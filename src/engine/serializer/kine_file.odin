#+build !js

package serializer

import assetstore "../assetstore"
import kineffi "../bindings"
import classes "../classes"
import vm "../vm"
import "core:c"
import "core:os"
import "core:path/filepath"


KINE_ZSTD_LEVEL :: kineffi.ZSTD_CLEVEL_DEFAULT


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
	reader := Reader {
		data = raw,
	}
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


Load_Embedded_Assets :: proc(data: []u8) -> Error {
	raw := data
	if is_zstd_frame(data) {
		err: Error
		raw, err = decompress_kine(data)
		if !Error_Is_None(err) {return err}
	}
	defer if raw_data(raw) != raw_data(data) {delete(raw)}
	reader := Reader {
		data = raw,
	}
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


Write_File_Data :: proc(path: string, data: []u8) -> Error {
	return Write_File_Data_Progress(path, data, nil)
}

Kine_Write_Progress_Callback :: proc(value: f32, userdata: rawptr)

kine_write_progress :: proc(
	progress: ^f32,
	callback: Kine_Write_Progress_Callback,
	userdata: rawptr,
	value: f32,
) {
	if progress != nil {progress^ = value}
	if callback != nil {callback(value, userdata)}
}

Write_File_Data_Progress :: proc(
	path: string,
	data: []u8,
	progress: ^f32,
	callback: Kine_Write_Progress_Callback = nil,
	userdata: rawptr = nil,
) -> Error {
	if path == "" {return Error_Make(.Invalid_Argument, -1, "the destination path is empty")}
	kine_write_progress(progress, callback, userdata, 0.1)
	compressed, compress_err := compress_kine(data)
	defer Error_Delete(&compress_err)
	defer delete(compressed)
	payload := data
	if Error_Is_None(compress_err) && len(compressed) < len(data) {payload = compressed}
	kine_write_progress(progress, callback, userdata, 0.55)


	staging, staging_err := os.make_directory_temp(
		filepath.dir(path),
		".kine-write-*",
		context.allocator,
	)
	if staging_err != nil {
		return Error_Make(.File_Write_Failed, -1, "could not stage %s: %v", path, staging_err)
	}
	defer delete(staging)
	defer os.remove_all(staging)
	pending, join_err := filepath.join([]string{staging, "pending.kine"}, context.temp_allocator)
	if join_err != nil {
		return Error_Make(
			.File_Write_Failed,
			-1,
			"could not form staging path for %s: %v",
			path,
			join_err,
		)
	}

	{
		file, open_err := os.create(pending)
		if open_err != nil {
			return Error_Make(
				.File_Write_Failed,
				-1,
				"could not create staging file for %s: %v",
				path,
				open_err,
			)
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
					"could not write %d bytes to staging file for %s",
					total,
					path,
				)
			}
			written += count
			kine_write_progress(
				progress,
				callback,
				userdata,
				0.55 + 0.44 * f32(written) / f32(total),
			)
		}


		if sync_err := os.sync(file); sync_err != nil {
			return Error_Make(
				.File_Write_Failed,
				-1,
				"could not sync staging file for %s: %v",
				path,
				sync_err,
			)
		}
	}
	if rename_err := os.rename(pending, path); rename_err != nil {
		return Error_Make(.File_Write_Failed, -1, "could not replace %s: %v", path, rename_err)
	}
	when ODIN_OS == .Linux || ODIN_OS == .Darwin {

		directory, open_err := os.open(filepath.dir(path))
		if open_err != nil {
			return Error_Make(
				.File_Write_Failed,
				-1,
				"could not open destination directory for %s: %v",
				path,
				open_err,
			)
		}
		sync_err := os.sync(directory)
		close_err := os.close(directory)
		if sync_err != nil || close_err != nil {
			return Error_Make(
				.File_Write_Failed,
				-1,
				"could not sync destination directory for %s",
				path,
			)
		}
	}
	kine_write_progress(progress, callback, userdata, 1)
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


	file, open_err := os.open(path)
	if open_err != nil {
		return nil, Error_Make(.File_Read_Failed, -1, "could not open %s: %v", path, open_err)
	}
	defer os.close(file)
	info, stat_err := os.fstat(file, context.allocator)
	if stat_err != nil {
		return nil, Error_Make(.File_Read_Failed, -1, "could not inspect %s: %v", path, stat_err)
	}
	defer os.file_info_delete(info, context.allocator)
	if info.type != .Regular {
		return nil, Error_Make(.File_Read_Failed, -1, "%s is not a regular file", path)
	}
	if info.size < 0 || u64(info.size) > u64(KINE_MAX_STREAM_BYTES) {
		return nil, Error_Make(
			.Stream_Too_Large,
			0,
			"file %s exceeds the %d byte stream limit",
			path,
			KINE_MAX_STREAM_BYTES,
		)
	}
	data := make([]u8, int(info.size))
	defer delete(data)
	read := 0
	for read < len(data) {
		count, read_err := os.read(file, data[read:read + min(len(data) - read, 64 * 1024)])
		if read_err != nil || count <= 0 {
			return nil, Error_Make(
				.File_Read_Failed,
				-1,
				"file %s was truncated during read",
				path,
			)
		}
		read += count
	}
	probe: [1]u8
	n, probe_err := os.read(file, probe[:])
	if n != 0 || (probe_err != nil && probe_err != .EOF) {
		return nil, Error_Make(.Stream_Too_Large, 0, "file %s grew while it was being read", path)
	}
	return Deserialize_From_Data(registry, L, parent, data, terrain)
}
