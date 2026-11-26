#+build !js
package extensions

import "core:os"
import "core:path/filepath"
import "core:testing"

@(test)
manifest_library_paths_are_relative_and_normalized :: proc(t: ^testing.T) {
	for valid in ([]string{"extension.so", "lib/extension.so", "bin/plugins/extension.dylib"}) {
		testing.expect(t, manifest_library_name_valid(valid), "relative library name accepted")
	}
	for invalid in ([]string{"", "../plugin.so", "lib/../../plugin.so", "/tmp/plugin.so", `C:\\plugin.dll`, `lib\\plugin.so`, "lib//plugin.so", "./plugin.so", "lib/.. /plugin.so", "plugin.so ", "plugin.so.", "plugin.so\x00", "plugin.so\n"}) {
		testing.expect(t, !manifest_library_name_valid(invalid), "invalid library name rejected")
	}
	testing.expect(
		t,
		!manifest_id_is_valid(".") && !manifest_id_is_valid(".."),
		"dot-only manifest ids rejected",
	)
}

@(test)
extension_library_resolution_does_not_follow_symlinks :: proc(t: ^testing.T) {
	cache, cache_err := os.user_cache_dir(context.allocator)
	testing.expect(t, cache_err == nil, "user cache exists")
	if cache_err != nil {return}
	defer delete(cache)
	root, err := os.make_directory_temp(cache, "kne-security-*", context.allocator)
	testing.expect(t, err == nil, "isolated extension fixture created")
	if err != nil {return}
	defer delete(root)
	defer os.remove_all(root)
	inner, _ := filepath.join([]string{root, "inner"}, context.allocator)
	outside, _ := filepath.join([]string{root, "outside"}, context.allocator)
	defer delete(inner)
	defer delete(outside)
	_ = os.make_directory(inner)
	_ = os.make_directory(outside)
	inside_lib, _ := filepath.join([]string{inner, "good.so"}, context.allocator)
	outside_lib, _ := filepath.join([]string{outside, "bad.so"}, context.allocator)
	defer delete(inside_lib)
	defer delete(outside_lib)
	_ = os.write_entire_file(inside_lib, []u8{'x'})
	_ = os.write_entire_file(outside_lib, []u8{'x'})
	testing.expect(t, library_stays_in_extension(inner, "good.so"), "normal library resolves")
	testing.expect(
		t,
		!library_stays_in_extension(inner, "../outside/bad.so"),
		"parent traversal refused",
	)
	link, _ := filepath.join([]string{inner, "redirect.so"}, context.allocator)
	defer delete(link)
	if os.symlink(outside_lib, link) == nil {
		testing.expect(
			t,
			!library_stays_in_extension(inner, "redirect.so"),
			"symlinked library refused",
		)
	}
}

@(test)
manifest_loader_refuses_oversized_json :: proc(t: ^testing.T) {
	cache, cache_err := os.user_cache_dir(context.allocator)
	if cache_err != nil {testing.expect(t, false, "cache directory available"); return}
	defer delete(cache)
	root, temp_err := os.make_directory_temp(cache, "kne-json-security-*", context.allocator)
	if temp_err != nil {testing.expect(t, false, "fixture directory created"); return}
	defer delete(root)
	defer os.remove_all(root)
	manifest_file, join_err := filepath.join([]string{root, MANIFEST_FILE}, context.allocator)
	if join_err != nil {testing.expect(t, false, "manifest path joined"); return}
	defer delete(manifest_file)

	valid_json := `{"id":"security-test-extension", "library":"plugin.so"}`
	testing.expect(
		t,
		os.write_entire_file(manifest_file, valid_json) == nil,
		"valid manifest written",
	)
	valid, valid_err := Manifest_Load(root)
	testing.expect(t, valid_err == "", "small manifest loads")
	if valid_err == "" {Manifest_Destroy(&valid)} else {delete(valid_err)}

	too_large := make([]u8, MAX_MANIFEST_BYTES + 1)
	defer delete(too_large)
	testing.expect(
		t,
		os.write_entire_file(manifest_file, too_large) == nil,
		"oversized manifest written",
	)
	_, oversized_err := Manifest_Load(root)
	testing.expect(t, oversized_err != "", "oversized manifest rejected before JSON parsing")
	delete(oversized_err)
}
