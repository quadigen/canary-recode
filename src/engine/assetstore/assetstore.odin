// assetstore owns the bytes of assets that travel inside a .kine file.
//
// The serializer rewrites asset-bearing property values to
// "kineasset://<content-id>" and appends the file bytes to the stream's asset
// table. Deserialization publishes that table here *before* any property setter
// runs, so by the time an ImageLabel or MeshPart decodes its reference the blob
// is already addressable. Consumers ask this package to turn a property value
// back into something they can hand to a decoder.
//
// The store is process-global and content-addressed, which is what makes it
// safe to share across maps: identical bytes written by two exports collapse to
// one entry, and re-exporting a loaded map re-embeds the same ids.
package assetstore

import "core:fmt"
import "core:strings"

// KINE_ASSET_SCHEME marks a property value that points at bytes embedded in the
// .kine stream rather than at a file on disk.
KINE_ASSET_SCHEME :: "kineasset://"

// ASSET_CACHE_SUBDIR keeps extracted blobs out of the user's home directory and
// gives them a stable, wipeable home.
ASSET_CACHE_SUBDIR :: "kinemium-assets"

// MAX_ASSET_BYTES bounds a single embedded asset. Meshes are the big case;
// anything larger is a packaging mistake rather than a place file.
MAX_ASSET_BYTES :: 256 * 1024 * 1024

// MAX_ASSET_COUNT bounds the asset table so a corrupt length cannot make the
// reader reserve an unreasonable amount of memory up front.
MAX_ASSET_COUNT :: 1 << 16

// MAX_ASSET_TOTAL_BYTES bounds the sum of every embedded asset in one map.
MAX_ASSET_TOTAL_BYTES :: 512 * 1024 * 1024

// Asset_Kind is advisory metadata. Consumers pick a decoder from the file
// extension carried alongside the bytes, so appending kinds never invalidates
// files written by older builds.
Asset_Kind :: enum u8 {
	Unknown = 0,
	Mesh    = 1,
	Texture = 2,
	Audio   = 3,
	Data    = 4,
}

// Asset is one embedded blob. Bytes are owned by the store.
Asset :: struct {
	id:    string,
	path:  string, // path as authored; kept so an editor round-trip can show it
	kind:  Asset_Kind,
	bytes: []u8,
	// cached is the on-disk copy written by Materialize, so repeated loads of
	// the same content do not re-extract it.
	cached: string,
}

	assets: [dynamic]Asset
	index:  map[string]int
	// missing_reported deduplicates the "the map says this is embedded but it
	// is not here" diagnostic, which would otherwise repeat per instance per frame.
	missing_reported: map[string]bool

FNV_OFFSET: u64 : 14695981039346656037
FNV_PRIME:  u64 : 1099511628211

// Content_Id derives the dedup key for a blob. FNV-1a is what the rest of the
// engine uses for content hashing. It is an identity key rather than a
// checksum: Register also compares the bytes it already holds under a key, so a
// collision resolves to a distinct id instead of aliasing two assets.
Content_Id :: proc(data: []u8) -> string {
	hash := FNV_OFFSET
	for byte in data {
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

// At returns the entry published at an index, in registration order. The pointer
// borrows from the store and is invalidated by the next Register or Clear. The
// serializer uses this to write the asset table back out.
At :: proc(index: int) -> (^Asset, bool) {
	if index < 0 || index >= len(assets) {
		return nil, false
	}
	return &assets[index], true
}

// owned_tprintf formats into an owned string. fmt.tprintf allocates from
// context.temp_allocator, whose results must not be freed, so every string this
// package hands back to a caller is built through here instead.
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

// candidate_id renders the bare hash for attempt 0 and "<hash>-<n>" after that.
// The result is owned by the caller.
candidate_id :: proc(base: string, attempt: int) -> string {
	if attempt == 0 {
		return strings.clone(base)
	}
	return owned_tprintf("%s-%d", base, attempt)
}

// Id_Is_Valid reports whether id has the shape this store produces: 16 lowercase
// hex digits, optionally followed by "-<n>" for a collision attempt.
//
// A .kine is untrusted input and supplies its own ids, and an id is used as a
// cache file name. Without this check a stream could use "../" or a drive
// letter to make Materialize write outside the cache directory, so every id read
// from a stream is validated before it is stored or turned into a path.
Id_Is_Valid :: proc(id: string) -> bool {
	// Exactly 16 lowercase hex digits make up the hash.
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
	// Only the collision suffix "-<n>" is allowed past the hash.
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

// Register stores a blob under a key derived from its contents and returns that
// key. The blob is always consumed: on rejection the bytes are freed, so callers
// must not delete them afterwards. The returned key is an independent copy the
// caller owns; the store keeps its own.
Register :: proc(data: []u8, path: string, kind: Asset_Kind) -> string {
	base := Content_Id(data)
	defer delete(base)

	for attempt := 0; attempt <= 8; attempt += 1 {
		id := candidate_id(base, attempt)
		existing, found := Find(id)
		if !found {
			store(id, path, kind, data)
			return id
		}
		same := bytes_equal(existing.bytes, data)
		if same {
			delete(data)
		}
		delete(id)
		if same {
			// The published key belongs to the store, so hand back a copy.
			return strings.clone(existing.id)
		}
	}

	// Nine collisions on a 64-bit content hash is not a reachable case. Refuse
	// rather than risk aliasing an asset that is already published.
	delete(data)
	return ""
}

// Register_As publishes a blob under a key taken from the file being read. The
// writer already deduplicated, so the key is trusted verbatim; disagreeing with
// an entry that is already published means the stream is corrupt.
Register_As :: proc(id: string, data: []u8, path: string, kind: Asset_Kind) -> bool {
	// The id comes from an untrusted file and ends up in a cache file name, so
	// it has to look like something this store would have produced.
	if !Id_Is_Valid(id) {
		delete(data)
		return false
	}
	if existing, found := Find(id); found {
		same := bytes_equal(existing.bytes, data)
		delete(data)
		return same
	}
	store(id, path, kind, data)
	return true
}

store :: proc(id, path: string, kind: Asset_Kind, data: []u8) {
	if index == nil {
		index = make(map[string]int)
	}
	// Every string is copied so the store owns its metadata outright. A caller
	// that frees its own id or path cannot leave a dangling key behind.
	append(
		&assets,
		Asset{
			id    = strings.clone(id),
			path  = strings.clone(path),
			kind  = kind,
			bytes = data,
		},
	)
	position := len(assets) - 1
	index[assets[position].id] = position
}

// Clear drops every entry. Materialized cache files stay on disk: they are
// content-addressed, so a later load of the same bytes reuses them safely.
Clear :: proc() {
	for &entry in assets {
		delete(entry.id)
		delete(entry.path)
		delete(entry.cached)
		delete(entry.bytes)
	}
	// delete releases the backing memory but leaves the header pointing at it, so
	// a second Clear would walk freed memory and free every string twice. Reset
	// the headers instead; store() rebuilds the map and Count() reads len(assets).
	delete(assets)
	assets = nil
	delete(index)
	index = nil
	// The next map's bad references have not been reported yet.
	Clear_Missing_Asset_Reports()
}

// ---------------------------------------------------------------------------
// Property value resolution
// ---------------------------------------------------------------------------

// Make_Uri builds the property value that stands in for an embedded asset. The
// result is owned by the caller.
Make_Uri :: proc(id: string) -> string {
	return owned_tprintf("%s%s", KINE_ASSET_SCHEME, id)
}

// Parse_Uri splits "kineasset://<id>" into its key. The key borrows from uri.
Parse_Uri :: proc(uri: string) -> (id: string, found: bool) {
	if !strings.has_prefix(uri, KINE_ASSET_SCHEME) {
		return "", false
	}
	id = uri[len(KINE_ASSET_SCHEME):]
	return id, id != ""
}

// Is_Uri reports whether a property value refers to an embedded asset.
Is_Uri :: proc(uri: string) -> bool {
	_, found := Parse_Uri(uri)
	return found
}

// Resolve_Bytes returns the embedded bytes for a "kineasset://" value. The slice
// borrows from the store and stays valid for the process lifetime. Any other
// value (a plain path, "builtin://", "memory://") reports false so callers fall
// through to their normal handling.
Resolve_Bytes :: proc(uri: string) -> (data: []u8, found: bool) {
	id, embedded := Parse_Uri(uri)
	if !embedded {
		return nil, false
	}
	entry, published := Find(id)
	if !published {
		return nil, false
	}
	return entry.bytes, true
}

// Resolve_Path turns a property value into a filesystem path. Plain paths pass
// through with any "file://" prefix removed; embedded assets are extracted to
// the cache directory first. The result is owned by the caller, and an empty
// string means the value could not be resolved.
Resolve_Path :: proc(uri: string) -> string {
	if id, embedded := Parse_Uri(uri); embedded {
		path, extracted := Materialize(id)
		if !extracted {
			return ""
		}
		return path
	}
	return strip_file_scheme(uri)
}

// Resolve_C_Path is Resolve_Path for the many C APIs that want a cstring. It
// returns nil when the value cannot be resolved; otherwise the caller owns the
// result and must delete it.
Resolve_C_Path :: proc(uri: string) -> cstring {
	path := Resolve_Path(uri)
	if path == "" {
		return nil
	}
	defer delete(path)
	return strings.clone_to_cstring(path)
}

// Report_Missing_Asset notes that a "kineasset://" reference could not be
// resolved to bytes.
//
// A plain path that fails to load is ordinary authoring, and consumers already
// have a sensible answer for it. A missing embedded reference never is: the map
// said those bytes were inside it, so the only outcomes are a server that never
// sent its asset table, a client that skipped the map load, or a truncated
// transfer. Left unreported, every one of those renders as a primitive box and
// looks like a working scene.
//
// Reports are deduplicated per value because these lookups happen per instance
// per part per frame, and a map with one bad reference would otherwise flood the
// log with the same line.
Report_Missing_Asset :: proc(uri, subject: string) {
	if !Is_Uri(uri) {return}
	if missing_reported == nil {
		missing_reported = make(map[string]bool)
	}
	if uri in missing_reported {return}
	missing_reported[uri] = true
	fmt.eprintf(
		"[Assets] %s could not resolve %s. The map says it is embedded, so it is missing rather than absent. If this is a network client, the server may not have sent its asset table.\n",
		subject,
		uri,
	)
}

// Clear_Missing_Asset_Reports forgets what has already been reported. Loading a
// map replaces the store wholesale, so the next map starts with a clean slate
// rather than staying quiet about its own bad references.
Clear_Missing_Asset_Reports :: proc() {
	if missing_reported == nil {return}
	for key in missing_reported {
		delete(key)
	}
	delete(missing_reported)
}

// Format_Hint is the extension Assimp uses to pick an importer for in-memory
// bytes. It returns a lowercase extension with no dot ("fbx"), or an empty
// string when the authoring path carried none. The result is owned by the
// caller.
Format_Hint :: proc(uri: string) -> string {
	path := uri
	if id, embedded := Parse_Uri(uri); embedded {
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

extension_of :: proc(path: string) -> string {
	// The extension is the last dot after the final separator. A dot that opens
	// a component marks a hidden file, not an extension, so ".fbx" has none.
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
