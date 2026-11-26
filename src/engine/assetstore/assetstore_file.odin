#+build !js

package assetstore

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

Read_Asset_File :: proc(authored: string) -> ([]u8, bool) {
	if authored == "" {
		return nil, false
	}
	path := strip_file_scheme(authored)
	defer delete(path)


	file, open_err := os.open(path)
	if open_err != nil {return nil, false}
	defer os.close(file)
	status, stat_err := os.fstat(file, context.allocator)
	if stat_err != nil {return nil, false}
	defer os.file_info_delete(status, context.allocator)
	if status.type != .Regular || status.size < 0 || status.size > i64(MAX_ASSET_BYTES) {
		return nil, false
	}

	data := make([]u8, int(status.size))
	read := 0
	for read < len(data) {
		n, read_err := os.read(file, data[read:])
		if read_err != nil || n <= 0 {
			delete(data)
			return nil, false
		}
		read += n
	}

	probe: [1]u8
	n, read_err := os.read(file, probe[:])
	if n != 0 || (read_err != nil && read_err != .EOF) {
		delete(data)
		return nil, false
	}
	return data, true
}

resolve_project_path :: proc(uri: string) -> string {
	path, valid := Project_Asset_Path(uri)
	if project_root == "" || !valid {return ""}
	current := project_root
	pieces := path
	for piece in strings.split_iterator(&pieces, "/") {
		joined, join_err := filepath.join({current, piece}, context.temp_allocator)
		if join_err != nil {return ""}
		info, stat_err := os.lstat(joined, context.temp_allocator)
		if stat_err != nil {return ""}
		link := info.type == .Symlink
		os.file_info_delete(info, context.temp_allocator)
		if link {return ""}
		current = joined
	}
	return strings.clone(current)
}

Materialize :: proc(id: string) -> (string, bool) {
	entry, found := Find(id)
	if !found {
		return "", false
	}
	if len(entry.cached) > 0 {
		if cached_file_matches(entry.cached, entry.bytes) {
			return strings.clone(entry.cached), true
		}
		delete(entry.cached)
		entry.cached = ""
	}
	if len(entry.bytes) == 0 && entry.kind != .Path_File {
		return "", false
	}

	directory := cache_directory()
	if directory == "" || !make_directories(directory) {
		return "", false
	}

	if !Id_Is_Valid(id) {
		return "", false
	}
	extension := extension_of(entry.path)
	defer delete(extension)

	name: string
	if extension == "" {
		name = strings.clone(id)
	} else {
		name = owned_tprintf("%s.%s", id, extension)
	}
	defer delete(name)
	path, join_err := filepath.join([]string{directory, name}, context.temp_allocator)
	if join_err != nil {
		return "", false
	}

	if !cached_file_matches(path, entry.bytes) {
		if !write_cache_atomically(directory, path, entry.bytes) {
			return "", false
		}
	}

	entry.cached = strings.clone(path)
	return strings.clone(path), true
}


cached_file_matches :: proc(path: string, expected: []u8) -> bool {
	info, stat_err := os.lstat(path, context.temp_allocator)
	if stat_err != nil {return false}
	defer os.file_info_delete(info, context.temp_allocator)
	if info.type != .Regular || info.size != i64(len(expected)) {return false}

	file, open_err := os.open(path)
	if open_err != nil {return false}
	defer os.close(file)
	opened, opened_err := os.fstat(file, context.temp_allocator)
	if opened_err != nil {return false}
	defer os.file_info_delete(opened, context.temp_allocator)
	if opened.type != .Regular || opened.size != i64(len(expected)) {return false}

	if info.inode != 0 &&
	   opened.inode != 0 &&
	   (info.inode != opened.inode || info.device != opened.device) {return false}

	buffer: [64 * 1024]u8
	offset := 0
	for offset < len(expected) {
		chunk := min(len(buffer), len(expected) - offset)
		n, read_err := os.read(file, buffer[:chunk])
		if read_err != nil || n <= 0 || !bytes_equal(buffer[:n], expected[offset:offset + n]) {
			return false
		}
		offset += n
	}

	probe: [1]u8
	n, read_err := os.read(file, probe[:])
	return n == 0 && (read_err == nil || read_err == .EOF)
}


write_cache_atomically :: proc(directory, destination: string, data: []u8) -> bool {
	file, create_err := os.create_temp_file(directory, "asset-*.tmp")
	if create_err != nil {return false}
	temporary := strings.clone(os.name(file))
	defer delete(temporary)
	defer os.remove(temporary)
	_ = os.fchmod(file, os.perm(0o600))

	written := 0
	for written < len(data) {
		n, write_err := os.write(file, data[written:])
		if write_err != nil || n <= 0 {
			os.close(file)
			return false
		}
		written += n
	}
	if os.close(file) != nil {return false}
	if os.rename(temporary, destination) != nil {


		if os.remove(destination) != nil || os.rename(temporary, destination) != nil {
			return false
		}
	}
	return true
}

Purge_Cache :: proc() -> bool {
	directory := cache_directory()
	if directory == "" {
		return true
	}
	if !os.exists(directory) {
		return true
	}
	return os.remove_all(directory) == nil
}

cache_directory :: proc(allocator := context.temp_allocator) -> string {
	root, root_err := os.user_cache_dir(context.allocator)
	if root_err != nil {
		return ""
	}
	defer delete(root)

	directory, join_err := filepath.join([]string{root, ASSET_CACHE_SUBDIR}, allocator)
	if join_err != nil {
		return ""
	}
	return directory
}

make_directories :: proc(path: string) -> bool {
	if path == "" {
		return false
	}
	if os.exists(path) {
		info, stat_err := os.lstat(path, context.temp_allocator)
		if stat_err != nil {return false}
		defer os.file_info_delete(info, context.temp_allocator)
		return info.type == .Directory
	}
	parent := filepath.dir(path)
	if parent != path && parent != "" && !make_directories(parent) {
		return false
	}
	if os.make_directory(path) == nil {
		return true
	}
	info, stat_err := os.lstat(path, context.temp_allocator)
	if stat_err != nil {return false}
	defer os.file_info_delete(info, context.temp_allocator)
	return info.type == .Directory
}
