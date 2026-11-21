#+build !js
package packages

import kineffi "../bindings"
import vm "../vm"
import "core:fmt"
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


Load_Internal_Modules_From_Directory :: proc(registry: ^Registry, source_dir: string) -> bool {
	if registry == nil || source_dir == "" {return false}
	loaded: [dynamic]Internal_Module
	keep := false
	defer if !keep {destroy_internal_modules(&loaded)}
	found_entrypoint := false
	walker := os.walker_create(source_dir)
	defer os.walker_destroy(&walker)
	for entry in os.walker_walk(&walker) {
		if entry.type != .Regular || !strings.has_suffix(entry.name, ".luau") {continue}
		relative, err := filepath.rel(source_dir, entry.fullpath, context.allocator)
		if err != nil {return false}
		defer delete(relative)
		normalized, replaced := strings.replace_all(relative, "\\", "/")
		if !replaced {normalized = strings.clone(relative)}
		defer delete(normalized)
		if strings.contains(normalized, "..") || strings.contains(normalized, "\"") {return false}
		data, read_err := os.read_entire_file(entry.fullpath, context.allocator)
		if read_err != nil {return false}
		defer delete(data)
		name := normalized[:len(normalized) - len(".luau")]
		append(
			&loaded,
			Internal_Module {
				name = strings.clone(name),
				source = strings.clone(string(data)),
				owned = true,
			},
		)
		found_entrypoint = found_entrypoint || name == "editor_ui"
	}
	if !found_entrypoint {
		fmt.eprintf("[EditorModules] no editor_ui module in %s\n", source_dir)
		return false
	}
	L: ^vm.State
	if registry.vm_state != nil {L = registry.vm_state.L}
	destroy_internal_modules(&registry.internal_modules, L)
	registry.internal_modules = loaded
	keep = true
	fmt.eprintf("[EditorModules] loaded %d local modules from %s\n", len(loaded), source_dir)
	return true
}
