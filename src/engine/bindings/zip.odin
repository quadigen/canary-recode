#+build !js
package kineffi

import "core:c"
import "core:mem"
import "core:strings"
import "core:os"
import "core:path/filepath"
import "core:path/slashpath"

import zip "./miniz"

ZIP_DEFAULT_COMPRESSION :: zip.mz_uint(0xFFFF_FFFF)

Zip_Mode :: enum {
	Reader,
	Writer,
}

Zip_Handle :: struct {
	archive:   zip.mz_zip_archive,
	mode:      Zip_Mode,
	finalized: bool,
	allocator: mem.Allocator,
}

zip_safe_entry_path :: proc(
	name: string,
	strip_root: bool,
) -> (string, bool) {
	if len(name) == 0 {
		return "", false
	}

	if strings.contains(name, "\\") ||
	   strings.contains(name, ":") ||
	   strings.contains(name, "\x00") {
		return "", false
	}

	cleaned := slashpath.clean(
		name,
		context.temp_allocator,
	)

	if slashpath.is_abs(cleaned) ||
	   cleaned == ".." ||
	   strings.has_prefix(cleaned, "../") {
		return "", false
	}

	if strip_root {
		index := strings.index_byte(cleaned, '/')

		if index < 0 || index + 1 >= len(cleaned) {
			return "", true
		}

		cleaned = cleaned[index + 1:]
	}

	if cleaned == "." {
		return "", true
	}

	return cleaned, true
}

Zip_Extract_All :: proc(
	handle: ^Zip_Handle,
	destination: string,
	strip_root: bool = false,
) -> bool {
	if handle == nil || handle.mode != .Reader {
		return false
	}

	if err := os.make_directory_all(destination); err != nil {
		return false
	}

	file_count := zip.mz_zip_reader_get_num_files(
		&handle.archive,
	)

	for index := zip.mz_uint(0); index < file_count; index += 1 {
		filename_size := zip.mz_zip_reader_get_filename(
			&handle.archive,
			index,
			nil,
			0,
		)

		if filename_size == 0 {
			return false
		}

		filename_buffer := make(
			[]u8,
			int(filename_size),
		)
		defer delete(filename_buffer)

		filename_cstring := cast(cstring)raw_data(
			filename_buffer,
		)

		if zip.mz_zip_reader_get_filename(
			&handle.archive,
			index,
			filename_cstring,
			filename_size,
		) == 0 {
			return false
		}

		archive_path := string(filename_cstring)

		safe_path, safe := zip_safe_entry_path(
			archive_path,
			strip_root,
		)

		if !safe {
			return false
		}

		// Can happen when stripping the ZIP's root directory.
		if len(safe_path) == 0 {
			continue
		}

		output_path, path_err := filepath.join(
			[]string{
				destination,
				safe_path,
			},
			context.temp_allocator,
		)

		if path_err != nil {
			return false
		}

		is_directory :=
			zip.mz_zip_reader_is_file_a_directory(
				&handle.archive,
				index,
			) != zip.MZ_FALSE

		if is_directory {
			if err := os.make_directory_all(
				output_path,
			); err != nil {
				return false
			}

			continue
		}

		parent := os.dir(output_path)

		if err := os.make_directory_all(parent); err != nil {
			return false
		}

		c_output, c_error := strings.clone_to_cstring(
			output_path,
		)

		if c_error != nil {
			return false
		}

		extracted := zip.mz_zip_reader_extract_to_file(
			&handle.archive,
			index,
			c_output,
			0,
		) != zip.MZ_FALSE

		delete(c_output)

		if !extracted {
			return false
		}
	}

	return true
}

Zip_Open :: proc(path: string) -> (^Zip_Handle, bool) {
	handle, alloc_err := mem.new(Zip_Handle)
	if alloc_err != nil {
		return nil, false
	}

	handle.allocator = context.allocator
	handle.mode = .Reader

	zip.mz_zip_zero_struct(&handle.archive)

	c_path, err := strings.clone_to_cstring(path)
	if err != nil {
		_ = mem.free(handle, handle.allocator)
		return nil, false
	}
	defer delete(c_path)

	if zip.mz_zip_reader_init_file(
		&handle.archive,
		c_path,
		0,
	) == zip.MZ_FALSE {
		_ = mem.free(handle, handle.allocator)
		return nil, false
	}

	return handle, true
}

Zip_Close :: proc(handle: ^Zip_Handle) -> bool {
	if handle == nil {
		return false
	}

	ok := true

	switch handle.mode {
	case .Reader:
		ok = zip.mz_zip_reader_end(&handle.archive) != zip.MZ_FALSE

	case .Writer:
		if !handle.finalized {
			if zip.mz_zip_writer_finalize_archive(&handle.archive) == zip.MZ_FALSE {
				ok = false
			} else {
				handle.finalized = true
			}
		}

		if zip.mz_zip_writer_end(&handle.archive) == zip.MZ_FALSE {
			ok = false
		}
	}

	allocator := handle.allocator
	_ = mem.free(handle, allocator)

	return ok
}

Zip_File_Count :: proc(handle: ^Zip_Handle) -> u32 {
	if handle == nil || handle.mode != .Reader {
		return 0
	}

	return u32(zip.mz_zip_reader_get_num_files(&handle.archive))
}

Zip_File_Name :: proc(
	handle: ^Zip_Handle,
	index: u32,
) -> (string, bool) {
	if handle == nil ||
	   handle.mode != .Reader ||
	   index >= Zip_File_Count(handle) {
		return "", false
	}

	filename_size := zip.mz_zip_reader_get_filename(
		&handle.archive,
		zip.mz_uint(index),
		nil,
		0,
	)

	if filename_size == 0 {
		return "", false
	}

	filename_buffer := make([]u8, int(filename_size))
	defer delete(filename_buffer)

	filename := cast(cstring)raw_data(filename_buffer)
	if zip.mz_zip_reader_get_filename(
		&handle.archive,
		zip.mz_uint(index),
		filename,
		filename_size,
	) == 0 {
		return "", false
	}

	return strings.clone(string(filename)), true
}

Zip_Read_Index :: proc(
	handle: ^Zip_Handle,
	index: u32,
) -> ([]u8, bool) {
	if handle == nil ||
	   handle.mode != .Reader ||
	   index >= Zip_File_Count(handle) {
		return nil, false
	}

	size: c.size_t
	data := zip.mz_zip_reader_extract_to_heap(
		&handle.archive,
		zip.mz_uint(index),
		&size,
		0,
	)

	if data == nil {
		return nil, false
	}
	defer zip.mz_free(data)

	result := make([]u8, int(size))
	if size > 0 {
		copy(result, mem.slice_ptr(cast(^u8)data, int(size)))
	}

	return result, true
}

Zip_Has_File :: proc(
	handle: ^Zip_Handle,
	path: string,
) -> bool {
	if handle == nil || handle.mode != .Reader {
		return false
	}

	c_path, err := strings.clone_to_cstring(path)
	if err != nil {
		return false
	}
	defer delete(c_path)

	index := zip.mz_zip_reader_locate_file(
		&handle.archive,
		c_path,
		nil,
		0,
	)

	return index >= 0
}

Zip_Read :: proc(
	handle: ^Zip_Handle,
	path: string,
) -> ([]u8, bool) {
	if handle == nil || handle.mode != .Reader {
		return nil, false
	}

	c_path, err := strings.clone_to_cstring(path)
	if err != nil {
		return nil, false
	}
	defer delete(c_path)

	size: c.size_t

	data := zip.mz_zip_reader_extract_file_to_heap(
		&handle.archive,
		c_path,
		&size,
		0,
	)

	if data == nil {
		return nil, false
	}

	defer zip.mz_free(data)

	result := make([]u8, int(size))

	if size > 0 {
		source := mem.slice_ptr(
			cast(^u8)data,
			int(size),
		)

		copy(result, source)
	}

	return result, true
}

Zip_Read_String :: proc(
	handle: ^Zip_Handle,
	path: string,
) -> (string, bool) {
	data, ok := Zip_Read(handle, path)
	if !ok {
		return "", false
	}
	defer delete(data)

	result := strings.clone(string(data))

	return result, true
}

Zip_Extract :: proc(
	handle: ^Zip_Handle,
	archive_path: string,
	destination: string,
) -> bool {
	if handle == nil || handle.mode != .Reader {
		return false
	}

	c_archive_path, err := strings.clone_to_cstring(archive_path)
	if err != nil {
		return false
	}
	defer delete(c_archive_path)

	c_destination, err2 := strings.clone_to_cstring(destination)
	if err2 != nil {
		return false
	}
	defer delete(c_destination)

	return zip.mz_zip_reader_extract_file_to_file(
		&handle.archive,
		c_archive_path,
		c_destination,
		0,
	) != zip.MZ_FALSE
}

Zip_Create :: proc(path: string) -> (^Zip_Handle, bool) {
	handle, alloc_err := mem.new(Zip_Handle)
	if alloc_err != nil {
		return nil, false
	}

	handle.allocator = context.allocator
	handle.mode = .Writer

	zip.mz_zip_zero_struct(&handle.archive)

	c_path, err := strings.clone_to_cstring(path)
	if err != nil {
		_ = mem.free(handle, handle.allocator)
		return nil, false
	}
	defer delete(c_path)

	if zip.mz_zip_writer_init_file(
		&handle.archive,
		c_path,
		0,
	) == zip.MZ_FALSE {
		_ = mem.free(handle, handle.allocator)
		return nil, false
	}

	return handle, true
}

Zip_Add_File :: proc(
	handle: ^Zip_Handle,
	archive_path: string,
	source_path: string,
	compression: zip.mz_uint = ZIP_DEFAULT_COMPRESSION,
) -> bool {
	if handle == nil ||
	   handle.mode != .Writer ||
	   handle.finalized {
		return false
	}

	c_archive, err := strings.clone_to_cstring(archive_path)
	if err != nil {
		return false
	}
	defer delete(c_archive)

	c_source, err2 := strings.clone_to_cstring(source_path)
	if err2 != nil {
		return false
	}
	defer delete(c_source)

	return zip.mz_zip_writer_add_file(
		&handle.archive,
		c_archive,
		c_source,
		nil,
		0,
		compression,
	) != zip.MZ_FALSE
}

Zip_Add_Data :: proc(
	handle: ^Zip_Handle,
	archive_path: string,
	data: []u8,
	compression: zip.mz_uint = ZIP_DEFAULT_COMPRESSION,
) -> bool {
	if handle == nil ||
	   handle.mode != .Writer ||
	   handle.finalized {
		return false
	}

	c_archive, err := strings.clone_to_cstring(archive_path)
	if err != nil {
		return false
	}
	defer delete(c_archive)

	data_ptr: rawptr = nil

	if len(data) > 0 {
		data_ptr = raw_data(data)
	}

	return zip.mz_zip_writer_add_mem(
		&handle.archive,
		c_archive,
		data_ptr,
		c.size_t(len(data)),
		compression,
	) != zip.MZ_FALSE
}

Zip_Add_String :: proc(
	handle: ^Zip_Handle,
	archive_path: string,
	data: string,
	compression: zip.mz_uint = ZIP_DEFAULT_COMPRESSION,
) -> bool {
	if handle == nil ||
	   handle.mode != .Writer ||
	   handle.finalized {
		return false
	}

	c_archive, err := strings.clone_to_cstring(archive_path)
	if err != nil {
		return false
	}
	defer delete(c_archive)

	data_ptr: rawptr = nil

	if len(data) > 0 {
		data_ptr = raw_data(data)
	}

	return zip.mz_zip_writer_add_mem(
		&handle.archive,
		c_archive,
		data_ptr,
		c.size_t(len(data)),
		compression,
	) != zip.MZ_FALSE
}

Zip_Finalize :: proc(handle: ^Zip_Handle) -> bool {
	if handle == nil || handle.mode != .Writer {
		return false
	}

	if handle.finalized {
		return true
	}

	if zip.mz_zip_writer_finalize_archive(
		&handle.archive,
	) == zip.MZ_FALSE {
		return false
	}

	handle.finalized = true

	return true
}

Zip_Last_Error_Code :: proc(
	handle: ^Zip_Handle,
) -> zip.mz_zip_error {
	if handle == nil {
		return .INVALID_PARAMETER
	}

	return zip.mz_zip_get_last_error(&handle.archive)
}

Zip_Last_Error :: proc(handle: ^Zip_Handle) -> string {
	if handle == nil {
		return "Invalid ZIP handle"
	}

	err := zip.mz_zip_get_last_error(&handle.archive)
	message := zip.mz_zip_get_error_string(err)

	if message == nil {
		return "Unknown ZIP error"
	}

	return string(message)
}
