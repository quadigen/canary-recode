#+build !js

package services

import "core:os"
import target "../target"

PAYLOAD_MAGIC      :: "KINEPAY1"
PAYLOAD_VERSION    :: u8(1)
PAYLOAD_TAIL_LEN    :: 8
PAYLOAD_LEN_FIELD   :: 8
PAYLOAD_TAIL_SIZE   :: PAYLOAD_LEN_FIELD + PAYLOAD_TAIL_LEN

Payload :: struct {
	mode:      target.Mode,
	address:   string,
	port:      u16,
	name:      string,
	map_bytes: []u8,
}

payload_self_region: []u8

Payload_Region :: proc(p: Payload) -> (region: []u8, ok: bool) {
	address_bytes := transmute([]u8)p.address
	name_bytes := transmute([]u8)p.name
	if (len(address_bytes) + len(name_bytes)) > int(max(u16)) {
		return nil, false
	}
	region = make([]u8,
		8 + 1 + 1 + 1 + 2 + 2 + len(address_bytes) + 2 + len(name_bytes) + 4 + len(p.map_bytes),
	)
	offset := 0
	copy(region[offset:], PAYLOAD_MAGIC); offset += 8
	region[offset] = PAYLOAD_VERSION; offset += 1
	region[offset] = u8(p.mode); offset += 1
	region[offset] = 0; offset += 1
	payload_write_le_u16(region, offset, p.port); offset += 2
	payload_write_le_u16(region, offset, u16(len(address_bytes))); offset += 2
	copy(region[offset:], address_bytes); offset += len(address_bytes)
	payload_write_le_u16(region, offset, u16(len(name_bytes))); offset += 2
	copy(region[offset:], name_bytes); offset += len(name_bytes)
	payload_write_le_u32(region, offset, u32(len(p.map_bytes))); offset += 4
	copy(region[offset:], p.map_bytes); offset += len(p.map_bytes)
	return region, true
}

Payload_Parse_Region :: proc(region: []u8) -> (payload: Payload, ok: bool) {
	if len(region) < 8 + 1 + 1 + 1 + 2 + 2 + 2 + 4 {
		return {}, false
	}
	offset := 0
	if string(region[0:8]) != PAYLOAD_MAGIC {
		return {}, false
	}
	offset = 8
	if region[offset] != PAYLOAD_VERSION {
		return {}, false
	}
	offset += 1
	mode_value := region[offset]
	offset += 1
	offset += 1
	if mode_value > 2 {
		return {}, false
	}
	payload.port = payload_read_le_u16(region, offset); offset += 2
	address_len := int(payload_read_le_u16(region, offset)); offset += 2
	if offset + address_len + 2 + 4 > len(region) {
		return {}, false
	}
	payload.address = string(region[offset:offset + address_len]); offset += address_len
	name_len := int(payload_read_le_u16(region, offset)); offset += 2
	if offset + name_len + 4 > len(region) {
		return {}, false
	}
	payload.name = string(region[offset:offset + name_len]); offset += name_len
	map_len := int(payload_read_le_u32(region, offset)); offset += 4
	if offset + map_len > len(region) {
		return {}, false
	}
	payload.map_bytes = region[offset:offset + map_len]
	payload.mode = target.Mode(mode_value)
	return payload, true
}

payload_write_le_u16 :: proc(buf: []u8, offset: int, value: u16) {
	buf[offset] = u8(value)
	buf[offset + 1] = u8(value >> 8)
}

payload_write_le_u32 :: proc(buf: []u8, offset: int, value: u32) {
	buf[offset] = u8(value)
	buf[offset + 1] = u8(value >> 8)
	buf[offset + 2] = u8(value >> 16)
	buf[offset + 3] = u8(value >> 24)
}

payload_write_le_u64 :: proc(buf: []u8, offset: int, value: u64) {
	for i in 0 ..< 8 {
		buf[offset + i] = u8(value >> (8 * u64(i)))
	}
}

payload_read_le_u16 :: proc(buf: []u8, offset: int) -> u16 {
	return u16(buf[offset]) | u16(buf[offset + 1]) << 8
}

payload_read_le_u32 :: proc(buf: []u8, offset: int) -> u32 {
	return u32(buf[offset]) |
		u32(buf[offset + 1]) << 8 |
		u32(buf[offset + 2]) << 16 |
		u32(buf[offset + 3]) << 24
}

payload_read_le_u64 :: proc(buf: []u8, offset: int) -> u64 {
	result: u64
	for i in 0 ..< 8 {
		result |= u64(buf[offset + i]) << (8 * u64(i))
	}
	return result
}

Payload_Append :: proc(template: []u8, payload: Payload) -> (out: []u8, ok: bool) {
	region, region_ok := Payload_Region(payload)
	if !region_ok {
		return nil, false
	}
	defer delete(region)
	out = make([]u8, len(template) + len(region) + PAYLOAD_TAIL_SIZE)
	copy(out, template)
	copy(out[len(template):], region)
	payload_write_le_u64(out, len(template) + len(region), u64(len(region)))
	copy(out[len(out) - PAYLOAD_TAIL_LEN:], PAYLOAD_MAGIC)
	return out, true
}

Payload_Read_Back :: proc(file_bytes: []u8) -> (payload: Payload, ok: bool) {
	if len(file_bytes) < PAYLOAD_TAIL_SIZE {
		return {}, false
	}
	tail := file_bytes[len(file_bytes) - PAYLOAD_TAIL_SIZE:]
	if string(tail[PAYLOAD_LEN_FIELD:]) != PAYLOAD_MAGIC {
		return {}, false
	}
	total := payload_read_le_u64(tail, 0)
	if total > u64(len(file_bytes) - PAYLOAD_TAIL_SIZE) {
		return {}, false
	}
	region_left := len(file_bytes) - PAYLOAD_TAIL_SIZE - int(total)
	region := file_bytes[region_left:region_left + int(total)]
	return Payload_Parse_Region(region)
}

Payload_Read_Self :: proc() -> (payload: Payload, ok: bool) {
	if len(payload_self_region) > 0 {
		return Payload_Parse_Region(payload_self_region)
	}
	path, path_error := os.get_executable_path(context.temp_allocator)
	if path_error != os.ERROR_NONE {
		return {}, false
	}
	handle, open_error := os.open(path)
	if open_error != os.ERROR_NONE {
		return {}, false
	}
	defer os.close(handle)
	size, size_error := os.file_size(handle)
	if size_error != os.ERROR_NONE || size < PAYLOAD_TAIL_SIZE {
		return {}, false
	}
	tail := make([]u8, PAYLOAD_TAIL_SIZE, context.temp_allocator)
	read, read_error := os.read_at(handle, tail, size - PAYLOAD_TAIL_SIZE)
	if read_error != os.ERROR_NONE || int(read) != PAYLOAD_TAIL_SIZE {
		return {}, false
	}
	if string(tail[PAYLOAD_LEN_FIELD:]) != PAYLOAD_MAGIC {
		return {}, false
	}
	total := payload_read_le_u64(tail, 0)
	if total > u64(size - PAYLOAD_TAIL_SIZE) {
		return {}, false
	}
	payload_self_region = make([]u8, int(total))
	read, read_error = os.read_at(handle, payload_self_region, size - PAYLOAD_TAIL_SIZE - i64(total))
	if read_error != os.ERROR_NONE || int(read) != int(total) {
		payload_self_region = nil
		return {}, false
	}
	return Payload_Parse_Region(payload_self_region)
}