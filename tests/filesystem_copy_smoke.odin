package main

import services "../src/engine/services"
import "core:fmt"
import "core:os"

ROOT :: "build/filesystem_copy_smoke"

expect :: proc(cond: bool, msg: string) {
	if !cond {
		fmt.eprintln("EXPECT FAILED:", msg)
		panic(msg)
	}
}

join :: proc(a, b: string) -> string {
	path, err := os.join_path({a, b}, context.temp_allocator)
	assert(err == nil, "join")
	return path
}

main :: proc() {
	os.remove_all(ROOT)
	defer os.remove_all(ROOT)
	assert(os.make_directory_all(ROOT) == nil, "setup: make root")


	source := join(ROOT, "file.txt")
	_ = os.write_entire_file_from_string(source, "hello")

	dest, ok := services.Project_Unique_Child_Path(ROOT, "file.txt")
	expect(ok, "collision should resolve a unique path")
	expect(
		services.Project_Entry_Name(dest) == "file (2).txt",
		"collision should pick 'file (2).txt'",
	)
	delete(dest)

	copy_dest, copy_ok := services.Project_Unique_Child_Path(ROOT, "file.txt")
	expect(copy_ok, "unique child path should resolve")
	expect(services.Project_Copy_Entry(source, copy_dest), "file copy should succeed")
	expect(os.exists(copy_dest), "copied file should exist")
	copied, read_err := os.read_entire_file(copy_dest, context.temp_allocator)
	expect(read_err == nil && string(copied) == "hello", "copied file should match source")
	delete(copy_dest)


	next_dest, next_ok := services.Project_Unique_Child_Path(ROOT, "file.txt")
	expect(next_ok, "third unique child path should resolve")
	expect(
		services.Project_Entry_Name(next_dest) == "file (3).txt",
		"second collision should pick 'file (3).txt'",
	)
	delete(next_dest)


	source_dir := join(ROOT, "folder")
	_ = os.make_directory(source_dir)
	_ = os.write_entire_file_from_string(join(source_dir, "inner.txt"), "inner")

	dir_dest, dir_ok := services.Project_Unique_Child_Path(ROOT, "folder")
	expect(dir_ok, "unique folder path should resolve")
	expect(
		services.Project_Entry_Name(dir_dest) == "folder (2)",
		"folder collision should pick 'folder (2)'",
	)
	expect(services.Project_Copy_Entry(source_dir, dir_dest), "folder copy should succeed")
	expect(os.exists(join(dir_dest, "inner.txt")), "copied folder should contain inner.txt")
	delete(dir_dest)

	fmt.println("FILESYSTEM_COPY_SMOKE_PASSED")
}
