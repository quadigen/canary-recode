#+build !js

package assetstore

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:testing"

store_lock: sync.Mutex

hold_store :: proc() {
	sync.lock(&store_lock)
}

release_store :: proc() {
	sync.unlock(&store_lock)
}

blob :: proc(data: ..u8) -> []u8 {
	out := make([]u8, len(data))
	for value, i in data {
		out[i] = value
	}
	return out
}

@(test)
content_id_is_stable_and_length_sensitive :: proc(t: ^testing.T) {
	expect := testing.expect

	first := Content_Id([]u8{'a', 'b', 'c'})
	second := Content_Id([]u8{'a', 'b', 'c'})
	expect(t, first == second, "identical bytes hash identically")
	delete(first)
	delete(second)

	short := Content_Id([]u8{'b', 'c'})
	long := Content_Id([]u8{'a', 'b', 'c'})
	expect(t, short != long, "length is part of the key")
	delete(short)
	delete(long)

	empty := Content_Id(nil)
	also_empty := Content_Id({})
	expect(t, empty == also_empty, "empty is one key")
	delete(empty)
	delete(also_empty)
}

@(test)
register_dedups_by_content :: proc(t: ^testing.T) {
hold_store()
defer release_store()
	expect := testing.expect
	Clear()
	defer Clear()

	first := Register(blob('m', 'e', 's', 'h'), "a/hero.fbx", .Mesh)
	second := Register(blob('m', 'e', 's', 'h'), "b/other.fbx", .Mesh)
	expect(t, first == second, "same bytes collapse to one key")
	expect(t, Count() == 1, "dedup does not add a second entry")

	third := Register(blob('d', 'i', 'f', 'f'), "c/wall.fbx", .Mesh)
	expect(t, third != first, "different bytes get a different key")
	expect(t, Count() == 2, "distinct bytes are stored separately")

	entry, found := Find(first)
	expect(t, found, "first key resolves")
	expect(t, entry.kind == .Mesh, "kind recorded")
	expect(t, entry.path == "a/hero.fbx", "authored path retained")

	delete(first)
	delete(second)
	delete(third)
}

@(test)
register_empty_blob :: proc(t: ^testing.T) {
hold_store()
defer release_store()
	expect := testing.expect
	Clear()
	defer Clear()

	id := Register(nil, "empty.dat", .Data)
	expect(t, id != "", "empty bytes still get a key")

	entry, found := Find(id)
	expect(t, found, "empty entry resolves")
	expect(t, len(entry.bytes) == 0, "empty blob stays empty")

	again := Register(nil, "other.dat", .Data)
	expect(t, again == id, "empty blobs dedup")
	expect(t, Count() == 1, "one entry only")

	delete(id)
	delete(again)
}

@(test)
register_as_dedups_the_stream_id :: proc(t: ^testing.T) {
hold_store()
defer release_store()
	expect := testing.expect
	Clear()
	defer Clear()

	expect(
		t,
		Register_As("0123456789abcdef", blob('1'), "tex.png", .Texture),
		"first publish succeeds",
	)
	expect(
		t,
		Register_As("0123456789abcdef", blob('1'), "tex.png", .Texture),
		"identical republish succeeds",
	)
	expect(t, Count() == 1, "no duplicate entry")

	expect(
		t,
		!Register_As("0123456789abcdef", blob('2'), "tex.png", .Texture),
		"mismatched bytes are refused",
	)
	expect(t, Count() == 1, "refusal does not publish")

	entry, found := Find("0123456789abcdef")
	expect(t, found, "entry survives the refusal")
	expect(t, len(entry.bytes) == 1 && entry.bytes[0] == '1', "bytes unchanged")

	expect(t, !Register_As("", blob('3'), "x.png", .Texture), "empty id refused")
	expect(t, Count() == 1, "empty id publishes nothing")
}

@(test)
uri_round_trip :: proc(t: ^testing.T) {
	expect := testing.expect

	uri := Make_Uri("abc123")
	defer delete(uri)
	expect(t, strings.has_prefix(uri, KINE_ASSET_SCHEME), "scheme applied")

	id, found := Parse_Uri(uri)
	expect(t, found, "embedded uri parses")
	expect(t, id == "abc123", "id recovered")

	expect(t, Is_Uri(uri), "Is_Uri accepts an embedded value")
	expect(t, !Is_Uri("models/hero.fbx"), "plain path is not embedded")
	expect(t, !Is_Uri("builtin://cube"), "builtin is not embedded")
	expect(t, !Is_Uri(KINE_ASSET_SCHEME), "bare scheme is not embedded")

	empty_id, empty_found := Parse_Uri("models/hero.fbx")
	expect(t, !empty_found && empty_id == "", "plain path reports no id")
}

@(test)
resolve_bytes_only_handles_embedded_values :: proc(t: ^testing.T) {
hold_store()
defer release_store()
	expect := testing.expect
	Clear()
	defer Clear()

	id := Register(blob(1, 2, 3, 4), "tex.png", .Texture)
	defer delete(id)
	uri := Make_Uri(id)
	defer delete(uri)

	data, found := Resolve_Bytes(uri)
	expect(t, found, "embedded bytes resolve")
	expect(t, len(data) == 4 && data[3] == 4, "bytes are the stored blob")

	unknown := Make_Uri("deadbeef")
	defer delete(unknown)
	missing, missing_found := Resolve_Bytes(unknown)
	expect(t, !missing_found && len(missing) == 0, "unknown id reports false")
	delete(missing)

	plain, plain_found := Resolve_Bytes("tex.png")
	expect(t, !plain_found && len(plain) == 0, "plain path falls through")
}

format_hint_case :: struct {
	path: string,
	want: string,
}

@(test)
format_hint_normalizes_extensions :: proc(t: ^testing.T) {
	expect := testing.expect

	cases := []format_hint_case{
		{"models/hero.FBX", "fbx"},
		{"models/hero.fbx", "fbx"},
		{`C:\art\hero.gltf`, "gltf"},
		{"archive.tar.gz", "gz"},
		{"models/hero", ""},
		{"models/.hidden", ""},
		{"tex.averylongextension", ""},
		{"tex.pn g", ""},
		{"tex.p%ng", ""},
	}
	for test_case in cases {
		got := Format_Hint(test_case.path)
		expect(
			t,
			got == test_case.want,
			fmt_hint_message(test_case.path, test_case.want, got),
		)
		delete(got)
	}
}

@(test)
format_hint_uses_the_authored_path :: proc(t: ^testing.T) {
hold_store()
defer release_store()
	expect := testing.expect
	Clear()
	defer Clear()

	id := Register(blob('g'), "models/hero.FBX", .Mesh)
	defer delete(id)
	uri := Make_Uri(id)
	defer delete(uri)

	hint := Format_Hint(uri)
	defer delete(hint)
	expect(t, hint == "fbx", "hint comes from the asset's own path")
}

@(test)
resolve_path_passes_plain_paths_through :: proc(t: ^testing.T) {
	expect := testing.expect

	plain := Resolve_Path("models/hero.fbx")
	defer delete(plain)
	expect(t, plain == "models/hero.fbx", "plain path is unchanged")

	stripped := Resolve_Path("file://models/hero.fbx")
	defer delete(stripped)
	expect(t, stripped == "models/hero.fbx", "file scheme is removed")

	backslashed := Resolve_Path(`file://C:\art\hero.fbx`)
	defer delete(backslashed)
	expect(t, backslashed == `C:\art\hero.fbx`, "windows path survives")

	absent := Make_Uri("missing")
	defer delete(absent)
	unresolvable := Resolve_Path(absent)
	defer delete(unresolvable)
	expect(t, unresolvable == "", "unknown embedded id has no path")
}

@(test)
materialize_extracts_into_the_cache :: proc(t: ^testing.T) {
hold_store()
defer release_store()
	expect := testing.expect
	Clear()
	defer Clear()

	payload := blob('b', 'i', 'n', 'a', 'r', 'y')
	id := Register(payload, "models/hero.fbx", .Mesh)
	defer delete(id)

	path, extracted := Materialize(id)
	expect(t, extracted, "materialize succeeds")
	defer delete(path)

	expect(t, os.exists(path), "file landed on disk")
	expect(t, strings.has_suffix(path, ".fbx"), "authored extension is kept")
	expect(
		t,
		strings.contains(path, ASSET_CACHE_SUBDIR),
		"file lives under the cache directory",
	)

	expect(t, !strings.contains(path, "models"), "authored directories are dropped")
	expect(t, !strings.contains(path, ".."), "no traversal in the cached name")

	cached_data, read_err := os.read_entire_file(path, context.allocator)
	defer delete(cached_data)
	expect(t, read_err == nil, "cached file is readable")
	expect(t, bytes_equal(cached_data, payload), "cached bytes match the blob")

	again, second_pass := Materialize(id)
	defer delete(again)
	expect(t, second_pass, "second materialize succeeds")
	expect(t, again == path, "cached path is reused, not rewritten")

	os.remove(path)
}

@(test)
materialize_rejects_traversal_in_the_extension :: proc(t: ^testing.T) {
hold_store()
defer release_store()
	expect := testing.expect
	Clear()
	defer Clear()

	id := Register(blob('z'), "evil/../../escape.fbx", .Mesh)
	defer delete(id)

	path, extracted := Materialize(id)
	expect(t, extracted, "materialize succeeds")
	defer delete(path)

	cache := cache_directory(context.allocator)
	defer delete(cache)
	expect(
		t,
		strings.has_prefix(path, cache),
		"materialized path stays inside the cache directory",
	)

	os.remove(path)
}

@(test)
register_as_rejects_an_id_that_is_not_a_content_id :: proc(t: ^testing.T) {
	hold_store()
	defer release_store()
	expect := testing.expect
	Clear()
	defer Clear()

	for hostile in ([]string{
		`../../../windows/system32/evil`,
		`..\\..\\evil`,
		`C:\\evil`,
		`nothexatall`,
		`0123456789ABCDEF`,
		`0123456789abcde`,
		`0123456789abcdef-`,
		`0123456789abcdef-x`,
		`0123456789abcdef.fbx`,
		` `,
	}) {
		accepted := Register_As(hostile, blob('x'), "authored/path.fbx", .Mesh)
		expect(t, !accepted, fmt.tprintf("rejected hostile id %q", hostile))
	}

	if Count() != 0 {
		panic("a hostile id reached the store")
	}

	for valid in ([]string{
		`0123456789abcdef`,
		`abcdef0123456789`,
		`0000000000000000`,
		`0123456789abcdef-1`,
		`0123456789abcdef-8`,
	}) {
		accepted := Register_As(valid, blob('y'), "authored/path.fbx", .Mesh)
		expect(t, accepted, fmt.tprintf("accepted content id %q", valid))
	}
}

@(test)
id_validation_matches_the_stored_form :: proc(t: ^testing.T) {
	hold_store()
	defer release_store()
	expect := testing.expect
	Clear()
	defer Clear()

	for attempt := 0; attempt < 3; attempt += 1 {
		id := Register(blob('q'), "authored/thing.fbx", .Texture)
		defer delete(id)
		expect(t, Id_Is_Valid(id), fmt.tprintf("stored id %q is valid", id))
	}
}

@(test)
materialize_works_without_an_extension :: proc(t: ^testing.T) {
	hold_store()
	defer release_store()
	expect := testing.expect
	Clear()
	defer Clear()

	id := Register(blob('n'), "authored/thing", .Data)
	defer delete(id)

	path, extracted := Materialize(id)
	expect(t, extracted, "materialize succeeds without an extension")
	defer delete(path)
	expect(t, os.exists(path), "the cache file was written")
	expect(t, filepath.base(path) == id, "the file name is the bare content id")

	os.remove(path)
}

@(test)
read_asset_file_reads_from_disk :: proc(t: ^testing.T) {
	expect := testing.expect

	blob := []u8{'h', 'i'}
	temporary, temp_err := os.temp_dir(context.allocator)
	expect(t, temp_err == nil, "temp dir resolved")
	defer delete(temporary)
	source, join_err := filepath.join(
		[]string{temporary, "assetstore_read_probe.bin"},
		context.allocator,
	)
	expect(t, join_err == nil, "probe path built")
	defer delete(source)
	defer os.remove(source)

	write_err := os.write_entire_file(source, blob)
	expect(t, write_err == nil, "probe file written")

	data, found := Read_Asset_File(source)
	expect(t, found, "plain path reads")
	expect(t, bytes_equal(data, blob), "bytes match")
	delete(data)

	uri_not_a_path := Make_Uri("ignored")
	defer delete(uri_not_a_path)
	data, found = Read_Asset_File(uri_not_a_path)
	expect(t, !found, "a uri is not a readable path")

	data, found = Read_Asset_File("")
	expect(t, !found, "empty path is refused")

	prefixed := fmt.tprintf("file://%s", source)
	data, found = Read_Asset_File(prefixed)
	expect(t, found, "file scheme is accepted")
	delete(data)
}

@(test)
clear_drops_every_entry :: proc(t: ^testing.T) {
hold_store()
defer release_store()
	expect := testing.expect
	Clear()
	defer Clear()

	id := Register(blob('c'), "tex.png", .Texture)
	defer delete(id)
	expect(t, Count() == 1, "one entry stored")

	Clear()
	expect(t, Count() == 0, "clear empties the store")

	_, found := Find(id)
	expect(t, !found, "cleared ids no longer resolve")

	next := Register(blob('d'), "tex.png", .Texture)
	defer delete(next)
	expect(t, next != "", "register works after clear")
	expect(t, Count() == 1, "exactly one entry after clear")
}

fmt_hint_message :: proc(path, want, got: string) -> string {
	return fmt.tprintf("Format_Hint(%q) = %q, want %q", path, got, want)
}
