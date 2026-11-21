package services


import ffi "../bindings"
import "core:c"
import hash "core:crypto/hash"
import "core:strings"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

EncodingService_Class := classes.Class_Info {
	name   = "EncodingService",
	parent = &Service_Class,
}

EncodingService :: struct {
	using service: Service,
}

base64_alphabet :: proc() -> [64]u8 {
	alphabet := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	result: [64]u8
	for index in 0 ..< 64 {result[index] = alphabet[index]}
	return result
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
		triple := u32(value[index]) << 16 | u32(value[index + 1]) << 8 | u32(value[index + 2])
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
	return string(buffer)
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
				if slot < 2 || index + 4 != len(value) {delete(scratch); return "", false}
				padding += 1
				continue
			}
			if padding != 0 {delete(scratch); return "", false}
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
	service.service = Service_Init(&EncodingService_Class, "encodingService", data_model)
	return &service.object
}

encoding_service_base64_encode :: proc(L: ^vm.State) -> i32 {
	value := vm.ArgString(L, 2)
	encoded := base64_encode(value)
	defer delete(encoded)
	vm.PushString(L, encoded)
	return 1
}

encoding_service_base64_decode :: proc(L: ^vm.State) -> i32 {
	value := vm.ArgString(L, 2)
	decoded, ok := base64_decode(value)
	if !ok {
		return vm.RaiseError(L, "EncodingService:DecodeBase64: invalid input")
	}
	defer delete(decoded)
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
	case "EncodeBase64",
	     "DecodeBase64",
	     "Base64Encode",
	     "Base64Decode",
	     "ComputeBufferHash",
	     "ComputeStringHash",
	     "CompressBuffer",
	     "DecompressBuffer",
	     "GetDecompressedBufferSize":
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
) -> (
	i32,
	bool,
) {
	switch method_name {
	case "ComputeBufferHash", "ComputeStringHash":
		item := enums.Arg_Item(L, 3, enum_registry, "HashAlgorithm")
		algorithm: hash.Algorithm
		#partial switch enums.HashAlgorithm(item.value) {
		case .Blake2b:
			algorithm = .BLAKE2B
		case .Md5:
			algorithm = .Insecure_MD5
		case .Sha1:
			algorithm = .Insecure_SHA1
		case .Sha256:
			algorithm = .SHA256
		case:
			return vm.RaiseError(L, "unsupported hash algorithm"), true
		}
		if method_name == "ComputeBufferHash" {
			digest := hash.hash_bytes(algorithm, vm.ArgBuffer(L, 2))
			defer delete(digest)
			vm.PushBuffer(L, digest)
		} else {
			digest := hash.hash_string(algorithm, vm.ArgString(L, 2))
			defer delete(digest)
			hex := make([]u8, len(digest) * 2)
			defer delete(hex)
			alphabet := "0123456789abcdef"
			for b, i in digest {
				hex[2 * i] = alphabet[b >> 4]
				hex[2 * i + 1] = alphabet[b & 15]
			}
			vm.PushString(L, string(hex))
		}
		return 1, true
	case "CompressBuffer", "DecompressBuffer", "GetDecompressedBufferSize":
		when ODIN_OS == .JS {
			return vm.RaiseError(L, "compression backend unavailable on web"), true
		} else {
			input := vm.ArgBuffer(L, 2)
			item := enums.Arg_Item(L, 3, enum_registry, "CompressionAlgorithm")
			if enums.CompressionAlgorithm(item.value) !=
			   .Zstd {return vm.RaiseError(L, "unsupported compression algorithm"), true}
			limit :: 256 * 1024 * 1024
			if method_name == "CompressBuffer" {
				if len(input) >
				   limit {return vm.RaiseError(L, "compression input too large"), true}
				level := vm.ArgOptionalNumber(L, 4, 1)
				if !(level >= f64(ffi.ZSTD_minCLevel()) &&
					   level <=
						   f64(
							   ffi.ZSTD_maxCLevel(),
						   )) {return vm.RaiseError(L, "invalid compression level"), true}
				bound := ffi.ZSTD_compressBound(c.size_t(len(input)))
				output := make([]u8, int(bound))
				defer delete(output)
				written := ffi.ZSTD_compress(
					raw_data(output),
					bound,
					raw_data(input),
					c.size_t(len(input)),
					i32(level),
				)
				if ffi.ZSTD_isError(written) !=
				   0 {return vm.RaiseError(L, "compression failed"), true}
				vm.PushBuffer(L, output[:int(written)])
				return 1, true
			}
			size := ffi.ZSTD_getFrameContentSize(raw_data(input), c.size_t(len(input)))
			if method_name == "GetDecompressedBufferSize" {
				if size == ~u64(0) ||
				   size == ~u64(1) {vm.PushNil(L)} else {vm.PushNumber(L, f64(size))}
				return 1, true
			}
			if size >
			   limit {return vm.RaiseError(L, "invalid or oversized compressed frame"), true}
			output := make([]u8, int(size))
			defer delete(output)
			written := ffi.ZSTD_decompress(
				raw_data(output),
				c.size_t(size),
				raw_data(input),
				c.size_t(len(input)),
			)
			if ffi.ZSTD_isError(written) != 0 ||
			   u64(written) != size {return vm.RaiseError(L, "decompression failed"), true}
			vm.PushBuffer(L, output)
			return 1, true
		}
	case "Base64Encode", "Base64Decode":
		input := vm.ArgBuffer(L, 2)
		if method_name == "Base64Encode" {
			result := base64_encode(string(input))
			defer delete(result)
			vm.PushBuffer(L, transmute([]u8)result)
		} else {
			result, ok := base64_decode(string(input))
			if !ok {return vm.RaiseError(L, "invalid base64"), true}
			defer delete(result)
			vm.PushBuffer(L, transmute([]u8)result)
		}
		return 1, true
	case "EncodeBase64":
		return encoding_service_base64_encode(L), true
	case "DecodeBase64":
		return encoding_service_base64_decode(L), true
	}
	return 0, false
}

encoding_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
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
		get = encoding_service_get,
		parallel_get = encoding_service_get,
		namecall = encoding_service_namecall,
		parallel_namecall = encoding_service_namecall,
		methods = []string {
			"EncodeBase64",
			"DecodeBase64",
			"Base64Encode",
			"Base64Decode",
			"ComputeBufferHash",
			"ComputeStringHash",
			"CompressBuffer",
			"DecompressBuffer",
			"GetDecompressedBufferSize",
		},
	)
}
