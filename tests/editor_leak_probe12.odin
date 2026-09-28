package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import windows "core:sys/windows"

import kineffi "../src/engine/bindings"
import packages "../src/engine/packages"
import engine_runtime "../src/engine/runtime"
import renderer "../src/engine/renderer"
import sandbox "../src/sandboxed"
import vm "../src/engine/vm"
import luauh "../src/engine/vm/luauh"

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
	GetProcessMemoryInfo :: proc(
		hProcess: windows.HANDLE,
		ppsmemCounters: ^PROCESS_MEMORY_COUNTERS,
		cb: windows.DWORD,
	) -> windows.BOOL ---
}

process_memory_mb :: proc() -> (working_set_mb: f64, private_mb: f64) {
	counters: PROCESS_MEMORY_COUNTERS
	counters.cb = u32(size_of(PROCESS_MEMORY_COUNTERS))
	if GetProcessMemoryInfo(windows.GetCurrentProcess(), &counters, counters.cb) == false {
		return 0, 0
	}
	return f64(counters.WorkingSetSize) / (1024.0 * 1024.0), f64(counters.PagefileUsage) / (1024.0 * 1024.0)
}

EDITOR_SOURCE_CANDIDATES :: []string{
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

	fmt.printf("[LeakProbe] packed %d editor modules from %s\n", added, source_dir)
	return true
}

snapshot :: proc(label: string, start: time.Time) {
	elapsed := time.duration_seconds(time.since(start))
	ws, priv := process_memory_mb()
	fmt.printf(
		"[LeakProbe] %-20s mem(ws=%.1fMB priv=%.1fMB) | %.2fs\n",
		label,
		ws,
		priv,
		elapsed,
	)
}

run :: proc(v: ^vm.VM, source: string, chunk: string) {
	ok, err := vm.RunInternal(v, source, chunk)
	if !ok {
		fmt.eprintln(chunk, "->", err)
	}
}

frames :: proc(environment: ^engine_runtime.Environment, v: ^vm.VM, s: ^kineffi.KineSkiaSurface, w, h: i32, n: int) {
	for _ in 0 ..< n {
		engine_runtime.Environment_Update_Step(environment, v, 1.0 / 60.0)
		engine_runtime.Environment_Render_2D(environment, v, s, w, h, 1.0 / 60.0)
		engine_runtime.Environment_Render_Overlay(environment, v, s, w, h, 1.0 / 60.0)
	}
}

luau_heap_mb :: proc(L: ^vm.VM) -> f64 {
	kb := f64(luauh.lua_gc(L.L, 3, 0))
	rem := f64(luauh.lua_gc(L.L, 4, 0))
	return (kb * 1024.0 + rem) / (1024.0 * 1024.0)
}

RENDER_MODE :: "RENDER_MODE"

main :: proc() {
	mode_buf: [32]u8
	mode := os.get_env(mode_buf[:], RENDER_MODE)
	if mode == "" {
		mode = "both"
	}

	script_vm := vm.New()
	environment: engine_runtime.Environment
	renderer_object: renderer.RendererObject

	defer sandbox.shutdown()
	defer vm.Close(&script_vm)

	archive_path := "build/editor-local-sources.zip"
	if !local_editor_archive(archive_path) {
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

	run(&script_vm, `
	local Selection = game:GetService("Selection")
	local candidates = {}
	for _, child in ipairs(game:GetChildren()) do
		table.insert(candidates, child)
	end
	_G.__sel_candidates = candidates
	_G.__sel_index = 1
	`, "probe12_boot")

	// Populate the panels once, then measure growth WITHOUT further selection
	// changes: the instance tree is static from here on.
	run(&script_vm, `
	local Selection = game:GetService("Selection")
	Selection:Set({ _G.__sel_candidates[2] })
	`, "probe12_populate")
	frames(&environment, &script_vm, surface, width, height, 5)

	fmt.printf("[Mode] %s\n", mode)

	// Phase A: 4 selection rounds (tree static after first selection).
	for round in 0 ..< 4 {
		start := time.now()
		for _ in 0 ..< 30 {
			run(&script_vm, `
			local Selection = game:GetService("Selection")
			local list = _G.__sel_candidates
			local index = _G.__sel_index
			_G.__sel_index = (index % #list) + 1
			Selection:Set({ list[index] })
			`, "probe12_sel")
			frames(&environment, &script_vm, surface, width, height, 1)
		}
		luauh.lua_gc(script_vm.L, 2, 0)
		fmt.printf(
			"[Sel r%d] luau_heap=%.2fMB mem(ws=%.1f priv=%.1f)\n",
			round,
			luau_heap_mb(&script_vm),
			process_memory_mb(),
		)
	}

	// Phase B: churn WITHOUT selection (LogService signature may still churn if
	// history grows; PrintService logging ticks). No Set calls at all.
	start := time.now()
	for _ in 0 ..< 120 {
		frames(&environment, &script_vm, surface, width, height, 1)
	}
	luauh.lua_gc(script_vm.L, 2, 0)
	fmt.printf(
		"[Idle 120f] luau_heap=%.2fMB mem(ws=%.1f priv=%.1f) dt=%.2fs\n",
		luau_heap_mb(&script_vm),
		process_memory_mb(),
		time.duration_seconds(time.since(start)),
	)

	// Phase C: render ablation — 120 frames with only one render path active.
	for _ in 0 ..< 120 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
		if mode == "2d" || mode == "both" {
			engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, width, height, 1.0 / 60.0)
		}
		if mode == "overlay" || mode == "both" {
			engine_runtime.Environment_Render_Overlay(&environment, &script_vm, surface, width, height, 1.0 / 60.0)
		}
	}
	luauh.lua_gc(script_vm.L, 2, 0)
	fmt.printf(
		"[Phase %s 120f] luau_heap=%.2fMB mem(ws=%.1f priv=%.1f)\n",
		mode,
		luau_heap_mb(&script_vm),
		process_memory_mb(),
	)

	// Phase D: run the phase C block again for the other modes with a fresh
	// read after 240 frames each, so all modes run in one process for timing.
	_ = mode
	fmt.println("EDITOR_LEAK_PROBE12_DONE")
}
