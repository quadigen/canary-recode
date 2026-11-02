package extensions


import "core:encoding/json"
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
