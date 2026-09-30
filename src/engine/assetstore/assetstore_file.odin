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

	status, stat_err := os.stat(path, context.allocator)
	if stat_err != nil || status.type != .Regular || status.size < 0 ||
	   status.size > i64(MAX_ASSET_BYTES) {
		return nil, false
	}

	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		return nil, false
	}
	return data, true
}

Materialize :: proc(id: string) -> (string, bool) {
	entry, found := Find(id)
	if !found {
		return "", false
	}
	if len(entry.cached) > 0 {
		if os.exists(entry.cached) {
			return strings.clone(entry.cached), true
		}
		delete(entry.cached)
		entry.cached = ""
	}
	if len(entry.bytes) == 0 {
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

	if !os.exists(path) && os.write_entire_file(path, entry.bytes) != nil {
		return "", false
	}

	entry.cached = strings.clone(path)
	return strings.clone(path), true
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
		return true
	}
	parent := filepath.dir(path)
	if parent != path && parent != "" && !make_directories(parent) {
		return false
	}
	if os.make_directory(path) == nil {
		return true
	}
	return os.exists(path)
}
