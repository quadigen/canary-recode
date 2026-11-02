#+build !js
package packages

import kineffi "../bindings"
import "core:os"
import "core:path/filepath"
import "core:strings"

Pack_Internal_Modules_From_Directory :: proc(
	archive_path, source_dir: string,
	allocator := context.allocator,
) -> (
	added: int,
	ok: bool,
) {
	archive, created := kineffi.Zip_Create(archive_path)
	if !created {
		return 0, false
	}

	walker := os.walker_create(source_dir)
	defer os.walker_destroy(&walker)

	for entry in os.walker_walk(&walker) {
		if entry.type != .Regular || !strings.has_suffix(entry.name, ".luau") {
			continue
		}

		relative, rel_err := filepath.rel(source_dir, entry.fullpath, allocator)
		if rel_err != nil {
			continue
		}

		zip_relative, replaced := strings.replace_all(relative, "\\", "/", allocator)
		if !replaced {
			zip_relative = strings.clone(relative, allocator)
		}
		delete(relative, allocator)

		data, read_err := os.read_entire_file(entry.fullpath, allocator)
		if read_err != nil {
			delete(zip_relative, allocator)
			continue
		}

		module_path := strings.concatenate({"internal/", zip_relative}, allocator)
		stored := kineffi.Zip_Add_String(archive, module_path, string(data))
		delete(module_path, allocator)
		delete(zip_relative, allocator)
		delete(data, allocator)

		if !stored {
			_ = kineffi.Zip_Close(archive)
			return added, false
		}
		added += 1
	}

	if !kineffi.Zip_Close(archive) || added == 0 {
		return added, false
	}
	return added, true
}
