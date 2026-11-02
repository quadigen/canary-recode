#+build !js
package services

// wire:service global="matrix"

import "base:runtime"
import "core:bytes"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import fsutil "../fsutil"
import signals "../signals"
import vm "../vm"

import http "../util/odin-http"
import http_client "../util/odin-http/client"

MATRIX_DEFAULT_HOMESERVER :: "https://opus.quadigen.com"
MATRIX_DEVICE_NAME :: "Kinemium Engine"
MATRIX_SYNC_INTERVAL :: 2.0
MATRIX_SESSION_FILE :: "session.json"

// Matrix_Session_Persistence can be disabled by test harnesses so they never
// read or overwrite a developer's real saved session.
Matrix_Session_Persistence := true

// Matrix_Session_Path_Override lets tests point the saved session at a
// temporary file instead of the user's real data directory.
Matrix_Session_Path_Override := ""

Matrix_Session :: struct {
	homeserver:   string,
	user_id:      string,
	access_token: string,
	device_id:    string,
}

// Borrowed view of a session for the duration of a single call.
Matrix_View :: struct {
	homeserver:   string,
	user_id:      string,
	access_token: string,
	device_id:    string,
}

Matrix_Sync_Handlers :: struct {
	connected:       bool,
	event:           i32,
	message:         i32,
	typing:          i32,
	invite:          i32,
	sync:            i32,
	error:           i32,
	capabilities:    vm.Thread_Security_Capabilities,
	since:           string,
	filter:          string,
	include_initial: bool,
}

MatrixService :: struct {
	using service:    Service,
	session:          ^Matrix_Session,
	session_changed:  ^signals.Signal,
	remember_session: bool,
	sync:             Matrix_Sync_Handlers,
	sync_elapsed:     f64,
}

MatrixService_Class := classes.Class_Info {
	name   = "MatrixService",
	parent = &Service_Class,
}

matrix_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(MatrixService)
	service.service = Service_Init(&MatrixService_Class, "MatrixService", data_model)
	service.session_changed = signals.Create(service.service.data_model.registry.signal_registry)
	service.remember_session = true
	service.session = matrix_session_load()
	return &service.object
}

matrix_session_destroy :: proc(session: ^Matrix_Session) {
	if session == nil {return}
	delete(session.homeserver)
	delete(session.user_id)
	delete(session.access_token)
	delete(session.device_id)
	free(session)
}

matrix_session_clone :: proc(
	homeserver, user_id, access_token, device_id: string,
) -> ^Matrix_Session {
	session := new(Matrix_Session)
	session.homeserver = strings.clone(homeserver)
	session.user_id = strings.clone(user_id)
	session.access_token = strings.clone(access_token)
	session.device_id = strings.clone(device_id)
	return session
}

matrix_session_path :: proc() -> (string, bool) {
	if Matrix_Session_Path_Override != "" {
		return strings.clone(Matrix_Session_Path_Override), true
	}

	data_dir, err := os.user_data_dir(context.allocator)
	if err != nil {return "", false}
	defer delete(data_dir)

	kinemium_dir, dir_err := os.join_path({data_dir, "Kinemium"}, context.allocator)
	if dir_err != nil {return "", false}
	defer delete(kinemium_dir)

	if !os.exists(kinemium_dir) {
		if make_err := fsutil.Make_Directory_All(kinemium_dir); make_err != nil {return "", false}
	}

	path, path_err := os.join_path({kinemium_dir, MATRIX_SESSION_FILE}, context.allocator)
	if path_err != nil {return "", false}

	return path, true
}

matrix_session_clear :: proc() -> bool {
	if !Matrix_Session_Persistence {return false}

	path, ok := matrix_session_path()
	if !ok {return false}
	defer delete(path)

	if !os.exists(path) {return true}
	return os.remove(path) == nil
}

matrix_session_persist :: proc(session: ^Matrix_Session) -> bool {
	if !Matrix_Session_Persistence {return false}
	if session == nil {return matrix_session_clear()}

	path, ok := matrix_session_path()
	if !ok {return false}
	defer delete(path)

	object := make(json.Object, 4)
	defer delete(object)
	object["homeserver"] = json.String(session.homeserver)
	object["userId"] = json.String(session.user_id)
	object["accessToken"] = json.String(session.access_token)
	if session.device_id != "" {object["deviceId"] = json.String(session.device_id)}

	data, marshal_err := json.marshal(object, {spec = .JSON}, context.temp_allocator)
	if marshal_err != nil {return false}
	defer delete(data, context.temp_allocator)

	return os.write_entire_file(path, data) == nil
}

matrix_session_load :: proc() -> ^Matrix_Session {
	if !Matrix_Session_Persistence {return nil}

	path, ok := matrix_session_path()
	if !ok {return nil}
	defer delete(path)

	if !os.is_file(path) {return nil}

	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {return nil}
	defer delete(data)

	value, parse_err := json.parse_string(
		string(data),
		parse_integers = false,
		allocator = context.allocator,
	)
	if parse_err != nil {return nil}
	defer json.destroy_value(value)

	object := matrix_json_object(value)
	if object == nil {return nil}

	homeserver := matrix_json_string(matrix_json_get(object, "homeserver"))
	access_token := matrix_json_string(matrix_json_get(object, "accessToken"))
	if homeserver == "" || access_token == "" {return nil}

	return matrix_session_clone(
		homeserver,
		matrix_json_string(matrix_json_get(object, "userId")),
		access_token,
		matrix_json_string(matrix_json_get(object, "deviceId")),
	)
}

matrix_push_session :: proc(L: ^vm.State, session: ^Matrix_Session) {
	vm.NewTable(L, 0, 4)
	vm.PushString(L, session.homeserver)
	vm.SetField(L, -2, "homeserver")
	vm.PushString(L, session.user_id)
	vm.SetField(L, -2, "userId")
	vm.PushString(L, session.access_token)
	vm.SetField(L, -2, "accessToken")
	if session.device_id != "" {
		vm.PushString(L, session.device_id)
		vm.SetField(L, -2, "deviceId")
	}
}

// Reads the session table at `index`; returns an owned session or nil.
matrix_session_from_table :: proc(L: ^vm.State, index: int) -> ^Matrix_Session {
	if !vm.IsTable(L, index) {return nil}
	vm.GetField(L, index, "homeserver")
	homeserver := vm.ArgOptionalString(L, -1, "")
	vm.Pop(L)
	vm.GetField(L, index, "userId")
	user_id := vm.ArgOptionalString(L, -1, "")
	vm.Pop(L)
	vm.GetField(L, index, "accessToken")
	access_token := vm.ArgOptionalString(L, -1, "")
	vm.Pop(L)
	vm.GetField(L, index, "deviceId")
	device_id := vm.ArgOptionalString(L, -1, "")
	vm.Pop(L)
	if homeserver == "" || access_token == "" {return nil}
	return matrix_session_clone(homeserver, user_id, access_token, device_id)
}

// Returns a borrowed view: either from the explicit session arg or the service.
matrix_session_view :: proc(
	service: ^MatrixService,
	L: ^vm.State,
	index: int,
) -> (
	Matrix_View,
	bool,
) {
	if index != 0 && vm.IsTable(L, index) {
		view: Matrix_View
		vm.GetField(L, index, "homeserver")
		view.homeserver = vm.ArgOptionalString(L, -1, "")
		vm.Pop(L)
		vm.GetField(L, index, "accessToken")
		view.access_token = vm.ArgOptionalString(L, -1, "")
		vm.Pop(L)
		vm.GetField(L, index, "userId")
		view.user_id = vm.ArgOptionalString(L, -1, "")
		vm.Pop(L)
		vm.GetField(L, index, "deviceId")
		view.device_id = vm.ArgOptionalString(L, -1, "")
		vm.Pop(L)
		if view.homeserver != "" && view.access_token != "" {return view, true}
	}
	if service.session != nil {
		return Matrix_View {
				homeserver = service.session.homeserver,
				user_id = service.session.user_id,
				access_token = service.session.access_token,
				device_id = service.session.device_id,
			},
			true
	}
	return {}, false
}

matrix_set_session :: proc(L: ^vm.State, service: ^MatrixService, session: ^Matrix_Session) {
	if service.session != nil {matrix_session_destroy(service.session)}
	service.session = session
	if service.remember_session {matrix_session_persist(session)}
	if service.session_changed != nil {
		if session != nil {matrix_push_session(L, session)} else {vm.PushNil(L)}
		signals.Fire(L, service.session_changed, 1)
		vm.Pop(L)
	}
}

/* ------------------------------------------------------------------ */
/* JSON helpers                                                       */
/* ------------------------------------------------------------------ */

matrix_json_get :: proc(object: json.Object, key: string) -> json.Value {
	if object == nil {return nil}
	if value, ok := object[key]; ok {return value}
	return nil
}

matrix_json_object :: proc(value: json.Value) -> json.Object {
	if object, ok := value.(json.Object); ok {return object}
	return nil
}

matrix_json_array :: proc(value: json.Value) -> json.Array {
	if array, ok := value.(json.Array); ok {return array}
	return nil
}

matrix_json_string :: proc(value: json.Value) -> string {
	if text, ok := value.(json.String); ok {return string(text)}
	return ""
}

matrix_json_number :: proc(value: json.Value) -> f64 {
	#partial switch v in value {
	case json.Integer:
		return f64(i64(v))
	case json.Float:
		return f64(v)
	}
	return 0
}

matrix_encode :: proc(value: json.Value) -> string {
	data, err := json.marshal(value, {spec = .JSON}, context.temp_allocator)
	if err != nil {return ""}
	return string(data)
}

/* ------------------------------------------------------------------ */
/* Request core                                                       */
/* ------------------------------------------------------------------ */

// matrix_request returns (ok, data, error, status). `error` is allocated with
// context.allocator on network/parse failures and must be freed by the caller;
// on HTTP failures it is a temp-allocated description.
matrix_request :: proc(
	base, method, path, body, token: string,
) -> (
	ok: bool,
	data: json.Value,
	error: string,
	status: int,
) {
	url := strings.concatenate({base, path}, context.temp_allocator)

	parsed_method, method_ok := http.method_parse(method)
	if !method_ok {return false, nil, strings.clone("Unsupported HTTP method"), 0}

	req: http_client.Request
	http_client.request_init(&req, parsed_method)
	defer http_client.request_destroy(&req)

	http.headers_set(&req.headers, "Accept", "application/json")
	if token != "" {
		http.headers_set(
			&req.headers,
			"Authorization",
			strings.concatenate({"Bearer ", token}, context.temp_allocator),
		)
	}
	if body != "" {
		http.headers_set_content_type_string(&req.headers, "application/json")
		_, write_err := bytes.buffer_write_string(&req.body, body)
		if write_err != nil {return false, nil, strings.clone("Failed to write request body"), 0}
	}

	response, request_err := http_client.request(&req, url)
	if request_err != nil {
		return false, nil, fmt.aprintf("Network error: %v", request_err), 0
	}
	defer http_client.response_destroy(&response)

	raw_body, allocated, body_err := http_client.response_body(&response)
	if body_err != nil {
		return false, nil, strings.clone("Failed to read response body"), int(response.status)
	}
	defer http_client.body_destroy(raw_body, allocated)

	raw := http_service_body_string(raw_body)
	status = int(response.status)
	success := http.status_is_success(response.status)

	if len(raw) == 0 {
		if success {return true, nil, "", status}
		return false, nil, fmt.tprintf("Request failed (HTTP %d).", status), status
	}

	decoded, decode_err := json.parse_string(
		raw,
		parse_integers = false,
		allocator = context.allocator,
	)
	if decode_err != nil {
		if success {return true, nil, "", status}
		return false, nil, fmt.tprintf("Request failed (HTTP %d).", status), status
	}

	if success {return true, decoded, "", status}
	return false, decoded, matrix_describe_error(status, decoded), status
}

matrix_describe_error :: proc(status: int, data: json.Value) -> string {
	object := matrix_json_object(data)
	if object != nil {
		code := matrix_json_string(matrix_json_get(object, "errcode"))
		message := matrix_json_string(matrix_json_get(object, "error"))
		switch code {
		case "M_LIMIT_EXCEEDED":
			retry := matrix_json_number(matrix_json_get(object, "retry_after_ms"))
			if retry <= 0 {retry = 2000}
			seconds := int((retry + 999) / 1000)
			return fmt.tprintf("Too many attempts. Try again in %ds.", seconds)
		case "M_USER_IN_USE":
			return "That username is already taken."
		case "M_INVALID_USERNAME":
			return message != "" ? message : "That username is not valid."
		case "M_WEAK_PASSWORD":
			return message != "" ? message : "That password is too weak."
		case "M_FORBIDDEN":
			return(
				message != "" ? message : "Forbidden (wrong credentials, or registration is disabled)." \
			)
		case "M_USER_DEACTIVATED":
			return "This account has been deactivated."
		case "M_EXCLUSIVE":
			return "That username is reserved."
		case:
			if message != "" {return message}
		}
	}
	return fmt.tprintf("Request failed (HTTP %d).", status)
}

// Authed request against the resolved session.
matrix_authed :: proc(
	service: ^MatrixService,
	L: ^vm.State,
	session_index: int,
	method, path, body: string,
) -> (
	ok: bool,
	data: json.Value,
	error: string,
	status: int,
) {
	view, found := matrix_session_view(service, L, session_index)
	if !found {return false, nil, strings.clone("Not logged in."), 0}

	ok, data, error, status = matrix_request(
		view.homeserver,
		method,
		path,
		body,
		view.access_token,
	)

	if status == 401 && data != nil {
		object := matrix_json_object(data)
		if matrix_json_string(matrix_json_get(object, "errcode")) == "M_UNKNOWN_TOKEN" {
			if error != "" {delete(error)}
			error = strings.clone("Your session has expired. Please log in again.")
			if service.session != nil {matrix_set_session(L, service, nil)}
		}
	}
	return
}

/* ------------------------------------------------------------------ */
/* Value normalization                                                */
/* ------------------------------------------------------------------ */

matrix_trim :: proc(text: string, allocator := context.temp_allocator) -> string {
	return strings.trim_space(text)
}

matrix_normalize_homeserver :: proc(input: string) -> string {
	url := strings.trim_space(input)
	if url == "" {url = MATRIX_DEFAULT_HOMESERVER}

	if !matrix_has_scheme(url) {
		url = strings.concatenate({"https://", url}, context.allocator)
	} else {
		url = strings.clone(url)
	}

	if at := strings.index(url, "/_matrix"); at >= 0 {
		resized := url[:at]
		trimmed := strings.trim_right(resized, "/")
		next := strings.clone(trimmed)
		delete(url)
		url = next
	}

	trimmed := strings.trim_right(url, "/")
	if trimmed != url {
		result := strings.clone(trimmed)
		delete(url)
		return result
	}
	return url
}

matrix_has_scheme :: proc(url: string) -> bool {
	// matches ^%a[%w+.-]*://
	colon := strings.index(url, ":")
	if colon < 1 {return false}
	for i in 0 ..< colon {
		c := url[i]
		if i == 0 {
			if !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) {return false}
			continue
		}
		if !((c >= 'a' && c <= 'z') ||
			   (c >= 'A' && c <= 'Z') ||
			   (c >= '0' && c <= '9') ||
			   c == '+' ||
			   c == '.' ||
			   c == '-') {
			return false
		}
	}
	return len(url) > colon + 2 && url[colon + 1] == '/' && url[colon + 2] == '/'
}

matrix_normalize_username :: proc(input: string) -> string {
	name := strings.to_lower(strings.trim_space(input), context.allocator)
	if strings.has_prefix(name, "@") {
		without := strings.clone(name[1:])
		delete(name)
		name = without
	}
	if colon := strings.index_byte(name, ':'); colon >= 0 {
		trimmed := name[:colon]
		result := strings.clone(trimmed)
		delete(name)
		return result
	}
	return name
}

/* ------------------------------------------------------------------ */
/* Service methods                                                    */
/* ------------------------------------------------------------------ */

matrix_get_session :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	if service.session == nil {vm.PushNil(L)} else {matrix_push_session(L, service.session)}
	return 1
}

matrix_speaks_matrix :: proc(base: string) -> bool {
	ok, data, error, _ := matrix_request(base, "GET", "/_matrix/client/versions", "", "")
	defer if data != nil {json.destroy_value(data)}
	_ = error
	object := matrix_json_object(data)
	return ok && object != nil && matrix_json_get(object, "versions") != nil
}

matrix_resolve_homeserver :: proc(L: ^vm.State, input: string) -> (bool, string, bool) {
	base := matrix_normalize_homeserver(input)
	if matrix_speaks_matrix(base) {return true, base, true}

	ok, data, error, _ := matrix_request(base, "GET", "/.well-known/matrix/client", "", "")
	defer if data != nil {json.destroy_value(data)}
	_ = ok
	_ = error

	object := matrix_json_object(data)
	if object != nil {
		hs := matrix_json_object(matrix_json_get(object, "m.homeserver"))
		delegated := matrix_json_string(matrix_json_get(hs, "base_url"))
		if delegated != "" {
			delegated_base := matrix_normalize_homeserver(delegated)
			if matrix_speaks_matrix(delegated_base) {return true, delegated_base, true}
			delete(delegated_base)
		}
	}

	message := fmt.aprintf(
		"Could not find a Matrix homeserver at %s",
		base,
		allocator = context.allocator,
	)
	delete(base)
	return false, message, true
}

matrix_login :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	base := vm.ArgString(L, 2)
	username := vm.ArgString(L, 3)
	password := vm.ArgString(L, 4)

	identifier := make(json.Object, 1)
	defer delete(identifier)
	identifier["type"] = json.String("m.id.user")
	identifier["user"] = json.String(username)

	body := make(json.Object, 4)
	defer delete(body)
	body["type"] = json.String("m.login.password")
	body["identifier"] = json.Value(identifier)
	body["password"] = json.String(password)
	body["initial_device_display_name"] = json.String(MATRIX_DEVICE_NAME)

	ok, data, error, _ := matrix_request(
		base,
		"POST",
		"/_matrix/client/v3/login",
		matrix_encode(body),
		"",
	)
	defer if data != nil {json.destroy_value(data)}
	if !ok {
		message := error != "" ? error : "Login failed."
		vm.PushBoolean(L, false)
		vm.PushString(L, message)
		return 2
	}

	session, ok2 := matrix_session_from(base, data)
	if !ok2 {
		vm.PushBoolean(L, false)
		vm.PushString(L, "The server returned no access token.")
		return 2
	}
	matrix_set_session(L, service, session)
	vm.PushBoolean(L, true)
	matrix_push_session(L, session)
	return 2
}

matrix_session_from :: proc(base: string, data: json.Value) -> (^Matrix_Session, bool) {
	object := matrix_json_object(data)
	if object == nil {return nil, false}
	access_token := matrix_json_string(matrix_json_get(object, "access_token"))
	if access_token == "" {return nil, false}
	return matrix_session_clone(
			base,
			matrix_json_string(matrix_json_get(object, "user_id")),
			access_token,
			matrix_json_string(matrix_json_get(object, "device_id")),
		),
		true
}

matrix_logout :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	view, found := matrix_session_view(service, L, 2)
	if !found {
		vm.PushBoolean(L, false)
		vm.PushString(L, "Not logged in.")
		return 2
	}
	ok, data, error, status := matrix_request(
		view.homeserver,
		"POST",
		"/_matrix/client/v3/logout",
		"",
		view.access_token,
	)
	defer if data != nil {json.destroy_value(data)}
	if ok || status == 401 {
		if service.session != nil &&
		   view.homeserver == service.session.homeserver &&
		   view.access_token == service.session.access_token {
			matrix_set_session(L, service, nil)
		}
		vm.PushBoolean(L, true)
		vm.PushNil(L)
		return 2
	}
	vm.PushBoolean(L, false)
	vm.PushString(L, error)
	return 2
}

matrix_whoami :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	ok, data, error, _ := matrix_authed(
		service,
		L,
		2,
		"GET",
		"/_matrix/client/v3/account/whoami",
		"",
	)
	defer if data != nil {json.destroy_value(data)}
	vm.PushBoolean(L, ok)
	if ok {http_push_json_value(L, data)} else {vm.PushString(L, error)}
	return 2
}

matrix_check_username :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	base := vm.ArgString(L, 2)
	username := vm.ArgString(L, 3)
	path := strings.concatenate(
		{"/_matrix/client/v3/register/available?username=", kinemium_url_encode(username)},
		context.temp_allocator,
	)
	ok, data, error, _ := matrix_request(base, "GET", path, "", "")
	defer if data != nil {json.destroy_value(data)}
	vm.PushBoolean(L, ok)
	if ok {vm.PushNil(L)} else {vm.PushString(L, error)}
	return 2
}

matrix_register :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	base := vm.ArgString(L, 2)
	username := vm.ArgString(L, 3)
	password := vm.ArgString(L, 4)

	registration_token := ""
	if vm.IsTable(L, 5) {
		vm.GetField(L, 5, "registrationToken")
		registration_token = vm.ArgOptionalString(L, -1, "")
		vm.Pop(L)
	}

	path := "/_matrix/client/v3/register?kind=user"

	// First attempt with no auth.
	ok, data, error, status := matrix_request(
		base,
		"POST",
		path,
		matrix_register_body(username, password, nil, ""),
		"",
	)
	if ok {
		return matrix_finish_register(L, service, base, data, error)
	}

	object := matrix_json_object(data)
	flows := matrix_json_array(matrix_json_get(object, "flows"))
	if status != 401 || flows == nil {
		message := error != "" ? error : "Registration failed."
		if data != nil {json.destroy_value(data)}
		vm.PushBoolean(L, false)
		vm.PushString(L, message)
		return 2
	}

	session_id := matrix_json_string(matrix_json_get(object, "session"))
	chosen := matrix_choose_flow(flows, registration_token != "")

	if chosen == nil {
		message := matrix_unsupported_flow_message(flows)
		if data != nil {json.destroy_value(data)}
		vm.PushBoolean(L, false)
		vm.PushString(L, message)
		return 2
	}

	if data != nil {json.destroy_value(data)}

	result_data: json.Value = nil
	result_ok := false
	result_error := ""

	for stage in chosen {
		stage_name := matrix_json_string(stage)
		auth := make(json.Object, 2, context.temp_allocator)
		auth["type"] = json.String(stage_name)
		auth["session"] = json.String(session_id)
		if matrix_is_token_stage(stage_name) {auth["token"] = json.String(registration_token)}

		body := matrix_register_body(username, password, auth, "")
		attempt_ok, attempt_data, attempt_error, attempt_status := matrix_request(
			base,
			"POST",
			path,
			body,
			"",
		)
		delete(auth)

		result_ok = attempt_ok
		result_error = attempt_error
		if result_data != nil {json.destroy_value(result_data)}
		result_data = attempt_data

		if attempt_ok {break}
		interim :=
			attempt_status == 401 &&
			matrix_json_object(attempt_data) != nil &&
			matrix_json_get(matrix_json_object(attempt_data), "errcode") == nil
		if !interim {break}
	}

	if !result_ok {
		message := result_error != "" ? result_error : "Registration did not complete."
		if result_data != nil {json.destroy_value(result_data)}
		vm.PushBoolean(L, false)
		vm.PushString(L, message)
		return 2
	}

	return matrix_finish_register(L, service, base, result_data, result_error)
}

matrix_register_body :: proc(username, password: string, auth: json.Object, _: string) -> string {
	body := make(json.Object, 4, context.temp_allocator)
	body["username"] = json.String(username)
	body["password"] = json.String(password)
	body["initial_device_display_name"] = json.String(MATRIX_DEVICE_NAME)
	if auth != nil {body["auth"] = json.Value(auth)}
	return matrix_encode(body)
}

matrix_finish_register :: proc(
	L: ^vm.State,
	service: ^MatrixService,
	base: string,
	data: json.Value,
	error: string,
) -> i32 {
	defer if data != nil {json.destroy_value(data)}
	_ = error
	session, ok := matrix_session_from(base, data)
	if !ok {
		vm.PushBoolean(L, false)
		vm.PushString(
			L,
			"Account created, but the server returned no access token. Try logging in.",
		)
		return 2
	}
	matrix_set_session(L, service, session)
	vm.PushBoolean(L, true)
	matrix_push_session(L, session)
	return 2
}

matrix_choose_flow :: proc(flows: json.Array, has_token: bool) -> json.Array {
	for flow_value in flows {
		flow := matrix_json_object(flow_value)
		if flow == nil {continue}
		stages := matrix_json_array(matrix_json_get(flow, "stages"))
		usable := true
		for stage_value in stages {
			stage := matrix_json_string(stage_value)
			if stage == "m.login.dummy" {continue}
			if has_token && matrix_is_token_stage(stage) {continue}
			usable = false
			break
		}
		if usable {return stages}
	}
	return nil
}

matrix_is_token_stage :: proc(stage: string) -> bool {
	return(
		stage == "m.login.registration_token" ||
		stage == "org.matrix.msc3231.login.registration_token" \
	)
}

matrix_unsupported_flow_message :: proc(flows: json.Array) -> string {
	if len(flows) == 0 {return "This server's sign-up requirements are not supported."}
	first := matrix_json_object(flows[0])
	stages := matrix_json_array(matrix_json_get(first, "stages"))
	needs := strings.builder_make(context.temp_allocator)
	count := 0
	for stage_value in stages {
		stage := matrix_json_string(stage_value)
		if stage == "m.login.dummy" || matrix_is_token_stage(stage) {continue}
		if count > 0 {strings.write_string(&needs, ", ")}
		strings.write_string(&needs, matrix_stage_name(stage))
		count += 1
	}
	if count == 0 {return "This server's sign-up requirements are not supported."}
	return strings.concatenate(
		{"This server requires ", strings.to_string(needs), " to sign up."},
		context.allocator,
	)
}

matrix_stage_name :: proc(stage: string) -> string {
	switch stage {
	case "m.login.recaptcha":
		return "a captcha"
	case "m.login.email.identity":
		return "email verification"
	case "m.login.msisdn":
		return "phone verification"
	case "m.login.sso":
		return "single sign-on"
	case "m.login.terms":
		return "accepting terms of service"
	case "m.login.registration_token", "org.matrix.msc3231.login.registration_token":
		return "a registration token"
	}
	return stage
}

/* ------------------------------------------------------------------ */
/* Room / message methods                                             */
/* ------------------------------------------------------------------ */

matrix_push_ok_data :: proc(L: ^vm.State, ok: bool, data: json.Value, error: string) -> i32 {
	vm.PushBoolean(L, ok)
	if ok {
		if data != nil {http_push_json_value(L, data)} else {vm.PushNil(L)}
	} else if error != "" {
		vm.PushString(L, error)
	} else {
		vm.PushNil(L)
	}
	return 2
}

matrix_push_ok_message :: proc(L: ^vm.State, ok: bool, error: string) -> i32 {
	vm.PushBoolean(L, ok)
	if error != "" {vm.PushString(L, error)} else {vm.PushNil(L)}
	return 2
}

matrix_url :: proc(parts: ..string) -> string {
	return strings.concatenate(parts, context.temp_allocator)
}

matrix_get_joined_rooms :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	ok, data, error, _ := matrix_authed(
		service,
		L,
		2,
		"GET",
		"/_matrix/client/v3/joined_rooms",
		"",
	)
	defer if data != nil {json.destroy_value(data)}
	if !ok {return matrix_push_ok_data(L, false, nil, error)}
	object := matrix_json_object(data)
	joined := matrix_json_array(matrix_json_get(object, "joined_rooms"))
	vm.PushBoolean(L, true)
	if joined == nil {vm.NewTable(L, 0, 0)} else {http_push_json_value(L, json.Value(joined))}
	return 2
}

matrix_sync :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	namecall_filter(service, L)
	return matrix_sync_impl(L, service, 2)
}

matrix_sync_impl :: proc(L: ^vm.State, service: ^MatrixService, session_index: int) -> i32 {
	pairs: [dynamic]string
	defer delete(pairs)

	if vm.IsTable(L, 3) {
		vm.GetField(L, 3, "since")
		since := vm.ArgOptionalString(L, -1, "")
		vm.Pop(L)
		if since != "" {
			append(&pairs, matrix_url("since=", kinemium_url_encode(since)))
		}
		vm.GetField(L, 3, "timeout")
		if vm.IsNumber(L, -1) {
			append(&pairs, matrix_url("timeout=", fmt.tprintf("%d", int(vm.ArgNumber(L, -1)))))
		}
		vm.Pop(L)
		vm.GetField(L, 3, "filter")
		if vm.IsTable(L, -1) {
			encoded := kinemium_encode_json(L, vm.StackTop(L))
			if encoded != "" {
				append(&pairs, matrix_url("filter=", kinemium_url_encode(encoded)))
				delete(encoded)
			}
		} else if vm.IsString(L, -1) {
			append(&pairs, matrix_url("filter=", kinemium_url_encode(vm.ArgString(L, -1))))
		}
		vm.Pop(L)
		vm.GetField(L, 3, "fullState")
		if vm.IsBoolean(
			L,
			-1,
		) {append(&pairs, matrix_url("full_state=", vm.ArgBoolean(L, -1) ? "true" : "false"))}
		vm.Pop(L)
		vm.GetField(L, 3, "setPresence")
		if vm.IsString(
			L,
			-1,
		) {append(&pairs, matrix_url("set_presence=", kinemium_url_encode(vm.ArgString(L, -1))))}
		vm.Pop(L)
	}

	path := matrix_url("/_matrix/client/v3/sync", kinemium_query(pairs[:]))
	ok, data, error, status := matrix_authed(service, L, session_index, "GET", path, "")
	defer if data != nil {json.destroy_value(data)}

	if !ok {
		vm.PushBoolean(L, false)
		vm.PushString(L, error)
		vm.PushNumber(L, f64(status))
		return 3
	}
	vm.PushBoolean(L, true)
	http_push_json_value(L, data)
	vm.PushNumber(L, f64(status))
	return 3
}

// Reads a session arg and passes it to sync; kept separate so the pump can call
// matrix_sync_impl with session_index = 0.
namecall_filter :: proc(service: ^MatrixService, L: ^vm.State) {
	_ = service
	_ = L
}

matrix_get_rooms :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	pairs := [1]string{"timeout=0"}
	path := matrix_url("/_matrix/client/v3/sync", kinemium_query(pairs[:]))
	ok, data, error, _ := matrix_authed(service, L, 2, "GET", path, "")
	defer if data != nil {json.destroy_value(data)}
	if !ok {
		vm.PushBoolean(L, false)
		vm.PushString(L, error)
		vm.PushNil(L)
		return 3
	}
	view, _ := matrix_session_view(service, L, 2)
	object := matrix_json_object(data)
	next_batch := matrix_json_string(matrix_json_get(object, "next_batch"))
	vm.PushBoolean(L, true)
	matrix_push_summarized_rooms(L, data, view.user_id)
	vm.PushString(L, next_batch)
	return 3
}

matrix_get_room_state :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	room_id := vm.ArgString(L, 3)
	event_type := vm.ArgString(L, 4)
	path := matrix_url(
		"/_matrix/client/v3/rooms/",
		kinemium_url_encode(room_id),
		"/state/",
		kinemium_url_encode(event_type),
	)
	if vm.IsString(L, 5) && vm.ArgString(L, 5) != "" {
		path = matrix_url(path, "/", kinemium_url_encode(vm.ArgString(L, 5)))
	}
	ok, data, error, _ := matrix_authed(service, L, 2, "GET", path, "")
	defer if data != nil {json.destroy_value(data)}
	return matrix_push_ok_data(L, ok, data, error)
}

matrix_get_room_info :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	room_id := vm.ArgString(L, 3)
	_, found := matrix_session_view(service, L, 2)
	if !found {
		vm.PushBoolean(L, false)
		vm.PushString(L, "Not logged in.")
		return 2
	}

	vm.NewTable(L, 0, 6)
	vm.PushString(L, room_id)
	vm.SetField(L, -2, "roomId")

	matrix_fetch_state_field(service, L, room_id, "m.room.name", "name", "name")
	matrix_fetch_state_field(service, L, room_id, "m.room.topic", "topic", "topic")
	matrix_fetch_state_field(service, L, room_id, "m.room.canonical_alias", "alias", "alias")
	matrix_fetch_state_field(service, L, room_id, "m.room.avatar", "url", "avatarUrl")

	vm.GetField(L, -1, "name")
	name, has_name := vm.ToString(L, -1)
	vm.Pop(L)
	vm.GetField(L, -1, "alias")
	alias, has_alias := vm.ToString(L, -1)
	vm.Pop(L)
	display := room_id
	if has_name && name != "" {display = name} else if has_alias && alias != "" {display = alias}
	vm.PushString(L, display)
	vm.SetField(L, -2, "displayName")

	vm.PushBoolean(L, true)
	vm.PushValue(L, -2)
	vm.Remove(L, -3)
	return 2
}

matrix_fetch_state_field :: proc(
	service: ^MatrixService,
	L: ^vm.State,
	room_id, event_type, field, target: string,
) {
	path := matrix_url(
		"/_matrix/client/v3/rooms/",
		kinemium_url_encode(room_id),
		"/state/",
		kinemium_url_encode(event_type),
	)
	ok, data, error, _ := matrix_authed(service, L, 0, "GET", path, "")
	defer {
		if data != nil {json.destroy_value(data)}
		if error != "" {delete(error)}
	}
	if !ok {return}
	object := matrix_json_object(data)
	value := matrix_json_string(matrix_json_get(object, field))
	if value == "" {return}
	// The room table is at the top of the stack.
	vm.PushString(L, value)
	vm.SetField(L, -2, target)
}

matrix_get_members :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	room_id := vm.ArgString(L, 3)
	path := matrix_url(
		"/_matrix/client/v3/rooms/",
		kinemium_url_encode(room_id),
		"/joined_members",
	)
	ok, data, error, _ := matrix_authed(service, L, 2, "GET", path, "")
	defer if data != nil {json.destroy_value(data)}
	if !ok {return matrix_push_ok_data(L, false, nil, error)}

	object := matrix_json_object(data)
	joined := matrix_json_object(matrix_json_get(object, "joined"))
	vm.NewTable(L, 0, 0)
	index := 1
	if joined != nil {
		for user_id, info in joined {
			info_object := matrix_json_object(info)
			vm.NewTable(L, 0, 3)
			vm.PushString(L, user_id)
			vm.SetField(L, -2, "userId")
			display := matrix_json_string(matrix_json_get(info_object, "display_name"))
			if display == "" {display = user_id}
			vm.PushString(L, display)
			vm.SetField(L, -2, "displayName")
			avatar := matrix_json_string(matrix_json_get(info_object, "avatar_url"))
			if avatar != "" {vm.PushString(L, avatar); vm.SetField(L, -2, "avatarUrl")}
			vm.SetArrayValue(L, -2, index)
			index += 1
		}
	}
	vm.PushBoolean(L, true)
	vm.PushValue(L, -2)
	vm.Remove(L, -3)
	return 2
}

matrix_get_messages :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	room_id := vm.ArgString(L, 3)
	dir := "b"
	limit := "50"
	from := ""
	types_json := `{"types":["m.room.message"]}`
	if vm.IsTable(L, 4) {
		vm.GetField(L, 4, "dir")
		if vm.IsString(L, -1) && vm.ArgString(L, -1) != "" {dir = vm.ArgString(L, -1)}
		vm.Pop(L)
		vm.GetField(L, 4, "limit")
		if vm.IsNumber(L, -1) {limit = fmt.tprintf("%d", int(vm.ArgNumber(L, -1)))}
		vm.Pop(L)
		vm.GetField(L, 4, "from")
		if vm.IsString(L, -1) {from = vm.ArgString(L, -1)}
		vm.Pop(L)
	}
	pairs: [dynamic]string
	defer delete(pairs)
	append(&pairs, matrix_url("dir=", dir))
	append(&pairs, matrix_url("limit=", limit))
	if from != "" {append(&pairs, matrix_url("from=", kinemium_url_encode(from)))}
	append(&pairs, matrix_url("filter=", kinemium_url_encode(types_json)))

	path := matrix_url(
		"/_matrix/client/v3/rooms/",
		kinemium_url_encode(room_id),
		"/messages",
		kinemium_query(pairs[:]),
	)
	ok, data, error, _ := matrix_authed(service, L, 2, "GET", path, "")
	defer if data != nil {json.destroy_value(data)}
	if !ok {return matrix_push_ok_data(L, false, nil, error)}

	object := matrix_json_object(data)
	chunk := matrix_json_array(matrix_json_get(object, "chunk"))

	vm.NewTable(L, 0, 3)
	vm.NewTable(L, 0, len(chunk))
	for event_value, i in chunk {
		matrix_push_event(L, event_value)
		vm.SetArrayValue(L, -2, i + 1)
	}
	if dir == "b" {matrix_reverse_table(L, -1)}
	vm.SetField(L, -2, "messages")
	vm.PushString(L, matrix_json_string(matrix_json_get(object, "end")))
	vm.SetField(L, -2, "nextToken")
	vm.PushString(L, matrix_json_string(matrix_json_get(object, "start")))
	vm.SetField(L, -2, "startToken")

	vm.PushBoolean(L, true)
	vm.PushValue(L, -2)
	vm.Remove(L, -3)
	return 2
}

matrix_reverse_table :: proc(L: ^vm.State, index: int) {
	length := vm.RawLen(L, index)
	if length < 2 {return}

	// Resolve the table to an absolute stack slot: the values pushed below shift
	// relative indexes, and SetArrayValue must keep referring to the table.
	absolute := index
	if absolute < 0 {absolute = vm.StackTop(L) + 1 + absolute}

	for i in 0 ..< length / 2 {
		vm.RawGetIndex(L, absolute, i + 1) // T[i+1] (A)
		vm.RawGetIndex(L, absolute, length - i) // T[length-i] (B)
		vm.PushValue(L, -2) // A
		vm.PushValue(L, -2) // B
		vm.SetArrayValue(L, absolute, i + 1) // T[i+1] = B
		vm.SetArrayValue(L, absolute, length - i) // T[length-i] = A
		vm.Pop(L, 2)
	}
}

matrix_send_message :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	room_id := vm.ArgString(L, 3)
	text := vm.ArgString(L, 4)
	msgtype := "m.text"
	reply_to := ""
	if vm.IsTable(L, 5) {
		vm.GetField(L, 5, "msgtype")
		if vm.IsString(L, -1) && vm.ArgString(L, -1) != "" {msgtype = vm.ArgString(L, -1)}
		vm.Pop(L)
		vm.GetField(L, 5, "replyTo")
		if vm.IsString(L, -1) {reply_to = vm.ArgString(L, -1)}
		vm.Pop(L)
	}

	body := make(json.Object, 2, context.temp_allocator)
	body["msgtype"] = json.String(msgtype)
	body["body"] = json.String(text)
	if reply_to != "" {
		in_reply := make(json.Object, 1, context.temp_allocator)
		in_reply["event_id"] = json.String(reply_to)
		relates := make(json.Object, 1, context.temp_allocator)
		relates["m.in_reply_to"] = json.Value(in_reply)
		body["m.relates_to"] = json.Value(relates)
	}

	txn := matrix_new_txn_id()
	path := matrix_url(
		"/_matrix/client/v3/rooms/",
		kinemium_url_encode(room_id),
		"/send/m.room.message/",
		kinemium_url_encode(txn),
	)
	ok, data, error, _ := matrix_authed(service, L, 2, "PUT", path, matrix_encode(body))
	defer if data != nil {json.destroy_value(data)}
	if !ok {return matrix_push_ok_data(L, false, nil, error)}
	object := matrix_json_object(data)
	event_id := matrix_json_string(matrix_json_get(object, "event_id"))
	vm.PushBoolean(L, true)
	if event_id != "" {vm.PushString(L, event_id)} else {vm.PushNil(L)}
	return 2
}

matrix_mark_read :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	room_id := vm.ArgString(L, 3)
	event_id := vm.ArgString(L, 4)
	path := matrix_url(
		"/_matrix/client/v3/rooms/",
		kinemium_url_encode(room_id),
		"/receipt/m.read/",
		kinemium_url_encode(event_id),
	)
	ok, data, error, _ := matrix_authed(service, L, 2, "POST", path, "{}")
	defer if data != nil {json.destroy_value(data)}
	return matrix_push_ok_message(L, ok, error)
}

matrix_set_typing :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	room_id := vm.ArgString(L, 3)
	typing := vm.ArgBoolean(L, 4)
	view, found := matrix_session_view(service, L, 2)
	if !found {
		vm.PushBoolean(L, false)
		vm.PushString(L, "Not logged in.")
		return 2
	}
	body := make(json.Object, 2, context.temp_allocator)
	body["typing"] = json.Boolean(typing)
	if typing {
		timeout := 30000
		if vm.IsNumber(L, 5) {timeout = int(vm.ArgNumber(L, 5))}
		body["timeout"] = json.Integer(timeout)
	}
	user_id := view.user_id
	if user_id == "" && service.session != nil {user_id = service.session.user_id}
	path := matrix_url(
		"/_matrix/client/v3/rooms/",
		kinemium_url_encode(room_id),
		"/typing/",
		kinemium_url_encode(user_id),
	)
	ok, data, error, _ := matrix_authed(service, L, 0, "PUT", path, matrix_encode(body))
	defer if data != nil {json.destroy_value(data)}
	return matrix_push_ok_message(L, ok, error)
}

matrix_join_room :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	room := vm.ArgString(L, 3)
	path := matrix_url("/_matrix/client/v3/join/", kinemium_url_encode(room))
	ok, data, error, _ := matrix_authed(service, L, 2, "POST", path, "{}")
	defer if data != nil {json.destroy_value(data)}
	if !ok {return matrix_push_ok_data(L, false, nil, error)}
	object := matrix_json_object(data)
	room_id := matrix_json_string(matrix_json_get(object, "room_id"))
	vm.PushBoolean(L, true)
	if room_id != "" {vm.PushString(L, room_id)} else {vm.PushString(L, room)}
	return 2
}

matrix_room_action :: proc(L: ^vm.State, service: ^MatrixService, action: string) -> i32 {
	room_id := vm.ArgString(L, 3)
	path := matrix_url("/_matrix/client/v3/rooms/", kinemium_url_encode(room_id), "/", action)
	ok, data, error, _ := matrix_authed(service, L, 2, "POST", path, "{}")
	defer if data != nil {json.destroy_value(data)}
	return matrix_push_ok_message(L, ok, error)
}

matrix_invite_user :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	room_id := vm.ArgString(L, 3)
	user_id := vm.ArgString(L, 4)
	body := make(json.Object, 1, context.temp_allocator)
	body["user_id"] = json.String(user_id)
	path := matrix_url("/_matrix/client/v3/rooms/", kinemium_url_encode(room_id), "/invite")
	ok, data, error, _ := matrix_authed(service, L, 2, "POST", path, matrix_encode(body))
	defer if data != nil {json.destroy_value(data)}
	return matrix_push_ok_message(L, ok, error)
}

matrix_create_room :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	options := vm.IsTable(L, 3) ? L : nil
	_ = options
	is_public := false
	name := ""
	topic := ""
	alias := ""
	preset := ""
	is_direct := false
	invites: [dynamic]string
	defer delete(invites)

	if vm.IsTable(L, 3) {
		vm.GetField(L, 3, "isPublic")
		is_public = vm.ArgBoolean(L, -1)
		vm.Pop(L)
		vm.GetField(L, 3, "name")
		name = vm.ArgOptionalString(L, -1, "")
		vm.Pop(L)
		vm.GetField(L, 3, "topic")
		topic = vm.ArgOptionalString(L, -1, "")
		vm.Pop(L)
		vm.GetField(L, 3, "alias")
		alias = vm.ArgOptionalString(L, -1, "")
		vm.Pop(L)
		vm.GetField(L, 3, "preset")
		preset = vm.ArgOptionalString(L, -1, "")
		vm.Pop(L)
		vm.GetField(L, 3, "isDirect")
		is_direct = vm.ArgBoolean(L, -1)
		vm.Pop(L)
		vm.GetField(L, 3, "invite")
		if vm.IsTable(L, -1) {
			length := vm.RawLen(L, -1)
			for i in 1 ..= length {
				vm.RawGetIndex(L, -1, i)
				if vm.IsString(L, -1) {append(&invites, vm.ArgString(L, -1))}
				vm.Pop(L)
			}
		}
		vm.Pop(L)
	}
	if preset == "" {preset = is_public ? "public_chat" : "private_chat"}

	body := make(json.Object, 8, context.temp_allocator)
	if name != "" {body["name"] = json.String(name)}
	if topic != "" {body["topic"] = json.String(topic)}
	body["visibility"] = json.String(is_public ? "public" : "private")
	body["preset"] = json.String(preset)
	if alias != "" {body["room_alias_name"] = json.String(alias)}
	if vm.IsTable(L, 3) {
		vm.GetField(L, 3, "isDirect")
		present := !vm.IsNil(L, -1)
		vm.Pop(L)
		if present {body["is_direct"] = json.Boolean(is_direct)}
	}
	if len(invites) > 0 {
		array := make(json.Array, len(invites), context.temp_allocator)
		for invite, i in invites {array[i] = json.String(invite)}
		body["invite"] = json.Value(array)
	}

	ok, data, error, _ := matrix_authed(
		service,
		L,
		2,
		"POST",
		"/_matrix/client/v3/createRoom",
		matrix_encode(body),
	)
	defer if data != nil {json.destroy_value(data)}
	if !ok {return matrix_push_ok_data(L, false, nil, error)}
	object := matrix_json_object(data)
	room_id := matrix_json_string(matrix_json_get(object, "room_id"))
	vm.PushBoolean(L, true)
	if room_id != "" {vm.PushString(L, room_id)} else {vm.PushNil(L)}
	return 2
}

matrix_create_direct_room :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	user_id := vm.ArgString(L, 3)
	view, found := matrix_session_view(service, L, 2)
	if !found {
		vm.PushBoolean(L, false)
		vm.PushString(L, "Not logged in.")
		return 2
	}

	// createRoom with invite + is_direct.
	if !vm.IsTable(L, 3) { /* no-op */}
	invite_array := make(json.Array, 1, context.temp_allocator)
	invite_array[0] = json.String(user_id)
	body := make(json.Object, 4, context.temp_allocator)
	body["visibility"] = json.String("private")
	body["preset"] = json.String("trusted_private_chat")
	body["is_direct"] = json.Boolean(true)
	body["invite"] = json.Value(invite_array)

	ok, data, error, _ := matrix_authed(
		service,
		L,
		0,
		"POST",
		"/_matrix/client/v3/createRoom",
		matrix_encode(body),
	)
	if !ok {
		if data != nil {json.destroy_value(data)}
		vm.PushBoolean(L, false)
		vm.PushString(L, error)
		return 2
	}
	object := matrix_json_object(data)
	room_id := matrix_json_string(matrix_json_get(object, "room_id"))
	if data != nil {json.destroy_value(data)}

	// Update m.direct account data.
	path := matrix_url(
		"/_matrix/client/v3/user/",
		kinemium_url_encode(view.user_id),
		"/account_data/m.direct",
	)
	existing_ok, existing, _, _ := matrix_authed(service, L, 0, "GET", path, "")
	direct := make(json.Object, 1, context.temp_allocator)
	if existing_ok && matrix_json_object(existing) != nil {
		for key, value in matrix_json_object(existing) {direct[key] = value}
	}
	if existing != nil {json.destroy_value(existing)}

	list := matrix_json_array(matrix_json_get(direct, user_id))
	updated := make(json.Array, len(list) + 1, context.temp_allocator)
	for value, i in list {updated[i] = value}
	updated[len(list)] = json.String(room_id)
	direct[user_id] = json.Value(updated)

	_, put_data, _, _ := matrix_authed(
		service,
		L,
		0,
		"PUT",
		path,
		matrix_encode(json.Value(direct)),
	)
	if put_data != nil {json.destroy_value(put_data)}

	vm.PushBoolean(L, true)
	vm.PushString(L, room_id)
	return 2
}

matrix_get_profile :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	view, found := matrix_session_view(service, L, 2)
	if !found {
		vm.PushBoolean(L, false)
		vm.PushString(L, "Not logged in.")
		return 2
	}
	user_id := vm.IsString(L, 3) ? vm.ArgString(L, 3) : view.user_id
	if user_id == "" {user_id = view.user_id}
	path := matrix_url("/_matrix/client/v3/profile/", kinemium_url_encode(user_id))
	ok, data, error, _ := matrix_authed(service, L, 0, "GET", path, "")
	defer if data != nil {json.destroy_value(data)}
	if !ok {return matrix_push_ok_data(L, false, nil, error)}
	object := matrix_json_object(data)
	vm.NewTable(L, 0, 2)
	display := matrix_json_string(matrix_json_get(object, "displayname"))
	avatar := matrix_json_string(matrix_json_get(object, "avatar_url"))
	if display != "" {vm.PushString(L, display); vm.SetField(L, -2, "displayName")}
	if avatar != "" {vm.PushString(L, avatar); vm.SetField(L, -2, "avatarUrl")}
	vm.PushBoolean(L, true)
	vm.PushValue(L, -2)
	vm.Remove(L, -3)
	return 2
}

matrix_set_display_name :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	name := vm.ArgString(L, 3)
	view, found := matrix_session_view(service, L, 2)
	if !found {
		vm.PushBoolean(L, false)
		vm.PushString(L, "Not logged in.")
		return 2
	}
	body := make(json.Object, 1, context.temp_allocator)
	body["displayname"] = json.String(name)
	path := matrix_url(
		"/_matrix/client/v3/profile/",
		kinemium_url_encode(view.user_id),
		"/displayname",
	)
	ok, data, error, _ := matrix_authed(service, L, 0, "PUT", path, matrix_encode(body))
	defer if data != nil {json.destroy_value(data)}
	return matrix_push_ok_message(L, ok, error)
}

/* ------------------------------------------------------------------ */
/* Pure helpers                                                       */
/* ------------------------------------------------------------------ */

matrix_new_txn_id :: proc() -> string {
	@(static) counter: u64
	counter += 1
	return fmt.aprintf("studio-%x-%d", time.to_unix_nanoseconds(time.now()), counter)
}

matrix_push_event :: proc(L: ^vm.State, event: json.Value) {
	object := matrix_json_object(event)
	if object == nil {
		vm.NewTable(L, 0, 0)
		return
	}
	content := matrix_json_object(matrix_json_get(object, "content"))
	ms := matrix_json_number(matrix_json_get(object, "origin_server_ts"))

	vm.NewTable(L, 0, 10)
	matrix_set_string_field(L, "eventId", matrix_json_string(matrix_json_get(object, "event_id")))
	matrix_set_string_field(L, "sender", matrix_json_string(matrix_json_get(object, "sender")))
	matrix_set_string_field(L, "type", matrix_json_string(matrix_json_get(object, "type")))
	matrix_set_string_field(L, "msgtype", matrix_json_string(matrix_json_get(content, "msgtype")))
	matrix_set_string_field(L, "body", matrix_json_string(matrix_json_get(content, "body")))
	vm.PushNumber(L, ms)
	vm.SetField(L, -2, "timestampMs")
	vm.PushNumber(L, ms / 1000)
	vm.SetField(L, -2, "timestamp")
	matrix_set_string_field(
		L,
		"stateKey",
		matrix_json_string(matrix_json_get(object, "state_key")),
	)
	http_push_json_value(L, json.Value(content))
	vm.SetField(L, -2, "content")
	http_push_json_value(L, event)
	vm.SetField(L, -2, "raw")
}

matrix_set_string_field :: proc(L: ^vm.State, key, value: string) {
	if value == "" {return}
	vm.PushString(L, value)
	vm.SetField(L, -2, key)
}

matrix_parse_event :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	_ = service
	if vm.IsTable(L, 2) {
		value, err := http_lua_to_json(L, 2, 0)
		if err == "" {
			defer json.destroy_value(value)
			matrix_push_event(L, value)
			return 1
		}
		delete(err)
	}
	vm.NewTable(L, 0, 0)
	return 1
}

matrix_mxc_to_http :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	_ = service
	base := vm.ArgString(L, 2)
	mxc := vm.ArgOptionalString(L, 3, "")
	if mxc == "" {vm.PushNil(L); return 1}

	prefix := "/_matrix/media/v3"
	authenticated := false
	if vm.IsTable(L, 4) {
		vm.GetField(L, 4, "authenticated")
		authenticated = vm.ArgBoolean(L, -1)
		vm.Pop(L)
	}
	if authenticated {prefix = "/_matrix/client/v1/media"}

	rest := strings.trim_prefix(mxc, "mxc://")
	slash := strings.index_byte(rest, '/')
	if slash < 0 {vm.PushNil(L); return 1}
	server := rest[:slash]
	media_id := rest[slash + 1:]
	if cut := strings.index_any(media_id, "/?#"); cut >= 0 {media_id = media_id[:cut]}

	width := 0
	height := 0
	method := "crop"
	if vm.IsTable(L, 4) {
		vm.GetField(L, 4, "width")
		if vm.IsNumber(L, -1) {width = int(vm.ArgNumber(L, -1))}
		vm.Pop(L)
		vm.GetField(L, 4, "height")
		if vm.IsNumber(L, -1) {height = int(vm.ArgNumber(L, -1))}
		vm.Pop(L)
		vm.GetField(L, 4, "method")
		if vm.IsString(L, -1) {method = vm.ArgString(L, -1)}
		vm.Pop(L)
	}

	if width > 0 || height > 0 {
		if width == 0 {width = 64}
		if height == 0 {height = 64}
		pairs := [3]string {
			fmt.tprintf("width=%d", width),
			fmt.tprintf("height=%d", height),
			fmt.tprintf("method=%s", method),
		}
		url := matrix_url(
			base,
			prefix,
			"/thumbnail/",
			kinemium_url_encode(server),
			"/",
			kinemium_url_encode(media_id),
			kinemium_query(pairs[:]),
		)
		vm.PushString(L, url)
		return 1
	}

	url := matrix_url(
		base,
		prefix,
		"/download/",
		kinemium_url_encode(server),
		"/",
		kinemium_url_encode(media_id),
	)
	vm.PushString(L, url)
	return 1
}

matrix_describe_error_lua :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	_ = service
	status := int(vm.ArgNumber(L, 2))
	vm.PushString(L, matrix_describe_error_lua_value(L, status, 3))
	return 1
}

matrix_describe_error_lua_value :: proc(L: ^vm.State, status: int, data_index: int) -> string {
	if vm.IsTable(L, data_index) {
		vm.GetField(L, data_index, "errcode")
		code := vm.ArgOptionalString(L, -1, "")
		vm.Pop(L)
		vm.GetField(L, data_index, "error")
		message := vm.ArgOptionalString(L, -1, "")
		vm.Pop(L)
		vm.GetField(L, data_index, "retry_after_ms")
		retry := int(vm.ArgOptionalNumber(L, -1, 2000))
		vm.Pop(L)
		switch code {
		case "M_LIMIT_EXCEEDED":
			if retry <= 0 {retry = 2000}
			return fmt.aprintf("Too many attempts. Try again in %ds.", (retry + 999) / 1000)
		case "M_USER_IN_USE":
			return "That username is already taken."
		case "M_INVALID_USERNAME":
			return message != "" ? strings.clone(message) : "That username is not valid."
		case "M_WEAK_PASSWORD":
			return message != "" ? strings.clone(message) : "That password is too weak."
		case "M_FORBIDDEN":
			return(
				message != "" ? strings.clone(message) : "Forbidden (wrong credentials, or registration is disabled)." \
			)
		case "M_USER_DEACTIVATED":
			return "This account has been deactivated."
		case "M_EXCLUSIVE":
			return "That username is reserved."
		case:
			if message != "" {return strings.clone(message)}
		}
	}
	return fmt.aprintf("Request failed (HTTP %d).", status)
}

matrix_authed_request :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	method := vm.ArgString(L, 3)
	path := vm.ArgString(L, 4)
	body := ""
	if vm.IsTable(L, 5) {
		value, err := http_lua_to_json(L, 5, 0)
		if err == "" {
			body = matrix_encode(value)
			json.destroy_value(value)
		} else {
			delete(err)
		}
	}
	ok, data, error, _ := matrix_authed(service, L, 2, method, path, body)
	defer if data != nil {json.destroy_value(data)}
	vm.PushBoolean(L, ok)
	if ok {http_push_json_value(L, data)} else {vm.PushString(L, error)}
	vm.PushString(L, okay_error(ok, error))
	return 3
}

http_lua_to_json_or_nil :: proc(L: ^vm.State, index: int) -> json.Value {
	value, err := http_lua_to_json(L, index, 0)
	if err != "" {
		delete(err)
		return nil
	}
	return value
}

okay_error :: proc(ok: bool, error: string) -> string {
	return ok ? "" : error
}

/* ------------------------------------------------------------------ */
/* Session serialization for the sync pump                            */
/* ------------------------------------------------------------------ */

matrix_push_summarized_rooms :: proc(L: ^vm.State, data: json.Value, self_id: string) {
	rooms_data := matrix_json_object(matrix_json_get(matrix_json_object(data), "rooms"))
	direct := matrix_direct_map(data)

	vm.NewTable(L, 0, 0)
	index := 1

	join := matrix_json_object(matrix_json_get(rooms_data, "join"))
	if join != nil {
		for room_id, room_value in join {
			matrix_push_room_info(L, room_id, "join", room_value, self_id, direct)
			vm.SetArrayValue(L, -2, index)
			index += 1
		}
	}
	invite := matrix_json_object(matrix_json_get(rooms_data, "invite"))
	if invite != nil {
		for room_id, room_value in invite {
			matrix_push_room_info(L, room_id, "invite", room_value, self_id, direct)
			vm.SetArrayValue(L, -2, index)
			index += 1
		}
	}
	_ = self_id
}

matrix_direct_map :: proc(data: json.Value) -> json.Object {
	direct := make(json.Object, 0, context.temp_allocator)
	account := matrix_json_object(matrix_json_get(matrix_json_object(data), "account_data"))
	events := matrix_json_array(matrix_json_get(account, "events"))
	for event_value in events {
		event := matrix_json_object(event_value)
		if matrix_json_string(matrix_json_get(event, "type")) != "m.direct" {continue}
		content := matrix_json_object(matrix_json_get(event, "content"))
		if content == nil {continue}
		for user_id, room_ids in content {
			if list, is_array := room_ids.(json.Array); is_array {
				for room_id_value in list {
					direct[matrix_json_string(room_id_value)] = json.String(user_id)
				}
			}
		}
	}
	return direct
}

matrix_push_room_info :: proc(
	L: ^vm.State,
	room_id, membership: string,
	room: json.Value,
	self_id: string,
	direct: json.Object,
) {
	room_object := matrix_json_object(room)
	vm.NewTable(L, 0, 12)
	vm.PushString(L, room_id)
	vm.SetField(L, -2, "roomId")
	vm.PushString(L, membership)
	vm.SetField(L, -2, "membership")
	vm.PushString(L, room_id)
	vm.SetField(L, -2, "displayName")
	vm.NewTable(L, 0, 0)
	vm.SetField(L, -2, "heroes")
	vm.PushNumber(L, 0)
	vm.SetField(L, -2, "unread")
	vm.PushNumber(L, 0)
	vm.SetField(L, -2, "highlights")
	vm.PushBoolean(L, false)
	vm.SetField(L, -2, "isDirect")

	state := matrix_json_object(matrix_json_get(room_object, "state"))
	invite_state := matrix_json_object(matrix_json_get(room_object, "invite_state"))
	apply_events := matrix_json_array(matrix_json_get(state, "events"))
	if membership ==
	   "invite" {apply_events = matrix_json_array(matrix_json_get(invite_state, "events"))}
	matrix_apply_state_events(L, apply_events, self_id)

	timeline := matrix_json_object(matrix_json_get(room_object, "timeline"))
	timeline_events := matrix_json_array(matrix_json_get(timeline, "events"))
	matrix_apply_state_events(L, timeline_events, self_id)

	// last message (searching from the end)
	for i := len(timeline_events) - 1; i >= 0; i -= 1 {
		event := matrix_json_object(timeline_events[i])
		if matrix_json_string(matrix_json_get(event, "type")) == "m.room.message" {
			matrix_push_event(L, timeline_events[i])
			vm.SetField(L, -2, "lastMessage")
			break
		}
	}

	summary := matrix_json_object(matrix_json_get(room_object, "summary"))
	if heroes := matrix_json_array(matrix_json_get(summary, "m.heroes")); heroes != nil {
		http_push_json_value(L, json.Value(heroes))
		vm.SetField(L, -2, "heroes")
	}
	if count := matrix_json_get(summary, "m.joined_member_count"); count != nil {
		vm.PushNumber(L, matrix_json_number(count))
		vm.SetField(L, -2, "memberCount")
	}

	unread := matrix_json_object(matrix_json_get(room_object, "unread_notifications"))
	if unread != nil {
		vm.PushNumber(L, matrix_json_number(matrix_json_get(unread, "notification_count")))
		vm.SetField(L, -2, "unread")
		vm.PushNumber(L, matrix_json_number(matrix_json_get(unread, "highlight_count")))
		vm.SetField(L, -2, "highlights")
	}

	// finishRoomInfo
	direct_user := matrix_json_string(matrix_json_get(direct, room_id))
	if direct_user != "" {
		vm.PushString(L, direct_user)
		vm.SetField(L, -2, "directUserId")
		vm.PushBoolean(L, true)
		vm.SetField(L, -2, "isDirect")
	}
	matrix_finish_room_display_name(L, room_id, direct_user, "invitedBy")
}

matrix_finish_room_display_name :: proc(
	L: ^vm.State,
	room_id, direct_user, invited_field: string,
) {
	_ = invited_field
	vm.GetField(L, -1, "name")
	if vm.IsString(L, -1) && vm.ArgString(L, -1) != "" {
		name := vm.ArgString(L, -1)
		vm.Pop(L)
		vm.PushString(L, name)
		vm.SetField(L, -2, "displayName")
		return
	}
	vm.Pop(L)
	vm.GetField(L, -1, "alias")
	if vm.IsString(L, -1) && vm.ArgString(L, -1) != "" {
		alias := vm.ArgString(L, -1)
		vm.Pop(L)
		vm.PushString(L, alias)
		vm.SetField(L, -2, "displayName")
		return
	}
	vm.Pop(L)
	if direct_user != "" {
		vm.PushString(L, direct_user)
		vm.SetField(L, -2, "displayName")
		return
	}
	vm.GetField(L, -1, "heroes")
	if vm.RawLen(L, -1) > 0 {
		vm.RawGetIndex(L, -1, 1)
		hero := vm.ArgString(L, -1)
		vm.Pop(L, 2)
		vm.PushString(L, hero)
		vm.SetField(L, -2, "displayName")
		return
	}
	vm.Pop(L)
	vm.GetField(L, -1, "invitedBy")
	if vm.IsString(L, -1) && vm.ArgString(L, -1) != "" {
		invited := vm.ArgString(L, -1)
		vm.Pop(L)
		vm.PushString(L, fmt.aprintf("Invite from %s", invited))
		vm.SetField(L, -2, "displayName")
		return
	}
	vm.Pop(L)
}

matrix_apply_state_events :: proc(L: ^vm.State, events: json.Array, self_id: string) {
	for event_value in events {
		event := matrix_json_object(event_value)
		content := matrix_json_object(matrix_json_get(event, "content"))
		if content == nil {continue}
		if matrix_json_get(event, "state_key") == nil {continue}
		kind := matrix_json_string(matrix_json_get(event, "type"))
		state_key := matrix_json_string(matrix_json_get(event, "state_key"))
		switch kind {
		case "m.room.name":
			if state_key ==
			   "" {matrix_set_room_string(L, "name", matrix_json_string(matrix_json_get(content, "name")))}
		case "m.room.topic":
			if state_key ==
			   "" {matrix_set_room_string(L, "topic", matrix_json_string(matrix_json_get(content, "topic")))}
		case "m.room.canonical_alias":
			if state_key ==
			   "" {matrix_set_room_string(L, "alias", matrix_json_string(matrix_json_get(content, "alias")))}
		case "m.room.avatar":
			if state_key ==
			   "" {matrix_set_room_string(L, "avatarUrl", matrix_json_string(matrix_json_get(content, "url")))}
		case "m.room.create":
			matrix_set_room_string(
				L,
				"roomType",
				matrix_json_string(matrix_json_get(content, "type")),
			)
		case "m.room.member":
			if self_id != "" &&
			   state_key == self_id &&
			   matrix_json_string(matrix_json_get(content, "membership")) == "invite" {
				matrix_set_room_string(
					L,
					"invitedBy",
					matrix_json_string(matrix_json_get(event, "sender")),
				)
			}
		}
	}
}

matrix_set_room_string :: proc(L: ^vm.State, key, value: string) {
	if value == "" {return}
	vm.PushString(L, value)
	vm.SetField(L, -2, key)
}

/* ------------------------------------------------------------------ */
/* Sync pump                                                          */
/* ------------------------------------------------------------------ */

matrix_start_sync :: proc(L: ^vm.State, service: ^MatrixService) -> i32 {
	view, found := matrix_session_view(service, L, 2)
	if !found {
		vm.PushBoolean(L, false)
		vm.PushString(L, "Not logged in.")
		return 2
	}
	_ = view

	matrix_sync_disconnect(service)
	handlers := Matrix_Sync_Handlers {
		capabilities = vm.GetThreadSecurityCapabilities(L),
	}

	opts_index := 0
	if vm.IsTable(L, 3) {
		opts_index = 3
	} else if vm.IsTable(L, 2) {
		opts_index = 2
	}

	if opts_index != 0 {
		matrix_store_handler(L, opts_index, "onEvent", &handlers.event)
		matrix_store_handler(L, opts_index, "onMessage", &handlers.message)
		matrix_store_handler(L, opts_index, "onTyping", &handlers.typing)
		matrix_store_handler(L, opts_index, "onInvite", &handlers.invite)
		matrix_store_handler(L, opts_index, "onSync", &handlers.sync)
		matrix_store_handler(L, opts_index, "onError", &handlers.error)

		vm.GetField(L, opts_index, "since")
		if vm.IsString(L, -1) {handlers.since = strings.clone(vm.ArgString(L, -1))}
		vm.Pop(L)

		vm.GetField(L, opts_index, "includeInitial")
		if vm.IsBoolean(L, -1) {handlers.include_initial = vm.ArgBoolean(L, -1)}
		vm.Pop(L)
	}

	handlers.connected = true
	service.sync = handlers
	service.sync_elapsed = MATRIX_SYNC_INTERVAL

	vm.PushLightUserdata(L, service)
	vm.PushFunction(L, "StopSync", matrix_sync_stop_function, 1)
	return 1
}

matrix_store_handler :: proc(L: ^vm.State, table_index: int, field: string, target: ^i32) {
	vm.GetField(L, table_index, field)
	if vm.TypeOf(L, -1) == .Function {target^ = vm.RetainValue(L)}
	vm.Pop(L)
}

matrix_sync_stop_function :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	service := cast(^MatrixService)vm.UpvaluePointer(L)
	if service != nil {matrix_sync_disconnect(service)}
	return 0
}

matrix_sync_disconnect :: proc(service: ^MatrixService) {
	if !service.sync.connected {return}
	registry := service.service.data_model.registry.signal_registry
	refs := [6]i32 {
		service.sync.event,
		service.sync.message,
		service.sync.typing,
		service.sync.invite,
		service.sync.sync,
		service.sync.error,
	}
	for ref in refs {
		if ref > 0 {vm.ReleaseValue(registry.L, ref)}
	}
	if service.sync.since != "" {delete(service.sync.since)}
	if service.sync.filter != "" {delete(service.sync.filter)}
	service.sync = {}
}

Matrix_Service_Step :: proc(service: ^MatrixService, L: ^vm.State, delta_time: f64) {
	if !service.sync.connected || service.session == nil {return}
	service.sync_elapsed += delta_time
	if service.sync_elapsed < MATRIX_SYNC_INTERVAL {return}
	service.sync_elapsed = 0

	base := service.session.homeserver
	token := service.session.access_token

	pairs: [dynamic]string
	defer delete(pairs)
	if service.sync.since !=
	   "" {append(&pairs, matrix_url("since=", kinemium_url_encode(service.sync.since)))}
	append(&pairs, "timeout=0")
	if service.sync.include_initial && service.sync.since == "" {append(&pairs, "full_state=true")}
	path := matrix_url("/_matrix/client/v3/sync", kinemium_query(pairs[:]))

	ok, data, error, status := matrix_request(base, "GET", path, "", token)
	if !ok {
		if data != nil {json.destroy_value(data)}
		if status == 401 || status == 403 {
			matrix_sync_disconnect(service)
		}
		if service.sync.error > 0 {
			vm.PushString(L, error)
			matrix_fire_handler(L, service, service.sync.error, 1)
			vm.Pop(L)
		}
		return
	}
	defer json.destroy_value(data)

	next_batch := matrix_json_string(matrix_json_get(matrix_json_object(data), "next_batch"))
	matrix_dispatch_sync(L, service, data)
	if next_batch != "" {
		if service.sync.since != "" {delete(service.sync.since)}
		service.sync.since = strings.clone(next_batch)
	}

	if service.sync.sync > 0 {
		http_push_json_value(L, data)
		matrix_fire_handler(L, service, service.sync.sync, 1)
		vm.Pop(L)
	}
}

matrix_fire_handler :: proc(L: ^vm.State, service: ^MatrixService, ref: i32, count: int) {
	if ref <= 0 {return}
	registry := service.service.data_model.registry.signal_registry
	top := vm.StackTop(L)
	signals.Fire_Handler(registry, ref, service.sync.capabilities, top - count + 1, count)
}

matrix_dispatch_sync :: proc(L: ^vm.State, service: ^MatrixService, data: json.Value) {
	rooms := matrix_json_object(matrix_json_get(matrix_json_object(data), "rooms"))
	deliver := service.sync.since != "" || service.sync.include_initial

	join := matrix_json_object(matrix_json_get(rooms, "join"))
	if join != nil {
		for room_id, room_value in join {
			room_object := matrix_json_object(room_value)
			timeline := matrix_json_object(matrix_json_get(room_object, "timeline"))
			events := matrix_json_array(matrix_json_get(timeline, "events"))
			if deliver {
				for event_value in events {
					matrix_push_event(L, event_value)
					matrix_fire_handler(L, service, service.sync.event, 1)
					vm.Pop(L)

					if matrix_json_string(
						   matrix_json_get(matrix_json_object(event_value), "type"),
					   ) ==
					   "m.room.message" {
						matrix_push_event(L, event_value)
						vm.PushString(L, room_id)
						// fire(roomId, parsed) -> order (roomId, parsed)
						// stack: parsed, roomId -> need roomId, parsed
						vm.PushValue(L, -2)
						vm.Remove(L, -3)
						matrix_fire_handler(L, service, service.sync.message, 2)
						vm.Pop(L, 2)
					}
				}
			}
			ephemeral := matrix_json_object(matrix_json_get(room_object, "ephemeral"))
			for event_value in matrix_json_array(matrix_json_get(ephemeral, "events")) {
				event := matrix_json_object(event_value)
				if matrix_json_string(matrix_json_get(event, "type")) != "m.typing" {continue}
				content := matrix_json_object(matrix_json_get(event, "content"))
				user_ids := matrix_json_array(matrix_json_get(content, "user_ids"))
				vm.PushString(L, room_id)
				if user_ids !=
				   nil {http_push_json_value(L, json.Value(user_ids))} else {vm.NewTable(L, 0, 0)}
				matrix_fire_handler(L, service, service.sync.typing, 2)
				vm.Pop(L, 2)
			}
		}
	}

	invite := matrix_json_object(matrix_json_get(rooms, "invite"))
	if invite != nil {
		direct := matrix_direct_map(data)
		for room_id, room_value in invite {
			vm.PushString(L, room_id)
			matrix_push_room_info(
				L,
				room_id,
				"invite",
				room_value,
				service.session.user_id,
				direct,
			)
			matrix_fire_handler(L, service, service.sync.invite, 2)
			vm.Pop(L, 2)
		}
	}
}

/* ------------------------------------------------------------------ */
/* Dispatch                                                           */
/* ------------------------------------------------------------------ */

matrix_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^MatrixService)object
	switch key {
	case "DefaultHomeserver":
		vm.PushString(L, MATRIX_DEFAULT_HOMESERVER)
		return true
	case "DeviceName":
		vm.PushString(L, MATRIX_DEVICE_NAME)
		return true
	case "Session":
		matrix_get_session(L, service)
		return true
	case "SessionChanged":
		signals.Push(L, service.session_changed)
		return true
	case "RememberSession":
		vm.PushBoolean(L, service.remember_session)
		return true
	case "GetSession",
	     "SetSession",
	     "OnSessionChanged",
	     "SetRememberSession",
	     "NormalizeHomeserver",
	     "NormalizeUsername",
	     "DescribeError",
	     "ResolveHomeserver",
	     "Login",
	     "Logout",
	     "Whoami",
	     "CheckUsername",
	     "Register",
	     "AuthedRequest",
	     "NewTxnId",
	     "MxcToHttp",
	     "GetJoinedRooms",
	     "Sync",
	     "SummarizeSync",
	     "GetRooms",
	     "GetRoomState",
	     "GetRoomInfo",
	     "GetMembers",
	     "GetMessages",
	     "SendMessage",
	     "MarkRead",
	     "SetTyping",
	     "JoinRoom",
	     "LeaveRoom",
	     "ForgetRoom",
	     "InviteUser",
	     "CreateRoom",
	     "CreateDirectRoom",
	     "GetProfile",
	     "SetDisplayName",
	     "StartSync",
	     "ParseEvent":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

matrix_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^MatrixService)object
	switch method {
	case "GetSession":
		return matrix_get_session(L, service), true
	case "SetSession":
		matrix_set_session(L, service, matrix_session_from_table(L, 2))
		return 0, true
	case "SetRememberSession":
		{
			enabled := true
			if vm.IsBoolean(L, 2) {enabled = vm.ArgBoolean(L, 2)}
			service.remember_session = enabled
			if enabled {
				if service.session != nil {matrix_session_persist(service.session)}
			} else {
				matrix_session_clear()
			}
			return 0, true
		}
	case "NormalizeHomeserver":
		vm.PushString(L, matrix_normalize_homeserver(vm.ArgString(L, 2)))
		return 1, true
	case "NormalizeUsername":
		vm.PushString(L, matrix_normalize_username(vm.ArgString(L, 2)))
		return 1, true
	case "DescribeError":
		return matrix_describe_error_lua(L, service), true
	case "ResolveHomeserver":
		{
			ok, message, _ := matrix_resolve_homeserver(L, vm.ArgString(L, 2))
			vm.PushBoolean(L, ok)
			vm.PushString(L, message)
			return 2, true
		}
	case "NewTxnId":
		vm.PushString(L, matrix_new_txn_id())
		return 1, true
	case "Login":
		return matrix_login(L, service), true
	case "Register":
		return matrix_register(L, service), true
	case "Logout":
		return matrix_logout(L, service), true
	case "Whoami":
		return matrix_whoami(L, service), true
	case "CheckUsername":
		return matrix_check_username(L, service), true
	case "AuthedRequest":
		return matrix_authed_request(L, service), true
	case "MxcToHttp":
		return matrix_mxc_to_http(L, service), true
	case "ParseEvent":
		return matrix_parse_event(L, service), true
	case "GetJoinedRooms":
		return matrix_get_joined_rooms(L, service), true
	case "Sync":
		return matrix_sync_impl(L, service, 2), true
	case "SummarizeSync":
		{
			if vm.IsTable(L, 2) {
				value, err := http_lua_to_json(L, 2, 0)
				if err == "" {
					defer json.destroy_value(value)
					matrix_push_summarized_rooms(L, value, vm.ArgOptionalString(L, 3, ""))
					return 1, true
				}
				delete(err)
			}
			vm.NewTable(L, 0, 0)
			return 1, true
		}
	case "GetRooms":
		return matrix_get_rooms(L, service), true
	case "GetRoomState":
		return matrix_get_room_state(L, service), true
	case "GetRoomInfo":
		return matrix_get_room_info(L, service), true
	case "GetMembers":
		return matrix_get_members(L, service), true
	case "GetMessages":
		return matrix_get_messages(L, service), true
	case "SendMessage":
		return matrix_send_message(L, service), true
	case "MarkRead":
		return matrix_mark_read(L, service), true
	case "SetTyping":
		return matrix_set_typing(L, service), true
	case "JoinRoom":
		return matrix_join_room(L, service), true
	case "LeaveRoom":
		return matrix_room_action(L, service, "leave"), true
	case "ForgetRoom":
		return matrix_room_action(L, service, "forget"), true
	case "InviteUser":
		return matrix_invite_user(L, service), true
	case "CreateRoom":
		return matrix_create_room(L, service), true
	case "CreateDirectRoom":
		return matrix_create_direct_room(L, service), true
	case "GetProfile":
		return matrix_get_profile(L, service), true
	case "SetDisplayName":
		return matrix_set_display_name(L, service), true
	case "OnSessionChanged":
		signals.Push(L, service.session_changed)
		vm.PushUserdataMethod(L, "Connect")
		return 1, true
	case "StartSync":
		return matrix_start_sync(L, service), true
	}
	return 0, false
}

matrix_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^MatrixService)object
	matrix_session_destroy(service.session)
	matrix_sync_disconnect(service)
	if service.session_changed != nil {signals.Destroy(service.session_changed)}
	classes.Object_Destroy(object)
	free(service)
}

Register_MatrixService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&MatrixService_Class,
		matrix_service_construct,
		matrix_service_destroy,
		creatable = false,
		get = matrix_service_get,
		namecall = matrix_service_namecall,
	)
}
