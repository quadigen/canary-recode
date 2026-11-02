package main

import "core:fmt"
import "core:os"

import packages "../src/engine/packages"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import target "../src/engine/target"
import vm "../src/engine/vm"
import sandbox "../src/sandboxed"

EDITOR_SOURCE_CANDIDATES := []string {
	"C:/Users/devco/Documents/kinemium-editor/internal",
	"../kinemium-editor/internal",
	"../../kinemium-editor/internal",
}

local_editor_archive :: proc(archive_path: string) -> bool {
	source_dir := ""
	for candidate in EDITOR_SOURCE_CANDIDATES {
		if os.is_dir(candidate) {
			source_dir = candidate
			break
		}
	}
	if source_dir == "" {
		return false
	}

	added, ok := packages.Pack_Internal_Modules_From_Directory(
		archive_path,
		source_dir,
		context.allocator,
	)
	if !ok {
		return false
	}

	return true
}

main :: proc() {
	target.set_mode(.Editor)
	target.set_playtest(false)

	script_vm := vm.New()
	environment: engine_runtime.Environment
	renderer_object: renderer.RendererObject

	vm.AddGlobal_Boolean(&script_vm, "IsPlaytest", false)

	archive_path := "build/editor-package-upload-smoke.zip"
	defer os.remove(archive_path)

	if !local_editor_archive(archive_path) {
		fmt.eprintln("no local editor checkout")
		os.exit(1)
	}

	sandbox.init_runtime(&script_vm, &environment, &renderer_object)
	defer sandbox.shutdown()

	if !packages.Load_Internal_Modules_From_Blob(&environment.packages, archive_path) {
		panic("failed to load the local editor sources")
	}

	probe := `
local package_upload = require("@internal/package_upload")
assert(package_upload ~= nil, "package_upload module missing")
local marketplace = require("@internal/marketplace")
assert(type(marketplace) == "function", "marketplace module missing")
local target = Instance.new("Folder")
target.Name = "PackageSmoke"
package_upload.open(target)
`
	ok, err := vm.RunInternal(&script_vm, probe, "package_upload_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		vm.Close(&script_vm)
		os.exit(1)
	}

	vm.Close(&script_vm)
	fmt.println("PACKAGE_UPLOAD_SMOKE_PASSED")
}
