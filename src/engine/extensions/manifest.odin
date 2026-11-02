package extensions


import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

MANIFEST_FILE :: "extension.json"

Manifest :: struct {
	id:            string,
	name:          string,
	version:       string,
	author:        string,
	description:   string,
	api_major:     u32,
	api_minor:     u32,
	library:       string,
	entry:         string,
	enabled:       bool,
	dependencies:  []string,
	capabilities:  []string,
	directory:     string,
	manifest_path: string,
}

Manifest_Destroy :: proc(manifest: ^Manifest) {
	if manifest == nil {
		return
	}
	delete(manifest.id)
	delete(manifest.name)
	delete(manifest.version)
	delete(manifest.author)
	delete(manifest.description)
	delete(manifest.library)
	delete(manifest.entry)
	for dependency in manifest.dependencies {
		delete(dependency)
	}
	delete(manifest.dependencies)
	for capability in manifest.capabilities {
		delete(capability)
	}
	delete(manifest.capabilities)
	delete(manifest.directory)
	delete(manifest.manifest_path)
	manifest^ = {}
}

@(private)
json_field :: proc(obj: json.Object, key: string) -> (json.Value, bool) {
	value, ok := obj[key]
	return value, ok
}

@(private)
field_string :: proc(obj: json.Object, key: string, fallback: string = "") -> string {
	if value, ok := json_field(obj, key); ok {
		if text, is_string := value.(json.String); is_string {
			return strings.clone(string(text))
		}
	}
	return strings.clone(fallback)
}

@(private)
field_bool :: proc(obj: json.Object, key: string, fallback: bool) -> bool {
	if value, ok := json_field(obj, key); ok {
		if flag, is_bool := value.(json.Boolean); is_bool {
			return bool(flag)
		}
	}
	return fallback
}

@(private)
field_u32 :: proc(obj: json.Object, key: string, fallback: u32) -> u32 {
	if value, ok := json_field(obj, key); ok {
		#partial switch v in value {
		case json.Integer:
			if v < 0 {
				return fallback
			}
			return u32(v)
		case json.Float:
			if v < 0 {
				return fallback
			}
			return u32(v)
		}
	}
	return fallback
}

@(private)
field_string_list :: proc(obj: json.Object, key: string) -> []string {
	value, ok := json_field(obj, key)
	if !ok {
		return nil
	}
	array, is_array := value.(json.Array)
	if !is_array {
		return nil
	}
	result := make([dynamic]string, 0, len(array))
	for entry in array {
		if text, is_string := entry.(json.String); is_string {
			append(&result, strings.clone(string(text)))
		}
	}
	return result[:]
}


manifest_id_is_valid :: proc(id: string) -> bool {
	if len(id) == 0 || len(id) > 96 {
		return false
	}
	for index in 0 ..< len(id) {
		char := id[index]
		switch {
		case char >= 'a' && char <= 'z':
		case char >= 'A' && char <= 'Z':
		case char >= '0' && char <= '9':
		case char == '.' || char == '_' || char == '-':
		case:
			return false
		}
	}
	return true
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

manifest_has_capability :: proc(manifest: ^Manifest, capability: string) -> bool {
	if manifest == nil {
		return false
	}
	for entry in manifest.capabilities {
		if entry == capability {
			return true
		}
	}
	return false
}
