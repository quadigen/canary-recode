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
import target "../src/engine/target"
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

	fmt.printf("[PlaytestSmoke] packed %d editor modules from %s\n", added, source_dir)
	return true
}

// run_case builds one environment in the given mode and reports whether the
// editor UI actually started. The editor is expected to build its Studio frame
// in editor and playtest processes, and never in a plain client or server.
run_case :: proc(
	label: string,
	mode: target.Mode,
	playtest: bool,
) -> bool {
	target.set_mode(mode)
	target.set_playtest(playtest)

	script_vm := vm.New()
	environment: engine_runtime.Environment
	renderer_object: renderer.RendererObject

	// IsPlaytest is published before the runtime initializes, exactly as
	// main.odin does, so the editor sees a real boolean while it loads rather
	// than a nil global.
	vm.AddGlobal_Boolean(&script_vm, "IsPlaytest", playtest)

	archive_path := strings.concatenate({"build/editor-playtest-", label, ".zip"})
	defer os.remove(archive_path)

	// The editor archive is packed before the runtime initializes so a missing
	// checkout is reported without paying for an environment.
	loaded_local := local_editor_archive(archive_path)
	if !loaded_local {
		fmt.printf("[PlaytestSmoke] %s: no local editor checkout present\n", label)
		return false
	}

	// The archive is pre-loaded so sandbox.init finds the local sources instead of
	// downloading, and the editor runs through the same entry point the engine
	// uses. Driving the modules by hand here would miss a routing bug in init.
	if !packages.Load_Internal_Modules_From_Blob(&environment.packages, archive_path) {
		panic("failed to load the local editor sources")
	}

	sandbox.init(&script_vm, &environment, &renderer_object)
	defer sandbox.shutdown()

	// The editor probe asserts rather than returning a value, so the result is
	// reported through the run's success instead of a global read-back.
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
	// A local editor checkout is what makes the editor assertions meaningful, so
	// the run reports a clear skip rather than a misleading pass without one.
	probe := "build/editor-playtest-probe.zip"
	have_editor := local_editor_archive(probe)
	os.remove(probe)
	if !have_editor {
		fmt.println("PLAYTEST_EDITOR_SMOKE_SKIPPED: no local kinemium-editor checkout")
		return
	}

	// The editor runs in an ordinary editor process, as it always has.
	assert(
		run_case("editor", .Editor, false),
		"the editor did not start in an editor process",
	)

	// The playtest client and server both host the editor, which is the new
	// behaviour: a playtest is an authoring session, not a shipping build.
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
