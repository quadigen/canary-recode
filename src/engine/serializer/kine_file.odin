#+build !js

package serializer

import "core:c"
import "core:fmt"
import "core:os"
import assetstore "../assetstore"
import classes "../classes"
import vm "../vm"
import kineffi "../bindings"

// A .KINE file stores the KINE byte stream as a single zstd frame when that is
// smaller. Raw streams remain valid for small or incompressible files.
KINE_ZSTD_LEVEL :: kineffi.ZSTD_CLEVEL_DEFAULT

// KINE_MAX_STREAM_BYTES bounds a decompressed stream. It cannot be smaller than
// the asset budget, because the asset table is part of the stream, and it is not
// exactly that either: the instance tree, property names, and varuint framing sit
// alongside the asset bytes. The extra headroom is what those cost, so a map that
// legitimately fills the asset budget still loads.
KINE_TREE_HEADROOM_BYTES :: 64 * 1024 * 1024
KINE_MAX_STREAM_BYTES :: assetstore.MAX_ASSET_TOTAL_BYTES + KINE_TREE_HEADROOM_BYTES

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

// decompress_kine expands a zstd frame. It refuses anything that would exceed
// KINE_MAX_STREAM_BYTES rather than trusting a size the frame claims for itself.
decompress_kine :: proc(data: []u8) -> ([]u8, bool) {
	content_size := kineffi.ZSTD_getFrameContentSize(raw_data(data), c.size_t(len(data)))
	if content_size == ~u64(0) || content_size == ~u64(1) {
		// The frame does not record its size, so there is nothing to bound the
		// allocation against. Refuse rather than decompress untrusted input blind.
		return nil, false
	}
	if content_size > KINE_MAX_STREAM_BYTES {
		fmt.eprintf("kine: stream claims %d bytes, over the %d byte limit\n", content_size, KINE_MAX_STREAM_BYTES)
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
		fmt.eprintf("kine: decompression failed: %s\n", kineffi.ZSTD_getErrorName(written))
		delete(decompressed)
		return nil, false
	}

	return decompressed[:int(written)], true
}

// Serialize_To_File writes an Instance hierarchy to a .KINE file on disk.
// exclude_child (optional) lets the caller strip selected children and their
// subtrees from the written tree (for example editor-only services).
Serialize_To_File :: proc(
	registry: ^classes.Registry,
	L: ^vm.State,
	object: ^classes.Object,
	path: string,
	exclude_child: proc(parent: ^classes.Object, object: ^classes.Object) -> bool = nil,
) -> bool {
	data, ok := Serialize(registry, L, object, exclude_child)
	if !ok {
		return false
	}
	defer delete(data)

	// Compression is an optimization, not a requirement. If zstd cannot run, or
	// fails, or does not actually help, the raw stream is still a valid .KINE
	// and the reader detects it by its KINE header. Losing compression must
	// never cost the author their save.
	compressed, compress_ok := compress_kine(data)
	if compress_ok {
		defer delete(compressed)
		if len(compressed) < len(data) {
			return os.write_entire_file(path, compressed) == nil
		}
	}

	return os.write_entire_file(path, data) == nil
}

// Deserialize_From_Data restores an Instance hierarchy from an in-memory .KINE
// byte stream (embedded binaries, network payloads) under parent.
Deserialize_From_Data :: proc(
	registry: ^classes.Registry,
	L: ^vm.State,
	parent: ^classes.Object,
	data: []u8,
) -> (^classes.Object, bool) {
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

// Deserialize_From_File reads a .KINE file from disk and restores the
// Instance hierarchy under parent (which may be nil for a standalone root).
Deserialize_From_File :: proc(
	registry: ^classes.Registry,
	L: ^vm.State,
	parent: ^classes.Object,
	path: string,
) -> (^classes.Object, bool) {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		return nil, false
	}
	defer delete(data)

	return Deserialize_From_Data(registry, L, parent, data)
}
