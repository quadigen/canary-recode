package main

import "core:fmt"
import "core:os"
import "core:strings"

import kineffi "../src/engine/bindings"
import packages "../src/engine/packages"
import engine_runtime "../src/engine/runtime"
import renderer "../src/engine/renderer"
import sandbox "../src/sandboxed"
import services "../src/engine/services"
import vm "../src/engine/vm"

// The editor UI lives in a separate repository. When a checkout is present the
// test packs it itself so the code under review is exercised instead of the
// release archive the engine downloads at startup.
EDITOR_SOURCE_CANDIDATES := []string{
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

	entries, err := os.read_directory_by_path(source_dir, -1, context.allocator)
	if err != nil {
		return false
	}
	defer os.file_info_slice_delete(entries, context.allocator)

	archive, created := kineffi.Zip_Create(archive_path)
	if !created {
		return false
	}

	added := 0
	for entry in entries {
		if entry.type != .Regular || !strings.has_suffix(entry.name, ".luau") {
			continue
		}

		data, read_err := os.read_entire_file(entry.fullpath, context.allocator)
		if read_err != nil {
			continue
		}

		module_path := strings.concatenate({"internal/", entry.name})
		stored := kineffi.Zip_Add_String(archive, module_path, string(data))
		delete(module_path)
		delete(data, context.allocator)

		if !stored {
			_ = kineffi.Zip_Close(archive)
			return false
		}
		added += 1
	}

	if !kineffi.Zip_Close(archive) || added == 0 {
		return false
	}

	fmt.printf("[DestroyedInstance] packed %d editor modules from %s\n", added, source_dir)
	return true
}

REGRESSION_SCRIPT :: `
local UI = require("@internal/editor_ui")
local shared = UI.shared()

assert(game.CoreGui:FindFirstChild("Studio") ~= nil, "the editor UI did not start")

-- Phase 1: the reported failure. A container with buttons destroyed outside of
-- UI.clear (engine teardown, a plugin, a plain :Destroy()) used to leave button
-- records behind that pointed at a detached Instance, and the next rebuild
-- aborted with "insufficient security capabilities to access this Instance".
local staleHost = UI.frame(UI.root(), UDim2.fromOffset(0, 0), UDim2.fromOffset(240, 140), Color3.new(0, 0, 0))
local staleButton = UI.button(staleHost, "Stale", UDim2.fromOffset(0, 0), UDim2.fromOffset(90, 24), function() end)

local recordsBefore = #shared.buttons

staleHost:Destroy()

local rebuilt = UI.frame(UI.root(), UDim2.fromOffset(0, 0), UDim2.fromOffset(120, 60), Color3.new(0, 0, 0))

-- The rebuild has to walk a live child; that is the moment the stale record is
-- inspected.
UI.frame(rebuilt, UDim2.fromOffset(0, 0), UDim2.fromOffset(20, 20), Color3.new(0, 0, 0))

local clearOk, clearError = pcall(function()
	UI.clear(rebuilt)
end)
assert(clearOk, "UI.clear aborted on a destroyed Instance: " .. tostring(clearError))
assert(#shared.buttons < recordsBefore, "the destroyed button record was not dropped")

-- Phase 2: the helpers the registry cleanup relies on.
assert(type(UI.isAlive) == "function", "UI.isAlive is missing")
assert(type(UI.forgetButtons) == "function", "UI.forgetButtons is missing")
assert(not UI.isAlive(staleButton), "a destroyed button was reported as alive")
assert(not UI.isAlive(nil), "nil must not be reported as alive")

local readOk, readError = pcall(function()
	return staleButton.Name
end)
assert(not readOk, "reading a destroyed Instance should fail")
assert(string.find(tostring(readError), "destroyed", 1, true) ~= nil, "misleading error: " .. tostring(readError))

-- UI.clear still destroys live children and prunes only their records.
local parent = UI.frame(UI.root(), UDim2.fromOffset(0, 0), UDim2.fromOffset(240, 140), Color3.new(0, 0, 0))
local kept = UI.frame(parent, UDim2.fromOffset(0, 0), UDim2.fromOffset(40, 40), Color3.new(0, 0, 0))
local pruned = UI.frame(parent, UDim2.fromOffset(0, 50), UDim2.fromOffset(40, 40), Color3.new(0, 0, 0))

UI.button(pruned, "B", UDim2.fromOffset(0, 0), UDim2.fromOffset(40, 20), function() end)

local recordsWithButtons = #shared.buttons

UI.clear(parent, { [kept] = true })

assert(kept.Parent == parent, "UI.clear removed a kept child")
assert(#shared.buttons < recordsWithButtons, "UI.clear did not prune the destroyed button record")

-- Prompts own a ScreenGui full of buttons and are torn down with destroyOnClose.
local prompt, _, promptController = UI.prompt({
	title = "Destroyed instance",
	buttons = { { id = "ok", text = "OK" } },
})

assert(prompt ~= nil and promptController ~= nil, "the prompt was not created")

local promptRecords = #shared.buttons
assert(promptRecords > 0, "the prompt did not register its buttons")

promptController:Destroy()

local promptOk, promptError = pcall(function()
	UI.clear(rebuilt)
end)
assert(promptOk, tostring(promptError))
assert(#shared.buttons < promptRecords, "prompt records survived the prompt being destroyed")

assert(UI.isAlive(UI.getWindow("Explorer")), "the Explorer window did not survive the resize")
print("DESTROYED_INSTANCE_REGRESSION_OK")
`

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	renderer_object: renderer.RendererObject

	defer sandbox.shutdown()
	defer vm.Close(&script_vm)

	archive_path := "build/editor-local-sources.zip"
	if local_editor_archive(archive_path) {
		defer os.remove(archive_path)

		sandbox.init_runtime(&script_vm, &environment, &renderer_object)
		if !packages.Load_Internal_Modules_From_Blob(&environment.packages, archive_path) {
			panic("failed to load the local editor sources")
		}
		sandbox.run_modules(environment.packages.internal_modules[:])
	} else {
		fmt.println("[DestroyedInstance] no local editor checkout; using the cached editor archive")
		sandbox.init(&script_vm, &environment, &renderer_object)
	}

	width: i32 = 960
	height: i32 = 640

	surface := kineffi.Kine_Skia_Surface_Create(width, height)
	assert(surface != nil)
	defer kineffi.Kine_Skia_Surface_Destroy(surface)

	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 255)
	engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, width, height, 1.0/60.0)
	engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, width, height, 1.0/60.0)

	// Resizing rebuilds the editor layout, which is when the compatibility
	// callbacks used to abort on a destroyed Instance.
	services.Resize(&environment.services, &environment.datatypes, 1280, 800)
	engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, 1280, 800, 1.0/60.0)
	engine_runtime.Environment_Render_Overlay(&environment, &script_vm, surface, 1280, 800, 1.0/60.0)

	ok, err := vm.RunInternal(&script_vm, REGRESSION_SCRIPT, "editor_destroyed_instance_regression")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("destroyed-instance regression failed")
	}

	fmt.println("EDITOR_DESTROYED_INSTANCE_SMOKE_PASSED")
}
