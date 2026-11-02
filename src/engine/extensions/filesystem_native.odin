#+build !js

package extensions

import debuglog "../debuglog"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

platform_library_candidates :: proc(directory: string) -> []string {
	entries, read_err := os.read_all_directory_by_path(directory, context.temp_allocator)
	if read_err != nil {
		return nil
	}

	result := make([dynamic]string)
	for entry in entries {
		if !platform_is_library_name(entry.name) {
			continue
		}
		path := platform_join(directory, entry.name)
		if !os.is_file(path) {
			delete(path)
			continue
		}
		append(&result, path)
	}


	for index in 1 ..< len(result) {
		current := result[index]
		probe := index - 1
		for probe >= 0 && result[probe] > current {
			result[probe + 1] = result[probe]
			probe -= 1
		}
		result[probe + 1] = current
	}

	return result[:]
}

Manifest_Load :: proc(directory: string) -> (manifest: Manifest, err: string) {
	path := platform_join(directory, MANIFEST_FILE)

	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		return {}, fmt.aprintf("cannot read %s", path)
	}
	defer delete(data, context.allocator)

	value, parse_err := json.parse_string(
		string(data),
		parse_integers = false,
		allocator = context.allocator,
	)
	if parse_err != nil {
		return {}, fmt.aprintf("%s: malformed JSON (%v)", path, parse_err)
	}
	defer json.destroy_value(value)

	obj, is_object := value.(json.Object)
	if !is_object {
		return {}, fmt.aprintf("%s: the manifest root must be a JSON object", path)
	}

	manifest = Manifest {
		id            = field_string(obj, "id"),
		name          = field_string(obj, "name"),
		version       = field_string(obj, "version", "0.0.0"),
		author        = field_string(obj, "author"),
		description   = field_string(obj, "description"),
		api_major     = field_u32(obj, "api", KNE_ABI_MAJOR),
		api_minor     = field_u32(obj, "api_minor", KNE_ABI_MINOR),
		library       = field_string(obj, "library"),
		entry         = field_string(obj, "entry", KNE_ENTRY_SYMBOL),
		enabled       = field_bool(obj, "enabled", true),
		dependencies  = field_string_list(obj, "dependencies"),
		capabilities  = field_string_list(obj, "capabilities"),
		directory     = strings.clone(directory),
		manifest_path = strings.clone(path),
	}

	if !manifest_id_is_valid(manifest.id) {
		Manifest_Destroy(&manifest)
		return {}, fmt.aprintf("%s: \"id\" is missing or contains unsupported characters", path)
	}
	if len(manifest.name) == 0 {
		manifest.name = strings.clone(manifest.id)
	}
	if len(manifest.entry) == 0 {
		manifest.entry = strings.clone(KNE_ENTRY_SYMBOL)
	}

	return manifest, ""
}

Discover :: proc(context_state: ^Context, directory: string) -> (loaded: int, err: string) {
	if context_state == nil || context_state.host == nil {
		return 0, strings.clone("the extension system is not initialized")
	}
	if len(directory) == 0 {
		return 0, strings.clone("no extension directory was given")
	}
	if !os.is_directory(directory) {
		return 0, ""
	}

	delete(context_state.directory)
	context_state.directory = strings.clone(directory)

	directories := make([dynamic]string)
	defer {
		for entry in directories {
			delete(entry)
		}
		delete(directories)
	}

	if os.exists(platform_join(directory, MANIFEST_FILE)) {
		append(&directories, strings.clone(directory))
	} else {
		entries, read_err := os.read_all_directory_by_path(directory, context.temp_allocator)
		if read_err != nil {
			return 0, fmt.aprintf("cannot read the extension directory %s", directory)
		}
		for entry in entries {
			child := platform_join(directory, entry.name)
			if !os.is_directory(child) {
				delete(child)
				continue
			}
			if !os.exists(platform_join(child, MANIFEST_FILE)) {
				delete(child)
				continue
			}
			append(&directories, child)
		}
	}

	Pending :: struct {
		manifest: Manifest,
		done:     bool,
		failed:   bool,
		reason:   string,
	}

	pending := make([dynamic]Pending, 0, len(directories))
	defer {
		for &entry in pending {
			Manifest_Destroy(&entry.manifest)
			delete(entry.reason)
		}
		delete(pending)
	}

	for extension_directory in directories {
		manifest, manifest_err := Manifest_Load(extension_directory)
		if manifest_err != "" {
			if len(err) == 0 {
				err = manifest_err
			} else {
				debuglog.Log(fmt.tprintf("KNE: %s", manifest_err))
				delete(manifest_err)
			}
			continue
		}
		if !manifest.enabled {
			debuglog.Log(fmt.tprintf("KNE: %s is disabled", manifest.id))
			Manifest_Destroy(&manifest)
			continue
		}
		append(&pending, Pending{manifest = manifest})
	}

	remaining := len(pending)
	progress := true
	for remaining > 0 && progress {
		progress = false
		for &entry in pending {
			if entry.done || entry.failed {
				continue
			}

			resolved := true
			for dependency in entry.manifest.dependencies {
				if Find(context_state, dependency) == nil {
					resolved = false
					break
				}
			}
			if !resolved {
				continue
			}

			_, load_err := load_record(context_state, &entry.manifest)
			if load_err != "" {
				entry.failed = true
				entry.reason = strings.clone(load_err)
				remaining -= 1
				if len(err) == 0 {
					err = load_err
				} else {
					delete(load_err)
				}
				continue
			}

			entry.done = true
			remaining -= 1
			loaded += 1
			progress = true
		}
	}

	if remaining > 0 {
		for &entry in pending {
			if entry.done || entry.failed {
				continue
			}
			reason := fmt.aprintf(
				"%s: unresolved dependencies (%s)",
				entry.manifest.id,
				strings.join(entry.manifest.dependencies, ", "),
			)
			dbg_message := fmt.tprintf("KNE: %s", reason)
			debuglog.Log(dbg_message)
			if len(err) == 0 {
				err = reason
			} else {
				delete(reason)
			}
		}
	}

	return loaded, err
}

@(private)
resolve_library_path :: proc(manifest: ^Manifest) -> (string, string) {
	if len(manifest.library) > 0 {
		path := platform_join(manifest.directory, manifest.library)
		if !os.is_file(path) {
			delete(path)
			return "", fmt.aprintf("%s: library %q is missing", manifest.id, manifest.library)
		}
		return path, ""
	}

	candidates := platform_library_candidates(manifest.directory)
	defer {
		for candidate in candidates {
			delete(candidate)
		}
		delete(candidates)
	}

	if len(candidates) == 0 {
		return "", fmt.aprintf(
			"%s: no dynamic library (%s) in %s",
			manifest.id,
			LIBRARY_FILENAME_SUFFIX,
			manifest.directory,
		)
	}
	if len(candidates) > 1 {
		debuglog.Log(
			fmt.tprintf(
				"KNE: %s has %d libraries, using %s; set \"library\" in the manifest to be explicit",
				manifest.id,
				len(candidates),
				candidates[0],
			),
		)
	}
	return strings.clone(candidates[0]), ""
}
