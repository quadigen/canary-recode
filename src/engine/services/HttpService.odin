#+build !js
package services

// wire:service global="httpService"

import "core:bytes"
import "core:fmt"
import "core:net"
import "core:strings"
import "core:time"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import json "core:encoding/json"

import http "../util/odin-http"
import http_client "../util/odin-http/client"

HttpService_Class := classes.Class_Info{
	name   = "HttpService",
	parent = &Service_Class,
}

guid_counter: u64 = 1

HttpService :: struct {
	using service: Service,

	http_enabled: bool,
}

http_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(HttpService)

	service.service = Service_Init(
		&HttpService_Class,
		"HttpService",
		data_model,
	)

	service.http_enabled = true

	return &service.object
}

http_service_body_string :: proc(body: http_client.Body_Type) -> string {
	switch value in body {
	case http_client.Body_Plain:
		return string(value)

	case http_client.Body_Url_Encoded:
		builder := strings.builder_make(context.temp_allocator)

		first := true

		for key, item in value {
			if !first {
				strings.write_byte(&builder, '&')
			}

			first = false

			encoded_key := net.percent_encode(
				key,
				context.temp_allocator,
			)

			encoded_value := net.percent_encode(
				item,
				context.temp_allocator,
			)

			strings.write_string(&builder, encoded_key)
			strings.write_byte(&builder, '=')
			strings.write_string(&builder, encoded_value)
		}

		return strings.to_string(builder)

	case http_client.Body_Error:
		return ""
	}

	return ""
}

http_service_apply_headers :: proc(
	L: ^vm.State,
	req: ^http_client.Request,
	table_index: int,
	allocated_keys: ^[dynamic]string,
) {
	if !vm.IsTable(L, table_index) {
		return
	}

	vm.PushNil(L)

	for vm.Next(L, table_index) {
		key, key_ok := vm.ToString(L, -2)
		value, value_ok := vm.ToString(L, -1)

		if key_ok && value_ok {
			allocated_key := http.headers_set(
				&req.headers,
				key,
				value,
			)

			append(allocated_keys, allocated_key)
		}

		vm.Pop(L)
	}
}

HttpService_GetAsync :: proc(
	service: ^HttpService,
	url: string,
	allocator := context.allocator,
) -> (body: string, ok: bool) {
	if !service.http_enabled {
		return "", false
	}

	response, err := http_client.get(url, allocator)
	if err != nil {
		return "", false
	}
	defer http_client.response_destroy(&response)

	response_body, body_allocated, body_err :=
		http_client.response_body(&response, allocator = allocator)

	if body_err != nil {
		return "", false
	}

	defer http_client.body_destroy(
		response_body,
		body_allocated,
		allocator,
	)

	if !http.status_is_success(response.status) {
		return "", false
	}

	#partial switch value in response_body {
	case http_client.Body_Plain:
		return strings.clone(string(value), allocator), true
	}

	return "", false
}

HttpService_GetJSON :: proc(
	service: ^HttpService,
	url: string,
	output: ^$T,
	allocator := context.allocator,
) -> bool {
	body, ok := HttpService_GetAsync(service, url, allocator)
	if !ok {
		return false
	}
	defer delete(body, allocator)

	err := json.unmarshal_string(body, output, allocator = allocator)
	return err == nil
}

http_service_send :: proc(
	L: ^vm.State,
	method: http.Method,
	url: string,
	request_body: string = "",
	content_type: string = "",
	headers_index: int = 0,
	return_response_table: bool = false,
	require_success: bool = true,
) -> i32 {
	req: http_client.Request

	http_client.request_init(&req, method)

	allocated_header_keys := make([dynamic]string)

	defer {
		http_client.request_destroy(&req)

		for key in allocated_header_keys {
			delete(key)
		}

		delete(allocated_header_keys)
	}

	if content_type != "" {
		http.headers_set_content_type_string(
			&req.headers,
			content_type,
		)
	}

	if headers_index != 0 {
		http_service_apply_headers(
			L,
			&req,
			headers_index,
			&allocated_header_keys,
		)
	}

	if request_body != "" {
		_, write_error := bytes.buffer_write_string(
			&req.body,
			request_body,
		)

		if write_error != nil {
			return vm.RaiseError(
				L,
				fmt.tprintf(
					"HttpService failed to write request body: %v",
					write_error,
				),
			)
		}
	}

	response, request_error := http_client.request(
		&req,
		url,
	)

	if request_error != nil {
		return vm.RaiseError(
			L,
			fmt.tprintf(
				"HttpService request failed: %v",
				request_error,
			),
		)
	}

	defer http_client.response_destroy(&response)

	response_body, body_allocated, body_error :=
		http_client.response_body(&response)

	if body_error != nil {
		return vm.RaiseError(
			L,
			fmt.tprintf(
				"HttpService failed to read response body: %v",
				body_error,
			),
		)
	}

	defer http_client.body_destroy(
		response_body,
		body_allocated,
	)

	body := http_service_body_string(response_body)

	status_code := int(response.status)
	status_line := http.status_string(response.status)

	status_message := status_line

	if len(status_line) > 4 {
		status_message = status_line[4:]
	}

	success := http.status_is_success(response.status)

	if return_response_table {
		vm.NewTable(L, 0, 5)

		vm.PushBoolean(L, success)
		vm.SetField(L, -2, "Success")

		vm.PushNumber(L, f64(status_code))
		vm.SetField(L, -2, "StatusCode")

		vm.PushString(L, status_message)
		vm.SetField(L, -2, "StatusMessage")

		vm.PushString(L, body)
		vm.SetField(L, -2, "Body")

		vm.NewTable(
			L,
			0,
			http.headers_count(response.headers),
		)

		for key, value in response.headers._kv {
			vm.PushString(L, value)
			vm.SetField(L, -2, key)
		}

		vm.SetField(L, -2, "Headers")

		return 1
	}

	if require_success && !success {
		return vm.RaiseError(
			L,
			fmt.tprintf(
				"HttpService request failed with HTTP %s",
				status_line,
			),
		)
	}

	vm.PushString(L, body)

	return 1
}

http_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^HttpService)object

	switch key {
	case "HttpEnabled":
		vm.PushBoolean(L, service.http_enabled)
		return true

	case "GetAsync",
	     "PostAsync",
	     "RequestAsync",
	     "GenerateGUID",
	     "JSONDecode",
	     "JSONEncode",
	     "UrlEncode":
		vm.PushUserdataMethod(L, key)
		return true
	}

	return false
}

http_service_push_guid :: proc(L: ^vm.State, bracketed: bool) {
	seed := time.now()
	raw := u128(time.to_unix_nanoseconds(seed))
	raw ~= u128(seed._nsec) << 64
	raw ~= u128(guid_counter)
	guid_counter += 1

	guid: [16]u8
	for index in 0 ..< 16 {
		guid[index] = u8(raw >> (u8(index % 16) * 8))
	}

	guid[6] = guid[6] & 0x0f | 0x40
	guid[8] = guid[8] & 0x3f | 0x80

	out: [36]u8
	hex_digits := "0123456789abcdef"
	hex_nibbles := [16]u8{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}

	group_sizes := [5]int{4, 2, 2, 2, 6}
	group_index := 0
	position := 0
	byte_index := 0
	for size in group_sizes {
		for _ in 0 ..< size {
			high := hex_nibbles[guid[byte_index] >> 4]
			low := hex_nibbles[guid[byte_index] & 0x0f]
			out[position] = hex_digits[high]
			out[position + 1] = hex_digits[low]
			position += 2
			byte_index += 1
		}
		if group_index < 4 {
			out[position] = '-'
			position += 1
		}
		group_index += 1
	}

	if bracketed {
		vm.PushString(L, fmt.tprintf("{%s}", string(out[:])))
	} else {
		vm.PushString(L, string(out[:]))
	}
}

http_push_json_value :: proc(L: ^vm.State, value: json.Value) {
	#partial switch v in value {
	case json.Null:
		vm.PushNil(L)
	case json.Integer:
		vm.PushNumber(L, f64(i64(v)))
	case json.Float:
		vm.PushNumber(L, f64(v))
	case json.Boolean:
		vm.PushBoolean(L, bool(v))
	case json.String:
		vm.PushString(L, string(v))
	case json.Array:
		vm.NewTable(L, 0, 0)
		for item, index in v {
			http_push_json_value(L, item)
			vm.SetArrayValue(L, -2, index + 1)
		}
	case json.Object:
		vm.NewTable(L, 0, 0)
		for key, item in v {
			http_push_json_value(L, item)
			vm.SetField(L, -2, string(key))
		}
	}
}

http_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method_name: string,
) -> (i32, bool) {
	service := cast(^HttpService)object

	switch method_name {
	case "GetAsync":
		if !service.http_enabled {
			return vm.RaiseError(
				L,
				"HTTP requests are disabled",
			), true
		}

		url := vm.ArgString(L, 2)

		return http_service_send(
			L,
			.Get,
			url,
		), true

	case "PostAsync":
		if !service.http_enabled {
			return vm.RaiseError(
				L,
				"HTTP requests are disabled",
			), true
		}

		url := vm.ArgString(L, 2)
		body := vm.ArgString(L, 3)

		content_type := vm.ArgOptionalString(
			L,
			4,
			"application/json",
		)

		return http_service_send(
			L,
			.Post,
			url,
			body,
			content_type,
		), true

	case "RequestAsync":
		if !service.http_enabled {
			return vm.RaiseError(
				L,
				"HTTP requests are disabled",
			), true
		}

		if !vm.IsTable(L, 2) {
			return vm.RaiseError(
				L,
				"RequestAsync expects a request table",
			), true
		}

		vm.GetField(L, 2, "Url")

		if !vm.IsString(L, -1) {
			vm.Pop(L)

			return vm.RaiseError(
				L,
				"RequestAsync requires Url",
			), true
		}

		url := vm.ArgString(L, -1)
		vm.Pop(L)

		vm.GetField(L, 2, "Method")
		method_string := vm.ArgOptionalString(L, -1, "GET")
		vm.Pop(L)

		http_method, method_ok := http.method_parse(method_string)

		if !method_ok {
			return vm.RaiseError(
				L,
				fmt.tprintf(
					"Unsupported HTTP method '%s'",
					method_string,
				),
			), true
		}

		vm.GetField(L, 2, "Body")
		body := vm.ArgOptionalString(L, -1, "")
		vm.Pop(L)

		headers_index := 0

		vm.GetField(L, 2, "Headers")

		if vm.IsTable(L, -1) {
			headers_index = vm.StackTop(L)
		} else {
			vm.Pop(L)
		}

		return http_service_send(
			L,
			http_method,
			url,
			body,
			"",
			headers_index,
			true,
			false,
		), true
	case "JSONDecode":
		value := vm.ArgString(L, 2)
		decoded, decode_err := json.parse_string(
			value,
			parse_integers = false,
			allocator = context.allocator,
		)
		if decode_err != nil {
			return vm.RaiseError(L, "HttpService:JSONDecode: the input is not valid JSON"), true
		}
		defer json.destroy_value(decoded)
		http_push_json_value(L, decoded)
		return 1, true

	case "JSONEncode":
		value := vm.ArgString(L, 2)
		vm.PushString(L, value)
		return 1, true

	case "GenerateGUID":
		bracketed := vm.ArgBoolean(L, 2)
		http_service_push_guid(L, bracketed)
		return 1, true

	case "UrlEncode":
		value := vm.ArgString(L, 2)

		encoded := net.percent_encode(
			value,
			context.temp_allocator,
		)

		vm.PushString(L, encoded)

		return 1, true
	}

	return 0, false
}

http_service_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	service := cast(^HttpService)object

	classes.Object_Destroy(object)

	free(service)
}

Register_HttpService_Class :: proc(
	registry: ^classes.Registry,
) {
	classes.Register_Class(
		registry,
		&HttpService_Class,
		http_service_construct,
		http_service_destroy,
		creatable = false,
		get       = http_service_get,
		namecall  = http_service_namecall,
	)
}
