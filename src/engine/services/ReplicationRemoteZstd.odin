package services

import kineffi "../bindings"
import "core:c"

REPLICATION_REMOTE_ZSTD_THRESHOLD :: 384
REPLICATION_REMOTE_ZSTD_MIN_SAVINGS :: 64
REPLICATION_REMOTE_ZSTD_MAX_EXPANDED :: 1024 * 1024

replication_remote_zstd_kind :: proc(kind: u8) -> bool {
	return kind == 16 || kind == 17 || kind == 18 || kind == Replication_Kind_Cloth_Config || kind == Replication_Kind_Deformable
}

replication_remote_zstd_compress :: proc(
	kind: u8,
	payload: []u8,
	enabled: bool,
) -> (compressed: []u8, used: bool) {
	if !enabled ||
	   !replication_remote_zstd_kind(kind) ||
	   len(payload) < REPLICATION_REMOTE_ZSTD_THRESHOLD ||
	   len(payload) > REPLICATION_REMOTE_ZSTD_MAX_EXPANDED {return nil, false}

	bound := kineffi.ZSTD_compressBound(c.size_t(len(payload)))
	if bound > c.size_t(REPLICATION_REMOTE_ZSTD_MAX_EXPANDED + 1024) {return nil, false}
	compressed = make([]u8, int(bound) + 5)
	written := kineffi.ZSTD_compress(
		raw_data(compressed[5:]),
		bound,
		raw_data(payload),
		c.size_t(len(payload)),
		1,
	)
	if kineffi.ZSTD_isError(written) != 0 {
		delete(compressed)
		return nil, false
	}
	compressed_size := int(written) + 5
	if compressed_size > int(Replication_Max_Native_Send_Payload) ||
	   compressed_size + max(REPLICATION_REMOTE_ZSTD_MIN_SAVINGS, len(payload) / 8) >= len(payload) {
		delete(compressed)
		return nil, false
	}

	compressed[0] = kind
	size := u32(len(payload))
	for i in 0 ..< 4 {compressed[i + 1] = u8(size >> u32(i * 8))}
	return compressed[:compressed_size], true
}

replication_remote_zstd_decompress :: proc(frame: []u8) -> (expanded: []u8, ok: bool) {
	if len(frame) < 5 + 5 + 6 ||
	   len(frame) > int(Replication_Max_Native_Send_Payload) + 5 ||
	   frame[4] != Replication_Kind_Remote_Zstd ||
	   !replication_remote_zstd_kind(frame[5]) {return nil, false}

	expected := u32(frame[6]) |
	            u32(frame[7]) << 8 |
	            u32(frame[8]) << 16 |
	            u32(frame[9]) << 24
	if expected < 4 || expected > REPLICATION_REMOTE_ZSTD_MAX_EXPANDED {return nil, false}
	encoded := frame[10:]
	frame_size := kineffi.ZSTD_findFrameCompressedSize(raw_data(encoded), c.size_t(len(encoded)))
	if kineffi.ZSTD_isError(frame_size) != 0 || int(frame_size) != len(encoded) {return nil, false}
	content_size := kineffi.ZSTD_getFrameContentSize(raw_data(encoded), c.size_t(len(encoded)))
	if content_size != u64(expected) {return nil, false}

	expanded = make([]u8, int(expected) + 5)
	copy(expanded[:4], frame[:4])
	expanded[4] = frame[5]
	written := kineffi.ZSTD_decompress(
		raw_data(expanded[5:]),
		c.size_t(expected),
		raw_data(encoded),
		c.size_t(len(encoded)),
	)
	if kineffi.ZSTD_isError(written) != 0 || written != c.size_t(expected) {
		delete(expanded)
		return nil, false
	}
	return expanded, true
}
