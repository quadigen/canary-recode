package main

import "core:fmt"
import "core:os"
import "core:mem"
import "base:runtime"
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

	fmt.printf("[LeakProbe] packed %d editor modules from %s\n", added, source_dir)
	return true
}

// ---- Tracking allocator -----------------------------------------------------

track: mem.Tracking_Allocator

bad_free_ignore :: proc(t: ^mem.Tracking_Allocator, memory: rawptr, location: runtime.Source_Code_Location) {
	// The engine allocates inside Luau C callbacks under the default allocator
	// and frees under the main context; those show up as bad frees here. They
	// are not leaks, so ignore them instead of panicking.
	_ = t
	_ = memory
	_ = location
}

tracking_live_mb :: proc() -> f64 {
	return f64(track.current_memory_allocated) / (1024.0 * 1024.0)
}

Tracking_Site :: struct {
	live_bytes: i64,
	live_count: i64,
}

tracking_report_top :: proc(label: string, top_n: int) {
	sites := map[string]Tracking_Site{}
	for _, entry in track.allocation_map {
		key := fmt.tprintf("%s:%d %s", entry.location.file_path, entry.location.line, entry.location.procedure)
		site := sites[key]
		site.live_bytes += i64(entry.size)
		site.live_count += 1
		sites[key] = site
	}

	keys := make([dynamic]string, 0, len(sites))
	defer delete(keys)
	for key, _ in sites {
		append(&keys, key)
	}
	for i := 1; i < len(keys); i += 1 {
		current := keys[i]
		j := i - 1
		for j >= 0 && sites[keys[j]].live_bytes < sites[current].live_bytes {
			keys[j+1] = keys[j]
			j -= 1
		}
		keys[j+1] = current
	}

	fmt.printf(
		"[LeakSites] %s (%d live allocs, %.1fMB tracked):\n",
		label,
		len(track.allocation_map),
		tracking_live_mb(),
	)
	for key, i in keys {
		if i >= top_n {
			break
		}
		site := sites[key]
		fmt.printf("[LeakSites]   %9.1fKB %7dx  %s\n", f64(site.live_bytes)/1024.0, site.live_count, key)
	}
}

// ---- Probe ------------------------------------------------------------------

snapshot :: proc(label: string, start: time.Time) {
	elapsed := time.duration_seconds(time.since(start))
	ws, priv := process_memory_mb()
	fmt.printf(
		"[LeakProbe] %-24s mem(ws=%.1fMB priv=%.1fMB tracked=%.1fMB) | %.2fs\n",
		label,
		ws,
		priv,
		tracking_live_mb(),
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

main :: proc() {
	// Install the tracking allocator over the whole process so every Odin-side
	// allocation is attributed to its call site.
	track_backing := context.allocator
	mem.tracking_allocator_init(&track, track_backing)
	context.allocator = mem.tracking_allocator(&track)
	track.bad_free_callback = bad_free_ignore

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

	// Baseline site report, so one-time boot costs don't masquerade as leaks.
	tracking_report_top("baseline", 12)

	run(&script_vm, `
	local UI = require("@internal/editor_ui")
	_G.__UI = UI
	_G.__churn_root = UI.create("ScreenGui", { Name = "ChurnRoot", DisplayOrder = 5000 }, game.CoreGui)
	`, "probe6_setup")

	// Phase T: tooltip churn (known +43.5MB/round from probe5). The tracker
	// should name exactly which call sites retain the bytes.
	for round in 0 ..< 3 {
		start := time.now()
		run(&script_vm, `
		local UI = _G.__UI
		local root = _G.__churn_root
		for i = 1, 200 do
			local target = UI.frame(root, UDim2.fromOffset(0, 0), UDim2.fromOffset(60, 20), UI.tokens.color.panel, 2)
			UI.tooltip(target, "tip " .. i, {})
		end
		UI.clear(root)
		`, "probe6_tooltip")
		frames(&environment, &script_vm, surface, width, height, 2)
		luauh.lua_gc(script_vm.L, 2, 0)
		snapshot(fmt.tprintf("T tooltip r%d", round), start)
	}
	tracking_report_top("after tooltip churn", 15)

	// Phase S: selection churn through the real editor reaction path (probe3
	// showed ~135MB/round). Same attribution, cross-check.
	run(&script_vm, `
	local Selection = game:GetService("Selection")
	local candidates = {}
	for _, child in ipairs(game:GetChildren()) do
		table.insert(candidates, child)
	end
	_G.__sel_candidates = candidates
	_G.__sel_index = 1
	`, "probe6_boot")

	for round in 0 ..< 3 {
		start := time.now()
		for _ in 0 ..< 30 {
			run(&script_vm, `
			local Selection = game:GetService("Selection")
			local list = _G.__sel_candidates
			local index = _G.__sel_index
			_G.__sel_index = (index % #list) + 1
			Selection:Set({ list[index] })
			`, "probe6_sel")
			frames(&environment, &script_vm, surface, width, height, 1)
		}
		luauh.lua_gc(script_vm.L, 2, 0)
		snapshot(fmt.tprintf("S selection r%d", round), start)
	}
	tracking_report_top("after selection churn", 15)

	fmt.println("EDITOR_LEAK_PROBE6_DONE")
}
