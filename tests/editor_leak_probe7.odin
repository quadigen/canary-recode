package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import windows "core:sys/windows"
import "core:time"

import kineffi "../src/engine/bindings"
import packages "../src/engine/packages"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import luauh "../src/engine/vm/luauh"
import sandbox "../src/sandboxed"

PROCESS_MEMORY_COUNTERS :: struct {
	cb:                         windows.DWORD,
	PageFaultCount:             windows.DWORD,
	PeakWorkingSetSize:         windows.SIZE_T,
	WorkingSetSize:             windows.SIZE_T,
	QuotaPeakPagedPoolUsage:    windows.SIZE_T,
	QuotaPagedPoolUsage:        windows.SIZE_T,
	QuotaPeakNonPagedPoolUsage: windows.SIZE_T,
	QuotaNonPagedPoolUsage:     windows.SIZE_T,
	PagefileUsage:              windows.SIZE_T,
	PeakPagefileUsage:          windows.SIZE_T,
}

foreign import psapi "system:Psapi.lib"

@(default_calling_convention = "system")
foreign psapi {
	GetProcessMemoryInfo :: proc(hProcess: windows.HANDLE, ppsmemCounters: ^PROCESS_MEMORY_COUNTERS, cb: windows.DWORD) -> windows.BOOL ---
}

process_memory_mb :: proc() -> (working_set_mb: f64, private_mb: f64) {
	counters: PROCESS_MEMORY_COUNTERS
	counters.cb = u32(size_of(PROCESS_MEMORY_COUNTERS))
	if GetProcessMemoryInfo(windows.GetCurrentProcess(), &counters, counters.cb) == false {
		return 0, 0
	}
	return f64(counters.WorkingSetSize) / (1024.0 * 1024.0),
		f64(counters.PagefileUsage) / (1024.0 * 1024.0)
}

LEAK_PROBE_MODE :: "LEAK_PROBE_MODE"

EDITOR_SOURCE_CANDIDATES :: []string {
	"C:/Users/devco/Documents/kinemium-editor/internal",
	"../kinemium-editor/internal",
	"../../kinemium-editor/internal",
}


pack_mode :: proc(archive_path: string) -> bool {
	mode_buf: [64]u8
	mode := os.get_env(mode_buf[:], LEAK_PROBE_MODE)
	if mode == "" {
		mode = "full"
	}

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

	walker := os.walker_create(source_dir)
	defer os.walker_destroy(&walker)

	archive, created := kineffi.Zip_Create(archive_path)
	if !created {
		return false
	}

	added := 0
	for entry in os.walker_walk(&walker) {
		if entry.type != .Regular || !strings.has_suffix(entry.name, ".luau") {
			continue
		}

		relative, rel_err := filepath.rel(source_dir, entry.fullpath, context.allocator)
		if rel_err != nil {
			continue
		}

		zip_relative, replaced := strings.replace_all(relative, "\\", "/", context.allocator)
		if !replaced {
			zip_relative = strings.clone(relative, context.allocator)
		}
		delete(relative, context.allocator)

		is_component := strings.has_prefix(zip_relative, "Components/")
		switch mode {
		case "none":
			if zip_relative != "editor_ui.luau" && !is_component {
				delete(zip_relative, context.allocator)
				continue
			}
		case "noexpl":
			if !is_component && (entry.name == "explorer.luau" || entry.name == "viewport.luau") {
				delete(zip_relative, context.allocator)
				continue
			}
		case "noinsp":
			if !is_component && entry.name == "inspector.luau" {
				delete(zip_relative, context.allocator)
				continue
			}
		}

		data, read_err := os.read_entire_file(entry.fullpath, context.allocator)
		if read_err != nil {
			delete(zip_relative, context.allocator)
			continue
		}

		module_path := strings.concatenate({"internal/", zip_relative}, context.allocator)
		stored := kineffi.Zip_Add_String(archive, module_path, string(data))
		delete(module_path, context.allocator)
		delete(zip_relative, context.allocator)
		delete(data, context.allocator)

		if !stored {
			_ = kineffi.Zip_Close(archive)
			return false
		}
		added += 1
	}

	if !kineffi.Zip_Close(archive) {
		return false
	}
	if added == 0 {
		return false
	}

	fmt.printf("[LeakProbe] mode=%s packed %d editor modules from %s\n", mode, added, source_dir)
	return true
}

snapshot :: proc(label: string, start: time.Time) {
	elapsed := time.duration_seconds(time.since(start))
	ws, priv := process_memory_mb()
	fmt.printf("[LeakProbe] %-24s mem(ws=%.1fMB priv=%.1fMB) | %.2fs\n", label, ws, priv, elapsed)
}

run :: proc(v: ^vm.VM, source: string, chunk: string) {
	ok, err := vm.RunInternal(v, source, chunk)
	if !ok {
		fmt.eprintln(chunk, "->", err)
	}
}

frames :: proc(
	environment: ^engine_runtime.Environment,
	v: ^vm.VM,
	s: ^kineffi.KineSkiaSurface,
	w, h: i32,
	n: int,
) {
	for _ in 0 ..< n {
		engine_runtime.Environment_Update_Step(environment, v, 1.0 / 60.0)
		engine_runtime.Environment_Render_2D(environment, v, s, w, h, 1.0 / 60.0)
		engine_runtime.Environment_Render_Overlay(environment, v, s, w, h, 1.0 / 60.0)
	}
}

SEL_BOOT :: `
local Selection = game:GetService("Selection")
local candidates = {}
for _, child in ipairs(game:GetChildren()) do
	table.insert(candidates, child)
end
_G.__sel_candidates = candidates
_G.__sel_index = 1
`

SEL_STEP :: `
local Selection = game:GetService("Selection")
local list = _G.__sel_candidates
local index = _G.__sel_index
_G.__sel_index = (index % #list) + 1
Selection:Set({ list[index] })
`

PRINT_STEP :: `print("probe7 log line")`

main :: proc() {
	mode_buf: [64]u8
	mode := os.get_env(mode_buf[:], LEAK_PROBE_MODE)
	if mode == "" {
		mode = "full"
	}

	script_vm := vm.New()
	environment: engine_runtime.Environment
	renderer_object: renderer.RendererObject

	defer sandbox.shutdown()
	defer vm.Close(&script_vm)

	archive_path := "build/editor-local-sources.zip"
	if !pack_mode(archive_path) {
		panic("no local editor checkout found")
	}
	defer os.remove(archive_path)

	sandbox.init_runtime(&script_vm, &environment, &renderer_object)
	if !packages.Load_Internal_Modules_From_Blob(&environment.packages, archive_path) {
		panic("failed to load the local editor sources")
	}
	sandbox.run_modules(environment.packages.internal_modules[:])

	width: i32 = 1280
	height: i32 = 800
	surface := kineffi.Kine_Skia_Surface_Create(width, height)
	assert(surface != nil)
	defer kineffi.Kine_Skia_Surface_Destroy(surface)
	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 255)

	frames(&environment, &script_vm, surface, width, height, 20)
	snapshot("warmup", time.now())

	run(&script_vm, SEL_BOOT, "probe7_boot")


	for round in 0 ..< 3 {
		start := time.now()
		for _ in 0 ..< 30 {
			run(&script_vm, SEL_STEP, "probe7_sel")
			frames(&environment, &script_vm, surface, width, height, 1)
		}
		luauh.lua_gc(script_vm.L, 2, 0)
		snapshot(fmt.tprintf("sel r%d", round), start)
	}


	for round in 0 ..< 3 {
		start := time.now()
		for _ in 0 ..< 30 {
			run(&script_vm, PRINT_STEP, "probe7_print")
			frames(&environment, &script_vm, surface, width, height, 1)
		}
		luauh.lua_gc(script_vm.L, 2, 0)
		snapshot(fmt.tprintf("print r%d", round), start)
	}

	fmt.println("EDITOR_LEAK_PROBE7_DONE")
}
