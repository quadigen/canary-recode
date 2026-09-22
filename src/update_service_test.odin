#+build !js

package main

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import services "engine/services"

@(test)
update_version_compare_test :: proc(t: ^testing.T) {
	expect := testing.expect
	compare := services.Update_Version_Compare

	expect(t, compare("1.2.3", "1.2.2") > 0, "patch bump")
	expect(t, compare("1.2.3", "1.2.3") == 0, "equal")
	expect(t, compare("1.2.2", "1.2.3") < 0, "patch downgrade")
	expect(t, compare("1.3.0", "1.2.10") > 0, "minor beats patch")
	expect(t, compare("2.0.0", "1.9.9") > 0, "major beats minor")
	expect(t, compare("v1.2.3", "1.2.3") == 0, "leading v is ignored")

	expect(t, compare("1.2.3", "1.2.3-dev") > 0, "release beats prerelease")
	expect(t, compare("1.2.3-dev", "1.2.3") < 0, "prerelease loses to release")
	expect(t, compare("1.2.3-alpha", "1.2.3-beta") < 0, "alpha < beta")
	expect(t, compare("1.2.3+build.5", "1.2.3") == 0, "build metadata ignored")

	expect(t, compare("", "1.0.0") < 0, "empty loses")
	expect(t, compare("whatever", "tracking-main") == 0, "garbage compares equal")
}

@(test)
update_asset_name_test :: proc(t: ^testing.T) {
	expect := testing.expect

	name := services.Update_Asset_Name("windows", "x86_64")
	expect(t, name == "kinemium-windows-x86_64.zip", "windows asset name")
	delete(name)

	name = services.Update_Asset_Name("macos", "arm64")
	expect(t, name == "kinemium-macos-arm64.zip", "macos asset name")
	delete(name)

	name = services.Update_Asset_Name("linux", "x86_64")
	expect(t, name == "kinemium-linux-x86_64.zip", "linux asset name")
	delete(name)
}

@(test)
update_swap_bundle_test :: proc(t: ^testing.T) {
	expect := testing.expect

	pending_dir, pending_err := os.make_directory_temp("", "kinemium-update-test-*", context.allocator)
	expect(t, pending_err == nil, "create pending directory")
	defer os.remove_all(pending_dir)
	defer delete(pending_dir)

	target_dir, target_err := os.make_directory_temp("", "kinemium-target-test-*", context.allocator)
	expect(t, target_err == nil, "create target directory")
	defer os.remove_all(target_dir)
	defer delete(target_dir)

	bundle_exe := test_join(pending_dir, "kinemium.exe")
	expect(t, bundle_exe != "", "bundle exe path")
	if bundle_exe == "" { return }
	defer delete(bundle_exe)

	bundle_sdl := test_join(pending_dir, "SDL3.dll")
	expect(t, bundle_sdl != "", "bundle dll path")
	if bundle_sdl == "" { return }
	defer delete(bundle_sdl)

	bundle_version := test_join(pending_dir, services.UPDATE_PENDING_VERSION_NAME)
	expect(t, bundle_version != "", "bundle marker path")
	if bundle_version == "" { return }
	defer delete(bundle_version)

	expect(t, os.write_entire_file_from_string(bundle_exe, "new-engine-bytes") == nil, "write bundle exe")
	expect(t, os.write_entire_file_from_string(bundle_sdl, "new-sdl-bytes") == nil, "write bundle dll")
	expect(t, os.write_entire_file_from_string(bundle_version, "v2.0.0") == nil, "write bundle marker")

	target_exe := test_join(target_dir, "kinemium-editor.exe")
	expect(t, target_exe != "", "target exe path")
	if target_exe == "" { return }
	defer delete(target_exe)

	target_sdl := test_join(target_dir, "SDL3.dll")
	expect(t, target_sdl != "", "target dll path")
	if target_sdl == "" { return }
	defer delete(target_sdl)

	expect(t, os.write_entire_file_from_string(target_exe, "old-engine-bytes") == nil, "write target exe")
	expect(t, os.write_entire_file_from_string(target_sdl, "old-sdl-bytes") == nil, "write target dll")

	swapped := services.Update_Swap_Bundle(pending_dir, target_exe)
	expect(t, swapped, "swap the bundle into place")

	expect(t, read_text_eq(target_exe, "new-engine-bytes"), "engine executable was replaced")
	expect(t, read_text_eq(target_sdl, "new-sdl-bytes"), "SDL3.dll was replaced")

	marker_in_target := test_join(target_dir, services.UPDATE_PENDING_VERSION_NAME)
	defer delete(marker_in_target)
	expect(t, !os.exists(marker_in_target), "pending marker is never copied into the target")
}

@(test)
update_pending_version_detected_test :: proc(t: ^testing.T) {
	expect := testing.expect

	// update_pending_read sweeps a fresh (empty) pending root without crashing.
	version, pending_dir, ready := services.Update_Pending_Read()
	if len(version) > 0 {
		delete(version)
	}
	if len(pending_dir) > 0 {
		delete(pending_dir)
	}
	expect(t, !ready || len(version) > 0, "pending read is consistent")
}

read_text :: proc(path: string) -> string {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		return ""
	}
	text := strings.clone(string(data))
	delete(data)
	return text
}

read_text_eq :: proc(path, expected: string) -> bool {
	text := read_text(path)
	defer delete(text)
	return text == expected
}

test_join :: proc(dir, name: string) -> string {
	joined, err := filepath.join([]string{dir, name}, context.allocator)
	if err != nil {
		return ""
	}
	return joined
}