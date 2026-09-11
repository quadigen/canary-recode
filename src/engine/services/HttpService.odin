package services

// wire:service global="HttpService"

import "core:fmt"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

HttpService_Class := classes.Class_Info{
	name   = "HttpService",
	parent = &Service_Class,
}

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
	service.http_enabled = false
	return &service.object
}

http_is_unreserved :: proc(value: u8) -> bool {
	return (value >= 'A' && value <= 'Z') ||
	       (value >= 'a' && value <= 'z') ||
	       (value >= '0' && value <= '9') ||
	       value == '-' ||
	       value == '_' ||
	       value == '.' ||
	       value == '~'
}

http_hex_value :: proc(value: u8) -> (u8, bool) {
	switch {
	case value >= '0' && value <= '9':
		return value-'0', true

	case value >= 'A' && value <= 'F':
		return value-'A'+10, true

	case value >= 'a' && value <= 'f':
		return value-'a'+10, true
	}

	return 0, false
}

http_url_encode :: proc(value: string) -> string {
	hex := "0123456789ABCDEF"
	result: [dynamic]u8

	for index in 0 ..< len(value) {
		byte := value[index]

		if http_is_unreserved(byte) {
			append(&result, byte)
			continue
		}

		append(&result, '%')
		append(&result, hex[byte >> 4])
		append(&result, hex[byte & 15])
	}

	return string(result[:])
}

http_url_decode :: proc(value: string) -> (string, bool) {
	result: [dynamic]u8

	index := 0
	for index < len(value) {
		if value[index] != '%' {
			append(&result, value[index])
			index += 1
			continue
		}

		if index+2 >= len(value) {
			delete(result)
			return "", false
		}

		high, high_ok := http_hex_value(value[index+1])
		low, low_ok := http_hex_value(value[index+2])

		if !high_ok || !low_ok {
			delete(result)
			return "", false
		}

		append(&result, (high << 4) | low)
		index += 3
	}

	return string(result[:]), true
}

http_generate_guid :: proc(wrap: bool) -> string {
	value := datatypes.UniqueId_New()
	raw := datatypes.UniqueId_ToString(value)

	if wrap {
		return fmt.tprintf(
			"{%s-%s-%s-%s-%s}",
			raw[0:8],
			raw[8:12],
			raw[12:16],
			raw[16:20],
			raw[20:32],
		)
	}

	return fmt.tprintf(
		"%s-%s-%s-%s-%s",
		raw[0:8],
		raw[8:12],
		raw[12:16],
		raw[16:20],
		raw[20:32],
	)
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

	case "GenerateGUID",
	     "UrlEncode",
	     "UrlDecode":
		vm.PushUserdataMethod(L, key)

	case:
		return false
	}

	return true
}

http_service_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	service := cast(^HttpService)object

	switch key {
	case "HttpEnabled":
		service.http_enabled = vm.ArgBoolean(L, value_index)

	case:
		return false
	}

	return true
}

http_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	switch method {
	case "GenerateGUID":
		wrap := vm.ArgOptionalBoolean(L, 2, false)
		vm.PushString(L, http_generate_guid(wrap))
		return 1, true

	case "UrlEncode":
		encoded := http_url_encode(vm.ArgString(L, 2))
		vm.PushString(L, encoded)
		delete(encoded)
		return 1, true

	case "UrlDecode":
		decoded, ok := http_url_decode(vm.ArgString(L, 2))
		if !ok {
			return vm.RaiseError(L, "invalid percent-encoded URL"), true
		}

		vm.PushString(L, decoded)
		delete(decoded)
		return 1, true
	}

	return 0, false
}

http_service_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	classes.Object_Destroy(object)
	free(cast(^HttpService)object)
}

Register_HttpService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&HttpService_Class,
		http_service_construct,
		http_service_destroy,
		creatable = false,
		get = http_service_get,
		set = http_service_set,
		namecall = http_service_namecall,
	)
}
