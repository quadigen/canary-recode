#+build !js

package serializer

import "core:c"
import "core:os"
import classes "../classes"
import vm "../vm"
import kineffi "../bindings"

// A .KINE file stores the KINE byte stream as a single zstd frame. Files saved
// before compression was introduced are still accepted: their leading bytes do
// not match the zstd magic, so they are passed through uncompressed.
KINE_ZSTD_LEVEL :: kineffi.ZSTD_CLEVEL_DEFAULT

is_zstd_frame :: proc(data: []u8) -> bool {
	if len(data) < 4 {
		return false
	}
	bytes := transmute([4]u8)u32(kineffi.ZSTD_MAGICNUMBER)
	return data[0] == bytes[0] && data[1] == bytes[1] && data[2] == bytes[2] && data[3] == bytes[3]
}

compress_kine :: proc(data: []u8) -> ([]u8, bool) {
	bound := kineffi.ZSTD_compressBound(c.size_t(len(data)))
	compressed := make([]u8, int(bound))

	written := kineffi.ZSTD_compress(
		raw_data(compressed),
		bound,
		raw_data(data),
		c.size_t(len(data)),
		KINE_ZSTD_LEVEL,
	)
	if kineffi.ZSTD_isError(written) != 0 {
		delete(compressed)
		return nil, false
	}

	return compressed[:int(written)], true
}

decompress_kine :: proc(data: []u8) -> ([]u8, bool) {
	content_size := kineffi.ZSTD_getFrameContentSize(raw_data(data), c.size_t(len(data)))
	if content_size == ~u64(0) || content_size == ~u64(1) || content_size > 64 * 1024 * 1024 {
		return nil, false
	}

	decompressed := make([]u8, int(content_size))
	written := kineffi.ZSTD_decompress(
		raw_data(decompressed),
		c.size_t(len(decompressed)),
		raw_data(data),
		c.size_t(len(data)),
	)
	if kineffi.ZSTD_isError(written) != 0 {
		delete(decompressed)
		return nil, false
	}

	return decompressed[:int(written)], true
}

// Serialize_To_File writes an Instance hierarchy to a .KINE file on disk.
Serialize_To_File :: proc(
	registry: ^classes.Registry,
	L: ^vm.State,
	object: ^classes.Object,
	path: string,
) -> bool {
	data, ok := Serialize(registry, L, object)
	if !ok {
		return false
	}
	defer delete(data)

	compressed, compress_ok := compress_kine(data)
	if !compress_ok {
		return false
	}
	defer delete(compressed)

	return os.write_entire_file(path, compressed) == 0
}

// Deserialize_From_File reads a .KINE file from disk and restores the
// Instance hierarchy under parent (which may be nil for a standalone root).
Deserialize_From_File :: proc(
	registry: ^classes.Registry,
	L: ^vm.State,
	parent: ^classes.Object,
	path: string,
) -> (^classes.Object, bool) {
	data, err := os.read_entire_file(path, context.allocator)
	if err != 0 {
		return nil, false
	}
	defer delete(data)

	if is_zstd_frame(data) {
		decompressed, ok := decompress_kine(data)
		if !ok {
			return nil, false
		}
		defer delete(decompressed)

		return Deserialize(registry, L, parent, decompressed)
	}

	return Deserialize(registry, L, parent, data)
}
