#+build !js
package services

import "core:bytes"
import "core:encoding/json"
import "core:fmt"
import "core:net"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

import vm "../vm"

import http "../util/odin-http"
import http_client "../util/odin-http/client"
KINEMIUM_API_PREFIX :: "/_kinemium/v1"

Kinemium_Meta :: struct {
	status:          int,
	headers:         string,
	etag:            string,
	version:         i64,
	filename:        string,
	errcode:         string,
	current_version: i64,
	has_version:     bool,
	has_current:     bool,
	body:            string,
}

Kinemium_Call_Options :: struct {
	query:        string,
	json:         string,
	raw_body:     string,
	content_type: string,
	headers:      string,
	raw:          bool,
	try_json:     bool,
	omit_auth:    bool,
}

Kinemium_Multipart_Part :: struct {
	name:         string,
	filename:     string,
	content_type: string,
	value:        string,
}

kinemium_url_encode :: proc(text: string, allocator := context.temp_allocator) -> string {
	return net.percent_encode(text, allocator)
}


kinemium_query :: proc(pairs: []string, allocator := context.temp_allocator) -> string {
	if len(pairs) == 0 {return ""}
	builder := strings.builder_make(allocator)
	strings.write_byte(&builder, '?')
	for pair, index in pairs {
		if index > 0 {strings.write_byte(&builder, '&')}
		strings.write_string(&builder, pair)
	}
	return strings.to_string(builder)
}


kinemium_header_value :: proc(raw_headers, name: string) -> (string, bool) {
	wanted := strings.to_lower(name, context.temp_allocator)
	remaining := raw_headers
	for line, ok := strings.split_lines_iterator(&remaining);
	    ok;
	    line, ok = strings.split_lines_iterator(&remaining) {
		colon := strings.index_byte(line, ':')
		if colon < 0 {continue}
		key := strings.trim_space(line[:colon])
		if strings.to_lower(key, context.temp_allocator) == wanted {
			return strings.trim_space(line[colon + 1:]), true
		}
	}
	return "", false
}

http_headers_to_string :: proc(headers: http.Headers) -> string {
	builder := strings.builder_make(context.allocator)
	for key, value in headers._kv {
		strings.write_string(&builder, key)
		strings.write_string(&builder, ": ")
		strings.write_string(&builder, value)
		strings.write_string(&builder, "\r\n")
	}
	return strings.to_string(builder)
}

kinemium_parse_version :: proc(text: string) -> (i64, bool) {
	trimmed := strings.trim(text, "\" \t")
	if value, ok := strconv.parse_i64(trimmed); ok {return value, true}
	return 0, false
}


kinemium_query_from_table :: proc(
	L: ^vm.State,
	index: int,
	allocator := context.allocator,
) -> string {
	if !vm.IsTable(L, index) {return ""}
	pairs: [dynamic]string
	defer delete(pairs)
	vm.PushNil(L)
	for vm.Next(L, index) {
		key, key_ok := vm.ToString(L, -2)
		if key_ok {
			value_index := vm.StackTop(L)
			value := ""
			#partial switch vm.TypeOf(L, value_index) {
			case .String:
				text, _ := vm.ToString(L, value_index)
				value = text
			case .Boolean:
				value = vm.ArgBoolean(L, value_index) ? "true" : "false"
			case .Number, .Integer:
				value = fmt.tprintf("%v", vm.ArgNumber(L, value_index))
			}
			append(
				&pairs,
				fmt.aprintf(
					"%s=%s",
					kinemium_url_encode(key, allocator),
					kinemium_url_encode(value, allocator),
					allocator = allocator,
				),
			)
		}
		vm.Pop(L)
	}
	if len(pairs) == 0 {return ""}
	slice.sort_by(pairs[:], proc(a, b: string) -> bool {return a < b})
	builder := strings.builder_make(allocator)
	strings.write_byte(&builder, '?')
	for pair, i in pairs {
		if i > 0 {strings.write_byte(&builder, '&')}
		strings.write_string(&builder, pair)
	}
	return strings.to_string(builder)
}


kinemium_encode_json :: proc(L: ^vm.State, index: int) -> string {
	value, err := http_lua_to_json(L, index, 0)
	if err != "" {
		delete(err)
		return ""
	}
	defer json.destroy_value(value)
	marshalled, marshal_err := json.marshal(value, {spec = .JSON}, context.temp_allocator)
	if marshal_err != nil {return ""}
	return strings.clone(string(marshalled))
}


kinemium_marshal :: proc(value: json.Value) -> string {
	marshalled, err := json.marshal(value, {spec = .JSON}, context.temp_allocator)
	if err != nil {return ""}
	return strings.clone(string(marshalled))
}

kinemium_options_from_table :: proc(L: ^vm.State, index: int) -> Kinemium_Call_Options {
	options: Kinemium_Call_Options
	if !vm.IsTable(L, index) {return options}

	vm.GetField(L, index, "query")
	options.query = kinemium_query_from_table(L, vm.StackTop(L))
	vm.Pop(L)

	vm.GetField(L, index, "json")
	if vm.IsTable(L, -1) {
		options.json = kinemium_encode_json(L, vm.StackTop(L))
	}
	vm.Pop(L)

	vm.GetField(L, index, "rawBody")
	options.raw_body = strings.clone(vm.ArgOptionalString(L, -1, ""))
	vm.Pop(L)

	vm.GetField(L, index, "contentType")
	options.content_type = strings.clone(vm.ArgOptionalString(L, -1, ""))
	vm.Pop(L)

	vm.GetField(L, index, "raw")
	options.raw = vm.ArgBoolean(L, -1)
	vm.Pop(L)

	options.try_json = !options.raw
	return options
}

kinemium_options_destroy :: proc(options: Kinemium_Call_Options) {
	if options.query != "" {delete(options.query)}
	if options.json != "" {delete(options.json)}
	if options.raw_body != "" {delete(options.raw_body)}
	if options.content_type != "" {delete(options.content_type)}
	if options.headers != "" {delete(options.headers)}
}

kinemium_boundary :: proc() -> string {
	@(static) counter: u64
	counter += 1
	return fmt.aprintf("kinemium%x%x", time.to_unix_nanoseconds(time.now()), counter)
}

kinemium_image_type :: proc(contents: string) -> (string, bool) {
	if strings.has_prefix(contents, "\x89PNG\r\n\x1a\n") {return "image/png", true}
	if strings.has_prefix(contents, "\xff\xd8\xff") {return "image/jpeg", true}
	if strings.has_prefix(contents, "GIF8") {return "image/gif", true}
	if strings.has_prefix(contents, "RIFF") &&
	   len(contents) >= 12 &&
	   contents[8:12] == "WEBP" {return "image/webp", true}
	return "", false
}

multipart_header_value :: proc(value: string) -> string {
	cleaned, _ := strings.replace_all(value, "\"", "_", context.temp_allocator)
	cleaned, _ = strings.replace_all(cleaned, "\r", "", context.temp_allocator)
	cleaned, _ = strings.replace_all(cleaned, "\n", "", context.temp_allocator)
	return cleaned
}

kinemium_multipart :: proc(
	parts: []Kinemium_Multipart_Part,
	allocator := context.allocator,
) -> (
	string,
	string,
) {
	boundary := kinemium_boundary()
	defer delete(boundary)
	builder := strings.builder_make(allocator)
	for part in parts {
		name := multipart_header_value(part.name)
		fmt.sbprintf(&builder, "--%s\r\n", boundary)
		if part.filename != "" {
			filename := multipart_header_value(part.filename)
			fmt.sbprintf(
				&builder,
				"Content-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\n",
				name,
				filename,
			)
		} else {
			fmt.sbprintf(&builder, "Content-Disposition: form-data; name=\"%s\"\r\n", name)
		}
		if part.content_type != "" {
			fmt.sbprintf(&builder, "Content-Type: %s\r\n", part.content_type)
		}
		strings.write_string(&builder, "\r\n")
		strings.write_string(&builder, part.value)
		strings.write_string(&builder, "\r\n")
	}
	fmt.sbprintf(&builder, "--%s--\r\n", boundary)


	return strings.to_string(
		builder,
	), fmt.aprintf("multipart/mixed; boundary=%s", boundary, allocator = allocator)
}


kinemium_call :: proc(
	base, token, method, path: string,
	options: Kinemium_Call_Options,
) -> (
	ok: bool,
	data: json.Value,
	body: string,
	meta: Kinemium_Meta,
) {
	url := strings.concatenate(
		{base, KINEMIUM_API_PREFIX, path, options.query},
		context.temp_allocator,
	)

	parsed_method, method_ok := http.method_parse(method)
	if !method_ok {
		message := strings.clone("Unsupported HTTP method")
		meta.body = message
		return false, nil, message, meta
	}

	req: http_client.Request
	http_client.request_init(&req, parsed_method)
	defer http_client.request_destroy(&req)

	http.headers_set(&req.headers, "Accept", options.raw ? "*/*" : "application/json")
	if !options.omit_auth {
		http.headers_set(
			&req.headers,
			"Authorization",
			strings.concatenate({"Bearer ", token}, context.temp_allocator),
		)
	}
	if options.content_type != "" {
		http.headers_set_content_type_string(&req.headers, options.content_type)
	}
	remaining := options.headers
	for line, has_line := strings.split_lines_iterator(&remaining);
	    has_line;
	    line, has_line = strings.split_lines_iterator(&remaining) {
		colon := strings.index_byte(line, ':')
		if colon < 0 {continue}
		http.headers_set(
			&req.headers,
			strings.trim_space(line[:colon]),
			strings.trim_space(line[colon + 1:]),
		)
	}

	body_text := options.raw_body != "" ? options.raw_body : options.json
	if body_text != "" {
		_, write_err := bytes.buffer_write_string(&req.body, body_text)
		if write_err != nil {
			message := strings.clone("Failed to write request body")
			meta.body = message
			return false, nil, message, meta
		}
	}

	response, request_err := http_client.request(&req, url)
	if request_err != nil {
		message := fmt.aprintf("Network error: %v", request_err)
		meta.body = message
		return false, nil, message, meta
	}
	defer http_client.response_destroy(&response)

	response_body, body_allocated, body_err := http_client.response_body(&response)
	if body_err != nil {
		message := strings.clone("Failed to read response body")
		meta.body = message
		return false, nil, message, meta
	}
	defer http_client.body_destroy(response_body, body_allocated)

	raw := http_service_body_string(response_body)
	out_body := strings.clone(raw)

	meta.status = int(response.status)
	meta.body = out_body
	meta.headers = http_headers_to_string(response.headers)
	if value, found := kinemium_header_value(meta.headers, "etag"); found {
		meta.etag = value
		meta.version, meta.has_version = kinemium_parse_version(value)
	}
	if value, found := kinemium_header_value(meta.headers, "content-disposition"); found {
		meta.filename = value
	}

	success := http.status_is_success(response.status)

	if options.raw && success {
		return true, nil, out_body, meta
	}

	if len(raw) == 0 {
		return success, nil, out_body, meta
	}

	if options.try_json {
		decoded, decode_err := json.parse_string(
			raw,
			parse_integers = false,
			allocator = context.allocator,
		)
		if decode_err == nil {
			if object, is_object := decoded.(json.Object); is_object {
				if code, has_code := object["errcode"].(json.String); has_code {
					meta.errcode = string(code)
				}
				if current, has_current := object["currentVersion"].(json.Integer); has_current {
					meta.current_version = i64(current)
					meta.has_current = true
				}
			}
			return success, decoded, out_body, meta
		}
	}
	return success, nil, out_body, meta
}

kinemium_call_destroy :: proc(data: json.Value, body: string, meta: Kinemium_Meta) {
	if data != nil {json.destroy_value(data)}
	if body != "" {delete(body)}
	if meta.headers != "" {delete(meta.headers)}
}

kinemium_push_meta :: proc(L: ^vm.State, meta: Kinemium_Meta) {
	vm.NewTable(L, 0, 8)
	vm.PushNumber(L, f64(meta.status))
	vm.SetField(L, -2, "status")

	vm.NewTable(L, 0, 0)
	remaining := meta.headers
	for line, ok := strings.split_lines_iterator(&remaining);
	    ok;
	    line, ok = strings.split_lines_iterator(&remaining) {
		colon := strings.index_byte(line, ':')
		if colon < 0 {continue}
		vm.PushString(L, strings.trim_space(line[colon + 1:]))
		vm.SetField(L, -2, strings.trim_space(line[:colon]))
	}
	vm.SetField(L, -2, "headers")

	if meta.etag != "" {vm.PushString(L, meta.etag); vm.SetField(L, -2, "etag")}
	if meta.has_version {vm.PushNumber(L, f64(meta.version)); vm.SetField(L, -2, "version")}
	if meta.filename != "" {vm.PushString(L, meta.filename); vm.SetField(L, -2, "filename")}
	if meta.errcode != "" {vm.PushString(L, meta.errcode); vm.SetField(L, -2, "errcode")}
	if meta.has_current {vm.PushNumber(L, f64(meta.current_version)); vm.SetField(L, -2, "currentVersion")}
}


kinemium_push_result :: proc(
	L: ^vm.State,
	ok: bool,
	data: json.Value,
	body: string,
	prefer_body: bool,
	meta: Kinemium_Meta,
) {
	vm.PushBoolean(L, ok)
	if prefer_body || data == nil {
		if body != "" {vm.PushString(L, body)} else {vm.PushNil(L)}
	} else {
		http_push_json_value(L, data)
	}
	kinemium_push_meta(L, meta)
}


kinemium_resolve_auth :: proc(
	registry: ^Registry,
	L: ^vm.State,
	session_index: int,
) -> (
	string,
	string,
	bool,
) {
	if session_index != 0 && vm.IsTable(L, session_index) {
		vm.GetField(L, session_index, "homeserver")
		homeserver := vm.ArgOptionalString(L, -1, "")
		vm.Pop(L)
		vm.GetField(L, session_index, "accessToken")
		token := vm.ArgOptionalString(L, -1, "")
		vm.Pop(L)
		if homeserver != "" && token != "" {return homeserver, token, true}
		return "", "", false
	}
	if descriptor := Find_Service(registry, "KinemiumService");
	   descriptor != nil && descriptor.object != nil {
		service := cast(^KinemiumService)descriptor.object
		if service.api_auth.token != "" {
			return service.api_auth.homeserver, service.api_auth.token, true
		}
	}
	if descriptor := Find_Service(registry, "MatrixService");
	   descriptor != nil && descriptor.object != nil {
		service := cast(^MatrixService)descriptor.object
		if service.session != nil && service.session.access_token != "" {
			return service.session.homeserver, service.session.access_token, true
		}
	}
	return "", "", false
}


kinemium_domain_call :: proc(
	L: ^vm.State,
	service: ^Service,
	session_index: int,
	method, path: string,
	options: Kinemium_Call_Options,
) -> i32 {
	defer kinemium_options_destroy(options)
	base, token, ok := kinemium_resolve_auth(service.data_model.registry, L, session_index)
	if !ok {
		vm.PushBoolean(L, false)
		vm.PushString(L, "Not logged in.")
		kinemium_push_meta(L, Kinemium_Meta{})
		return 3
	}
	success, data, body, meta := kinemium_call(base, token, method, path, options)
	defer kinemium_call_destroy(data, body, meta)
	kinemium_push_result(L, success, data, body, options.raw || !success, meta)
	return 3
}


kinemium_options_query :: proc(L: ^vm.State, params_index: int) -> Kinemium_Call_Options {
	options: Kinemium_Call_Options
	options.try_json = true
	if vm.IsTable(L, params_index) {
		options.query = kinemium_query_from_table(L, params_index)
	}
	return options
}


kinemium_options_json :: proc(L: ^vm.State, json_index: int) -> Kinemium_Call_Options {
	options: Kinemium_Call_Options
	options.try_json = true
	if vm.IsTable(L, json_index) {
		options.json = kinemium_encode_json(L, json_index)
	}
	return options
}


kinemium_options_empty :: proc() -> Kinemium_Call_Options {
	return Kinemium_Call_Options{try_json = true}
}


kinemium_options_raw :: proc() -> Kinemium_Call_Options {
	return Kinemium_Call_Options{raw = true}
}


kinemium_options_image :: proc(
	L: ^vm.State,
	bytes_index: int,
	out: ^Kinemium_Call_Options,
) -> bool {
	contents := vm.ArgString(L, bytes_index)
	mime, detected := kinemium_image_type(contents)
	if !detected {return false}
	out.raw_body = strings.clone(contents)
	out.content_type = strings.clone(mime)
	out.try_json = true
	return true
}


kinemium_upload_image_call :: proc(
	L: ^vm.State,
	service: ^Service,
	session_index, bytes_index: int,
	method, path: string,
) -> i32 {
	options: Kinemium_Call_Options
	if !kinemium_options_image(L, bytes_index, &options) {
		vm.PushBoolean(L, false)
		vm.PushString(L, "Unsupported image. Use PNG, JPEG, GIF or WebP.")
		kinemium_push_meta(L, Kinemium_Meta{})
		return 3
	}
	return kinemium_domain_call(L, service, session_index, method, path, options)
}


kinemium_multipart_call :: proc(
	L: ^vm.State,
	service: ^Service,
	session_index: int,
	method, path: string,
	parts: []Kinemium_Multipart_Part,
) -> i32 {
	body, content_type := kinemium_multipart(parts)
	options := Kinemium_Call_Options {
		raw_body     = body,
		content_type = content_type,
		try_json     = true,
	}
	return kinemium_domain_call(L, service, session_index, method, path, options)
}
