package main

import serializer "../src/engine/serializer"
import "core:fmt"
import "core:os"
import "core:path/filepath"

Progress_Capture :: struct {
	values: [dynamic]f32,
}

record_progress :: proc(value: f32, userdata: rawptr) {
	capture := cast(^Progress_Capture)userdata
	append(&capture.values, value)
}

assert_payload :: proc(path: string, expected: []u8) {
	saved, read_err := os.read_entire_file(path, context.allocator)
	assert(read_err == nil, "could not read exported file")
	defer delete(saved)
	decoded, repack_err := serializer.Repack_File_Data(saved, 0)
	assert(serializer.Error_Is_None(repack_err), "could not decompress exported file")
	defer serializer.Error_Delete(&repack_err)
	defer delete(decoded)
	assert(len(decoded) == len(expected), "export size changed")
	for b, i in decoded {assert(b == expected[i], "export payload changed")}
}

main :: proc() {
	dir, dir_err := os.make_directory_temp(
		"",
		"kinemium-export-progress-audit-*",
		context.allocator,
	)
	assert(dir_err == nil)
	defer delete(dir)
	defer os.remove_all(dir)
	path, join_err := filepath.join([]string{dir, "map.kine"}, context.temp_allocator)
	assert(join_err == nil)

	payload := make([]u8, 4 * 1024 * 1024)
	defer delete(payload)
	for &byte, i in payload {byte = u8((i * 73 + i / 13) % 256)}
	capture: Progress_Capture
	defer delete(capture.values)
	value: f32
	err := serializer.Write_File_Data_Progress(path, payload, &value, record_progress, &capture)
	assert(serializer.Error_Is_None(err), "export unexpectedly failed")
	serializer.Error_Delete(&err)
	assert(value == 1)
	assert(len(capture.values) >= 4, "progress callback did not publish milestones")
	assert(capture.values[0] > 0 && capture.values[0] < 1)
	assert(capture.values[len(capture.values) - 1] == 1)
	saw_writing := false
	previous: f32
	for item in capture.values {
		assert(item >= previous && item <= 1, "progress was not monotonic")
		if item > 0.55 && item < 1 {saw_writing = true}
		previous = item
	}
	assert(saw_writing, "progress did not publish intermediate file writes")
	assert_payload(path, payload)


	loaded, bounded_read_error := serializer.Deserialize_From_File(nil, nil, nil, path)
	assert(
		loaded == nil && bounded_read_error.kind == .Invalid_Argument,
		"bounded descriptor read did not reach the parser",
	)
	serializer.Error_Delete(&bounded_read_error)


	small := []u8{'K', 'I', 'N', 'E', 0, 1, 2, 3}
	err = serializer.Write_File_Data(path, small)
	assert(serializer.Error_Is_None(err), "sync replacement failed")
	serializer.Error_Delete(&err)
	assert_payload(path, small)


	occupied, occupied_err := filepath.join([]string{dir, "occupied"}, context.temp_allocator)
	assert(occupied_err == nil)
	assert(os.make_directory(occupied) == nil)
	err = serializer.Write_File_Data(occupied, payload)
	assert(!serializer.Error_Is_None(err), "invalid target directory was replaced")
	serializer.Error_Delete(&err)
	assert(os.is_directory(occupied))
	nonregular_loaded, directory_error := serializer.Deserialize_From_File(nil, nil, nil, occupied)
	assert(
		nonregular_loaded == nil && directory_error.kind == .File_Read_Failed,
		"non-regular KINE paths must be refused",
	)
	serializer.Error_Delete(&directory_error)


	oversized, oversize_path_err := filepath.join(
		[]string{dir, "oversized.kine"},
		context.temp_allocator,
	)
	assert(oversize_path_err == nil)
	file, open_err := os.create(oversized)
	assert(open_err == nil)
	_, seek_err := os.seek(file, i64(serializer.KINE_MAX_STREAM_BYTES), .Start)
	assert(seek_err == nil)
	count, write_err := os.write(file, []u8{0})
	assert(write_err == nil && count == 1)
	os.close(file)
	oversize_loaded, read_error := serializer.Deserialize_From_File(nil, nil, nil, oversized)
	assert(oversize_loaded == nil && read_error.kind == .Stream_Too_Large)
	serializer.Error_Delete(&read_error)

	fmt.println("EXPORT_PROGRESS_AUDIT_PASSED")
}
