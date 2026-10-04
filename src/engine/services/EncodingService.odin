package services

// wire:service global="EncodingService"

import "core:strings"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

EncodingService_Class := classes.Class_Info{
	name   = "EncodingService",
	parent = &Service_Class,
}

EncodingService :: struct {
	using service: Service,
}

base64_alphabet_bytes: [64]u8

base64_alphabet_ready: bool

base64_alphabet :: proc() -> [64]u8 {
	if !base64_alphabet_ready {
		alphabet := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
		for index in 0 ..< 64 {
			base64_alphabet_bytes[index] = alphabet[index]
		}
		base64_alphabet_ready = true
	}
	return base64_alphabet_bytes
}

base64_encode :: proc(value: string) -> string {
	length := len(value)
	if length == 0 {
		return ""
	}
	encoded_length := (length + 2) / 3 * 4
	alphabet := base64_alphabet()
	buffer := make([]u8, encoded_length)
	position := 0
	index := 0
	for index + 2 < length {
		triple :=
			u32(value[index]) << 16 |
			u32(value[index + 1]) << 8 |
			u32(value[index + 2])
		buffer[position + 0] = alphabet[(triple >> 18) & 0x3f]
		buffer[position + 1] = alphabet[(triple >> 12) & 0x3f]
		buffer[position + 2] = alphabet[(triple >> 6) & 0x3f]
		buffer[position + 3] = alphabet[triple & 0x3f]
		position += 4
		index += 3
	}
	remaining := length - index
	if remaining == 1 {
		triple := u32(value[index]) << 16
		buffer[position + 0] = alphabet[(triple >> 18) & 0x3f]
		buffer[position + 1] = alphabet[(triple >> 12) & 0x3f]
		buffer[position + 2] = '='
		buffer[position + 3] = '='
	} else if remaining == 2 {
		triple := u32(value[index]) << 16 | u32(value[index + 1]) << 8
		buffer[position + 0] = alphabet[(triple >> 18) & 0x3f]
		buffer[position + 1] = alphabet[(triple >> 12) & 0x3f]
		buffer[position + 2] = alphabet[(triple >> 6) & 0x3f]
		buffer[position + 3] = '='
	}
	return strings.clone(string(buffer))
}

base64_decode :: proc(value: string) -> (string, bool) {
	if len(value) % 4 != 0 {
		return "", false
	}
	alphabet := base64_alphabet()
	values: [256]i8
	for index in 0 ..< 256 {
		values[index] = -1
	}
	for index in 0 ..< 64 {
		values[alphabet[index]] = i8(index)
	}
	decoded_length := len(value) / 4 * 3
	scratch := make([]byte, decoded_length)
	used := 0
	index := 0
	for index < len(value) {
		packed: u32 = 0
		padding := 0
		for slot in 0 ..< 4 {
			character := value[index + slot]
			if character == '=' {
				padding += 1
				continue
			}
			digit := values[character]
			if digit < 0 {
				delete(scratch)
				return "", false
			}
			packed |= u32(digit) << u32(18 - 6 * slot)
		}
		if padding == 0 {
			scratch[used] = byte((packed >> 16) & 0xff)
			scratch[used + 1] = byte((packed >> 8) & 0xff)
			scratch[used + 2] = byte(packed & 0xff)
			used += 3
		} else if padding == 1 {
			scratch[used] = byte((packed >> 16) & 0xff)
			scratch[used + 1] = byte((packed >> 8) & 0xff)
			used += 2
		} else if padding == 2 {
			scratch[used] = byte((packed >> 16) & 0xff)
			used += 1
		} else {
			delete(scratch)
			return "", false
		}
		index += 4
	}
	decoded := strings.clone(string(scratch[:used]))
	delete(scratch)
	return decoded, true
}

encoding_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(EncodingService)
	service.service = Service_Init(
		&EncodingService_Class,
		"encodingService",
		data_model,
	)
	return &service.object
}

encoding_service_base64_encode :: proc(L: ^vm.State) -> i32 {
	value := vm.ArgString(L, 2)
	vm.PushString(L, base64_encode(value))
	return 1
}

encoding_service_base64_decode :: proc(L: ^vm.State) -> i32 {
	value := vm.ArgString(L, 2)
	decoded, ok := base64_decode(value)
	if !ok {
		return vm.RaiseError(L, "EncodingService:DecodeBase64: invalid input")
	}
	vm.PushString(L, decoded)
	return 1
}

encoding_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "EncodeBase64", "DecodeBase64":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

encoding_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method_name: string,
) -> (i32, bool) {
	switch method_name {
	case "EncodeBase64":
		return encoding_service_base64_encode(L), true
	case "DecodeBase64":
		return encoding_service_base64_decode(L), true
	}
	return 0, false
}

encoding_service_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	classes.Object_Destroy(object)
	free(cast(^EncodingService)object)
}

Register_EncodingService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&EncodingService_Class,
		encoding_service_construct,
		encoding_service_destroy,
		creatable = false,
		get       = encoding_service_get,
		namecall  = encoding_service_namecall,
	)
}
