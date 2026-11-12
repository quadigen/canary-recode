#+build !js

package serializer

import assetstore "../assetstore"
import kineffi "../bindings"
import classes "../classes"
import vm "../vm"
import "core:c"
import "core:os"


KINE_ZSTD_LEVEL :: kineffi.ZSTD_CLEVEL_DEFAULT

KINE_TREE_HEADROOM_BYTES :: 64 * 1024 * 1024
KINE_MAX_STREAM_BYTES :: assetstore.MAX_ASSET_TOTAL_BYTES + KINE_TREE_HEADROOM_BYTES

is_zstd_frame :: proc(data: []u8) -> bool {
	if len(data) < 4 {
		return false
	}
	bytes := transmute([4]u8)u32(kineffi.ZSTD_MAGICNUMBER)
	return data[0] == bytes[0] && data[1] == bytes[1] && data[2] == bytes[2] && data[3] == bytes[3]
}

compress_kine :: proc(data: []u8, level: c.int = KINE_ZSTD_LEVEL) -> ([]u8, Error) {
	bound := kineffi.ZSTD_compressBound(c.size_t(len(data)))
	compressed := make([]u8, int(bound))

	written := kineffi.ZSTD_compress(
		raw_data(compressed),
		bound,
		raw_data(data),
		c.size_t(len(data)),
		level,
	)
	if kineffi.ZSTD_isError(written) != 0 {
		delete(compressed)
		return nil, Error_Make(
			.Compress_Failed,
			-1,
			"zstd could not compress %d bytes: %s",
			len(data),
			string(kineffi.ZSTD_getErrorName(written)),
		)
	}

	return compressed[:int(written)], Error_None
}


decompress_kine :: proc(data: []u8, level: c.int = KINE_ZSTD_LEVEL) -> ([]u8, Error) {
	content_size := kineffi.ZSTD_getFrameContentSize(raw_data(data), c.size_t(len(data)))
	if content_size == ~u64(0) || content_size == ~u64(1) {


		return nil, Error_Make(
			.Stream_Too_Large,
			0,
			"the zstd frame records no decompressed size, so there is nothing to bound the allocation against",
		)
	}
	if content_size > KINE_MAX_STREAM_BYTES {
		return nil, Error_Make(
			.Stream_Too_Large,
			0,
			"the zstd frame claims %d decompressed bytes, over the %d byte limit",
			content_size,
			KINE_MAX_STREAM_BYTES,
		)
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
		return nil, Error_Make(
			.Decompress_Failed,
			0,
			"zstd could not expand the %d byte frame: %s",
			len(data),
			string(kineffi.ZSTD_getErrorName(written)),
		)
	}

	return decompressed[:int(written)], Error_None
}


Has_Path_Assets :: proc(data: []u8) -> bool {
	raw := data
	if is_zstd_frame(data) {
		err: Error
		raw, err = decompress_kine(data)
		defer Error_Delete(&err)
		if !Error_Is_None(err) {return false}
	}
	defer if raw_data(raw) != raw_data(data) {delete(raw)}
	reader := Reader{data = raw}
	defer Error_Delete(&reader.err)
	if !read_kine_header(&reader) || reader.version < KINE_ASSET_VERSION {return false}
	count, ok := read_u32(&reader)
	if !ok || count > u32(assetstore.MAX_ASSET_COUNT) {return false}
	for _ in 0 ..< count {
		for _ in 0 ..< 2 {
			length, length_ok := read_var_u32(&reader)
			if !length_ok {return false}
			if _, skipped := read_bytes(&reader, int(length)); !skipped {return false}
		}
		kind, kind_ok := read_u8(&reader)
		if !kind_ok {return false}
		if kind == u8(assetstore.Asset_Kind.Path_File) {return true}
		length, length_ok := read_var_u32(&reader)
		if !length_ok {return false}
		if _, skipped := read_bytes(&reader, int(length)); !skipped {return false}
	}
	return false
}

// Network clients load the file bundle without instantiating the server's map.
Load_Embedded_Assets :: proc(data: []u8) -> Error {
	raw := data
	if is_zstd_frame(data) {
		err: Error
		raw, err = decompress_kine(data)
		if !Error_Is_None(err) {return err}
	}
	defer if raw_data(raw) != raw_data(data) {delete(raw)}
	reader := Reader{data = raw}
	defer Error_Delete(&reader.err)
	if !read_kine_header(&reader) {return Error_Take(&reader.err)}
	if reader.version >= KINE_ASSET_VERSION && !read_asset_table(&reader) {
		return Error_Take(&reader.err)
	}
	return Error_None
}

Repack_File_Data :: proc(data: []u8, level: c.int) -> ([]u8, Error) {
	raw: []u8
	if is_zstd_frame(data) {
		err: Error
		raw, err = decompress_kine(data)
		if !Error_Is_None(err) {
			return nil, err
		}
	} else {
		raw = make([]u8, len(data))
		copy(raw, data)
	}
	if level == 0 {
		return raw, Error_None
	}
	compressed, err := compress_kine(raw, level)
	if Error_Is_None(err) && len(compressed) >= len(raw) {
		delete(compressed)
		return raw, Error_None
	}
	delete(raw)
	return compressed, err
}

Serialize_To_File :: proc(
	registry: ^classes.Registry,
	L: ^vm.State,
	object: ^classes.Object,
	path: string,
	exclude_child: proc(parent: ^classes.Object, object: ^classes.Object) -> bool = nil,
	terrain: ^Kine_Terrain = nil,
) -> Error {
	if path == "" {
		return Error_Make(.Invalid_Argument, -1, "the destination path is empty")
	}

	data, err := Serialize(registry, L, object, exclude_child, terrain)
	defer Error_Delete(&err)
	if !Error_Is_None(err) {
		return Error_Take(&err)
	}
	defer delete(data)
	return Write_File_Data(path, data)
}

// Write a complete snapshot without accessing the VM or the live asset store.
Write_File_Data :: proc(path: string, data: []u8) -> Error {
	compressed, compress_err := compress_kine(data)
	defer Error_Delete(&compress_err)
	defer delete(compressed)
	if Error_Is_None(compress_err) && len(compressed) < len(data) {
		write_err := os.write_entire_file(path, compressed)
		if write_err != nil {
			return Error_Make(
				.File_Write_Failed,
				-1,
				"could not write %d compressed bytes to %s: %v",
				len(compressed),
				path,
				write_err,
			)
		}
		return Error_None
	}

	write_err := os.write_entire_file(path, data)
	if write_err != nil {
		return Error_Make(
			.File_Write_Failed,
			-1,
			"could not write %d bytes to %s: %v",
			len(data),
			path,
			write_err,
		)
	}
	return Error_None
}


Write_File_Data_Progress :: proc(path: string, data: []u8, progress: ^f32) -> Error {
	if progress != nil {progress^ = 0.1}
	compressed, compress_err := compress_kine(data)
	defer Error_Delete(&compress_err)
	defer delete(compressed)
	payload := data
	if Error_Is_None(compress_err) && len(compressed) < len(data) {payload = compressed}
	if progress != nil {progress^ = 0.55}

	file, open_err := os.create(path)
	if open_err != nil {
		return Error_Make(.File_Write_Failed, -1, "could not create %s: %v", path, open_err)
	}
	defer os.close(file)

	total := len(payload)
	written := 0
	for written < total {
		chunk := min(1 << 20, total - written)
		count, write_err := os.write(file, payload[written:written + chunk])
		if write_err != nil || count <= 0 {
			return Error_Make(
				.File_Write_Failed,
				-1,
				"could not write %d bytes to %s",
				total,
				path,
			)
		}
		written += count
		if progress != nil {progress^ = 0.55 + 0.45 * f32(written) / f32(total)}
	}
	if progress != nil {progress^ = 1}
	return Error_None
}

Deserialize_From_Data :: proc(
	registry: ^classes.Registry,
	L: ^vm.State,
	parent: ^classes.Object,
	data: []u8,
	terrain: ^Kine_Terrain = nil,
	service_properties: ^Loaded_Service_Properties = nil,
) -> (
	^classes.Object,
	Error,
) {
	if data == nil {
		return nil, Error_Make(.Invalid_Argument, -1, "the stream is nil")
	}

	if is_zstd_frame(data) {
		decompressed, err := decompress_kine(data)
		defer Error_Delete(&err)
		if !Error_Is_None(err) {
			return nil, Error_Take(&err)
		}
		defer delete(decompressed)

		return Deserialize(registry, L, parent, decompressed, terrain, service_properties)
	}

	return Deserialize(registry, L, parent, data, terrain, service_properties)
}


Deserialize_From_File :: proc(
	registry: ^classes.Registry,
	L: ^vm.State,
	parent: ^classes.Object,
	path: string,
	terrain: ^Kine_Terrain = nil,
) -> (
	^classes.Object,
	Error,
) {
	if path == "" {
		return nil, Error_Make(.Invalid_Argument, -1, "the source path is empty")
	}

	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		return nil, Error_Make(.File_Read_Failed, -1, "could not read %s: %v", path, err)
	}
	defer delete(data)

	return Deserialize_From_Data(registry, L, parent, data, terrain)
}
