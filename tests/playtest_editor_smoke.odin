package main

import "core:fmt"
import "core:os"
import "core:strings"

import packages "../src/engine/packages"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
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

	fmt.printf("[PlaytestSmoke] packed %d editor modules from %s\n", added, source_dir)
	return true
}


run_case :: proc(label: string, mode: target.Mode, playtest: bool) -> bool {
	target.set_mode(mode)
	target.set_playtest(playtest)

	script_vm := vm.New()
	environment: engine_runtime.Environment
	renderer_object: renderer.RendererObject


	vm.AddGlobal_Boolean(&script_vm, "IsPlaytest", playtest)

	archive_path := strings.concatenate({"build/editor-playtest-", label, ".zip"})
	defer os.remove(archive_path)


	loaded_local := local_editor_archive(archive_path)
	if !loaded_local {
		fmt.printf("[PlaytestSmoke] %s: no local editor checkout present\n", label)
		return false
	}


	if !packages.Load_Internal_Modules_From_Blob(&environment.packages, archive_path) {
		panic("failed to load the local editor sources")
	}

	sandbox.init(&script_vm, &environment, &renderer_object)
	defer sandbox.shutdown()


	probe := "assert(game.CoreGui:FindFirstChild(\"Studio\") ~= nil, \"the editor UI did not start\")"

	ok, err := vm.RunInternal(&script_vm, probe, "playtest_editor_case")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		vm.Close(&script_vm)
		return false
	}

	fmt.printf(
		"[PlaytestSmoke] %s: mode=%s IsPlaytest=%t editorStarted=true\n",
		label,
		target.name(),
		playtest,
	)

	vm.Close(&script_vm)
	return true
}

main :: proc() {


	probe := "build/editor-playtest-probe.zip"
	have_editor := local_editor_archive(probe)
	os.remove(probe)
	if !have_editor {
		fmt.println("PLAYTEST_EDITOR_SMOKE_SKIPPED: no local kinemium-editor checkout")
		return
	}


	assert(run_case("editor", .Editor, false), "the editor did not start in an editor process")


	assert(
		run_case("playtest_client", .Client, true),
		"the editor did not start in a playtest client",
	)
	assert(
		run_case("playtest_server", .Server, true),
		"the editor did not start in a playtest server",
	)

	fmt.println("PLAYTEST_EDITOR_SMOKE_PASSED")
}
