package main

import kineffi "../src/engine/bindings"
import "core:fmt"
import "core:os"

join :: proc(a, b: string) -> string {
	path, err := os.join_path({a, b}, context.temp_allocator)
	assert(err == nil)
	return path
}

main :: proc() {
	root, err := os.make_directory_temp("", "kine-security-archive-*", context.allocator)
	assert(err == nil)
	defer {
		_ = os.remove_all(root)
		delete(root)
	}
	archive := join(root, "fixture.zip")
	writer, opened := kineffi.Zip_Create(archive)
	assert(opened)
	assert(kineffi.Zip_Add_String(writer, "nested/item.txt", "new"))
	assert(kineffi.Zip_Close(writer))
	reader, read_ok := kineffi.Zip_Open(archive)
	assert(read_ok)
	defer _ = kineffi.Zip_Close(reader)

	outside := join(root, "outside")
	assert(os.make_directory(outside) == nil)
	canary := join(outside, "item.txt")
	assert(os.write_entire_file_from_string(canary, "original") == nil)
	output := join(root, "output")
	assert(os.make_directory(output) == nil)
	nested := join(output, "nested")
	when ODIN_OS != .Windows {
		assert(os.symlink(outside, nested) == nil)
		assert(!kineffi.Zip_Extract_All(reader, output))
		assert(os.remove(nested) == nil)
	}
	assert(os.make_directory(nested) == nil)
	target := join(nested, "item.txt")
	when ODIN_OS != .Windows {
		assert(os.symlink(canary, target) == nil)
		assert(!kineffi.Zip_Extract_All(reader, output))
		assert(os.remove(target) == nil)
		assert(os.link(canary, target) == nil)
	} else {
		assert(os.write_entire_file_from_string(target, "old") == nil)
	}
	assert(kineffi.Zip_Extract_All(reader, output))
	data, data_err := os.read_entire_file(target, context.temp_allocator)
	assert(data_err == nil && string(data) == "new")
	original, original_err := os.read_entire_file(canary, context.temp_allocator)
	assert(original_err == nil && string(original) == "original")
	fmt.println("SECURITY_ARCHIVE_SMOKE_PASSED")
}
