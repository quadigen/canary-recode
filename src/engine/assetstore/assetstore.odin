


package assetstore

import "core:fmt"
import "core:strings"


KINE_ASSET_SCHEME :: "kineasset://"
PROJECT_ASSET_SCHEME :: "project://"


ASSET_CACHE_SUBDIR :: "kinemium-assets"


MAX_ASSET_BYTES :: 256 * 1024 * 1024


MAX_ASSET_COUNT :: 1 << 16


MAX_ASSET_TOTAL_BYTES :: 512 * 1024 * 1024


Asset_Kind :: enum u8 {
	Unknown   = 0,
	Mesh      = 1,
	Texture   = 2,
	Audio     = 3,
	Data      = 4,
	Path_File = 5,
	Animation = 6,
}


Asset :: struct {
	id:     string,
	path:   string,
	kind:   Asset_Kind,
	bytes:  []u8,
	cached: string,
}

assets: [dynamic]Asset
index: map[string]int
path_files: map[string]int
project_root: string


missing_reported: map[string]bool

FNV_OFFSET: u64 : 14695981039346656037
FNV_PRIME: u64 : 1099511628211


Content_Id :: proc(data: []u8, path := "") -> string {
	hash := FNV_OFFSET
	for byte in data {
		hash ~= u64(byte)
		hash *= FNV_PRIME
	}
	for byte in transmute([]u8)path {
		hash ~= u64(byte)
		hash *= FNV_PRIME
	}
	hash ~= u64(len(data))
	hash *= FNV_PRIME
	return owned_tprintf("%016x", hash)
}

Find :: proc(id: string) -> (^Asset, bool) {
	if id == "" {
		return nil, false
	}
	position, found := index[id]
	if !found {
		return nil, false
	}
	return &assets[position], true
}

Count :: proc() -> int {
	return len(assets)
}


At :: proc(index: int) -> (^Asset, bool) {
	if index < 0 || index >= len(assets) {
		return nil, false
	}
	return &assets[index], true
}


owned_tprintf :: proc(format: string, args: ..any) -> string {
	return strings.clone(fmt.tprintf(format, ..args))
}

bytes_equal :: proc(a, b: []u8) -> bool {
	if len(a) != len(b) {
		return false
	}
	for value, i in a {
		if value != b[i] {
			return false
		}
	}
	return true
}


candidate_id :: proc(base: string, attempt: int) -> string {
	if attempt == 0 {
		return strings.clone(base)
	}
	return owned_tprintf("%s-%d", base, attempt)
}


Id_Is_Valid :: proc(id: string) -> bool {

	index := 0
	for index < 16 && index < len(id) {
		c := id[index]
		is_digit := c >= '0' && c <= '9'
		is_lower_hex := c >= 'a' && c <= 'f'
		if !is_digit && !is_lower_hex {
			return false
		}
		index += 1
	}
	if index != 16 {
		return false
	}
	if index == len(id) {
		return true
	}

	if id[index] != '-' {
		return false
	}
	index += 1
	if index == len(id) {
		return false
	}
	for index < len(id) {
		c := id[index]
		if c < '0' || c > '9' {
			return false
		}
		index += 1
	}
	return true
}


Register :: proc(data: []u8, path: string, kind: Asset_Kind) -> string {
	base := Content_Id(data, kind == .Path_File ? path : "")
	defer delete(base)

	for attempt := 0; attempt <= 8; attempt += 1 {
		id := candidate_id(base, attempt)
		existing, found := Find(id)
		if !found {
			store(id, path, kind, data)
			return id
		}
		same :=
			bytes_equal(existing.bytes, data) &&
			(kind != .Path_File || (existing.kind == kind && existing.path == path))
		if same {
			delete(data)
		}
		delete(id)
		if same {

			return strings.clone(existing.id)
		}
	}


	delete(data)
	return ""
}


Register_As :: proc(id: string, data: []u8, path: string, kind: Asset_Kind) -> bool {


	if !Id_Is_Valid(id) {
		delete(data)
		return false
	}
	if existing, found := Find(id); found {
		same := bytes_equal(existing.bytes, data)
		delete(data)
		if kind != .Path_File {return same}
		return same && existing.kind == kind && existing.path == path
	}
	store(id, path, kind, data)
	return true
}

store :: proc(id, path: string, kind: Asset_Kind, data: []u8) {
	if index == nil {
		index = make(map[string]int)
	}


	append(
		&assets,
		Asset{id = strings.clone(id), path = strings.clone(path), kind = kind, bytes = data},
	)
	position := len(assets) - 1
	index[assets[position].id] = position
	if kind == .Path_File {
		if path_files == nil {
			path_files = make(map[string]int)
		}
		path_files[assets[position].path] = position
	}
}


Clear :: proc() {
	for &entry in assets {
		delete(entry.id)
		delete(entry.path)
		delete(entry.cached)
		delete(entry.bytes)
	}


	delete(assets)
	assets = nil
	delete(index)
	index = nil
	delete(path_files)
	path_files = nil

	Clear_Missing_Asset_Reports()
}


Make_Uri :: proc(id: string) -> string {
	return owned_tprintf("%s%s", KINE_ASSET_SCHEME, id)
}


Parse_Uri :: proc(uri: string) -> (id: string, found: bool) {
	if !strings.has_prefix(uri, KINE_ASSET_SCHEME) {
		return "", false
	}
	id = uri[len(KINE_ASSET_SCHEME):]
	return id, id != ""
}


Is_Uri :: proc(uri: string) -> bool {
	_, found := Parse_Uri(uri)
	return found
}

Find_Path_File :: proc(path: string) -> (^Asset, bool) {
	key := strings.trim_prefix(path, "file://")
	position, found := path_files[key]
	if !found {return nil, false}
	return &assets[position], true
}

Set_Project_Root :: proc(path: string) {
	replacement := strings.clone(path)
	delete(project_root)
	project_root = replacement
}

Project_Asset_Path :: proc(uri: string) -> (string, bool) {
	if !strings.has_prefix(uri, PROJECT_ASSET_SCHEME) {return "", false}
	path := uri[len(PROJECT_ASSET_SCHEME):]
	if path == "" ||
	   strings.has_suffix(path, "/") ||
	   strings.contains_any(path, "\\:\x00") {return "", false}
	pieces := path
	for piece in strings.split_iterator(&pieces, "/") {


		if piece == "" ||
		   piece == "." ||
		   piece == ".." ||
		   strings.has_suffix(piece, ".") ||
		   strings.has_suffix(piece, " ") {return "", false}
	}
	return path, true
}

resolve_embedded_id :: proc(value: string) -> (string, bool) {
	if id, embedded := Parse_Uri(value); embedded {return id, true}
	if project_root != "" && strings.has_prefix(value, PROJECT_ASSET_SCHEME) {return "", false}
	if file, found := Find_Path_File(value); found {return file.id, true}
	return "", false
}


Resolve_Bytes :: proc(uri: string) -> (data: []u8, found: bool) {
	id, embedded := resolve_embedded_id(uri)
	if !embedded {
		return nil, false
	}
	entry, published := Find(id)
	if !published {
		return nil, false
	}
	return entry.bytes, true
}


Resolve_Path :: proc(uri: string) -> string {
	if id, embedded := resolve_embedded_id(uri); embedded {
		path, extracted := Materialize(id)
		if !extracted {
			return ""
		}
		return path
	}
	if strings.has_prefix(uri, PROJECT_ASSET_SCHEME) {return resolve_project_path(uri)}
	return strip_file_scheme(uri)
}


Resolve_C_Path :: proc(uri: string) -> cstring {
	path := Resolve_Path(uri)
	if path == "" {
		return nil
	}
	defer delete(path)
	return strings.clone_to_cstring(path)
}

UGC_Assets_Enabled :: proc() -> bool {
	return #config(BUILD_TARGET, "editor") != "editor"
}

Resolve_Ugc_Asset :: proc(value: string, kind: Asset_Kind) -> string {
	if id, found := resolve_embedded_id(value); found {return Make_Uri(id)}
	if value == "" || !UGC_Assets_Enabled() {
		return strings.clone(value)
	}
	if (strings.contains(value, "://") && !strings.has_prefix(value, "file://")) ||
	   strings.has_prefix(value, "data:") {
		return strings.clone(value)
	}
	data, found := Read_Asset_File(value)
	if !found || len(data) == 0 {
		if data != nil {delete(data)}
		return strings.clone(value)
	}
	id := Register(data, value, kind)
	defer delete(id)
	if id == "" {
		return strings.clone(value)
	}
	return Make_Uri(id)
}

Report_Missing_Asset :: proc(uri, subject: string) {
	if !Is_Uri(uri) {return}
	if missing_reported == nil {
		missing_reported = make(map[string]bool)
	}
	if uri in missing_reported {return}

	missing_reported[strings.clone(uri)] = true
	fmt.eprintf(
		"[Assets] %s could not resolve %s. The map says it is embedded, so it is missing rather than absent. If this is a network client, the server may not have sent its asset table.\n",
		subject,
		uri,
	)
}


Clear_Missing_Asset_Reports :: proc() {
	if missing_reported == nil {return}
	for key in missing_reported {
		delete(key)
	}
	delete(missing_reported)
	missing_reported = nil
}


Format_Hint :: proc(uri: string) -> string {
	path := uri
	if id, embedded := resolve_embedded_id(uri); embedded {
		entry, published := Find(id)
		if !published {
			return ""
		}
		path = entry.path
	}
	return extension_of(path)
}

strip_file_scheme :: proc(path: string) -> string {
	if strings.has_prefix(path, "file://") {
		return strings.clone(path[len("file://"):])
	}
	return strings.clone(path)
}

Is_Ugc_File_Path :: proc(path: string) -> bool {
	if strings.has_prefix(path, "data:") ||
	   strings.contains(path, "://") ||
	   strings.contains(path, "\x00") ||
	   strings.contains(path, "\n") {return false}
	ext := extension_of(path)
	defer delete(ext)
	switch ext {
	case "png",
	     "svg",
	     "jpeg",
	     "jpg",
	     "webp",
	     "gif",
	     "bmp",
	     "ico",
	     "tga",
	     "dds",
	     "ktx",
	     "ktx2",
	     "glb",
	     "gltf",
	     "obj",
	     "fbx",
	     "dae",
	     "stl",
	     "ply",
	     "3ds",
	     "blend",
	     "3mf",
	     "wav",
	     "mp3",
	     "ogg",
	     "flac",
	     "opus",
	     "aiff",
	     "aif",
	     "m4a",
	     "ttf",
	     "otf",
	     "ttc",
	     "woff",
	     "woff2":
		return true
	}
	return false
}

extension_of :: proc(path: string) -> string {


	dot := -1
	component_start := 0
	for i in 0 ..< len(path) {
		if path[i] == '/' || path[i] == '\\' {
			component_start = i + 1
			dot = -1
		} else if path[i] == '.' && i > component_start {
			dot = i
		}
	}
	if dot < 0 || dot == len(path) - 1 {
		return ""
	}
	extension := path[dot + 1:]
	if len(extension) == 0 || len(extension) > 12 {
		return ""
	}
	buffer: [12]u8
	for i in 0 ..< len(extension) {
		char := extension[i]
		switch {
		case char >= 'A' && char <= 'Z':
			buffer[i] = char + 32
		case (char >= 'a' && char <= 'z') || (char >= '0' && char <= '9'):
			buffer[i] = char
		case:
			return ""
		}
	}
	return strings.clone(string(buffer[:len(extension)]))
}
