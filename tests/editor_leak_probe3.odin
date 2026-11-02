package main

import "core:fmt"
import "core:os"
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

	fmt.printf("[LeakProbe] packed %d editor modules from %s\n", added, source_dir)
	return true
}

snapshot :: proc(label: string, start: time.Time, frames: int) {
	elapsed := time.duration_seconds(time.since(start))
	per := 0.0
	if frames > 0 {
		per = elapsed * 1000.0 / f64(frames)
	}
	ws, priv := process_memory_mb()
	fmt.printf(
		"[LeakProbe] %-18s mem(ws=%.1fMB priv=%.1fMB) | %d frames in %.2fs (%.1f ms/frame)\n",
		label,
		ws,
		priv,
		frames,
		elapsed,
		per,
	)
}

main :: proc() {
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

	frame :: proc(
		env: ^engine_runtime.Environment,
		v: ^vm.VM,
		s: ^kineffi.KineSkiaSurface,
		w, h: i32,
	) {
		engine_runtime.Environment_Update_Step(env, v, 1.0 / 60.0)
		engine_runtime.Environment_Render_2D(env, v, s, w, h, 1.0 / 60.0)
		engine_runtime.Environment_Render_Overlay(env, v, s, w, h, 1.0 / 60.0)
	}

	for _ in 0 ..< 20 {
		frame(&environment, &script_vm, surface, width, height)
	}
	snapshot("warmup", time.now(), 0)

	boot_ok, boot_err := vm.RunInternal(
		&script_vm,
		`
local Selection = game:GetService("Selection")
local candidates = {}
for _, child in ipairs(game:GetChildren()) do
	table.insert(candidates, child)
end
_G.__leak_probe_candidates = candidates
_G.__leak_probe_index = 1
`,
		"leak_probe_boot",
	)
	if !boot_ok {
		fmt.eprintln(boot_err)
		panic("leak probe boot failed")
	}


	for round in 0 ..< 5 {
		start := time.now()

		for _ in 0 ..< 30 {
			ok, err := vm.RunInternal(
				&script_vm,
				`
local Selection = game:GetService("Selection")
local list = _G.__leak_probe_candidates
local index = _G.__leak_probe_index
_G.__leak_probe_index = (index % #list) + 1
Selection:Set({ list[index] })
`,
				"leak_probe_sel",
			)
			if !ok {
				fmt.eprintln(err)
			}
			frame(&environment, &script_vm, surface, width, height)
		}

		luauh.lua_gc(script_vm.L, 2, 0)
		label := fmt.tprintf("selchurn r%d", round)
		snapshot(label, start, 30)
	}

	fmt.println("EDITOR_LEAK_PROBE_DONE")
}
