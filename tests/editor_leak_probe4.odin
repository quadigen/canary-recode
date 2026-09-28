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

snapshot :: proc(label: string, start: time.Time) {
	elapsed := time.duration_seconds(time.since(start))
	ws, priv := process_memory_mb()
	fmt.printf(
		"[LeakProbe] %-28s mem(ws=%.1fMB priv=%.1fMB) | %.2fs\n",
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

	frames(&environment, &script_vm, surface, width, height, 20)
	snapshot("warmup", time.now())

	kind_names := []string{"TextLabel", "Frame", "TextButton"}

	// Dedicated churn ScreenGui so phases don't fight the editor's own rebuilds.
	run(&script_vm, `
_G.__churn_root = UI.create("ScreenGui", { Name = "ChurnRoot", DisplayOrder = 5000 }, game.CoreGui)
`, "probe4_setup")

	// ---- Phase A: raw bulk create/destroy of one GUI class per round (2500/round).
	for round in 0 ..< 9 {
		start := time.now()
		kind := kind_names[round % 3]

		source := fmt.tprintf(`
local root = _G.__churn_root
local kind = "%s"
local made = {}
for i = 1, 2500 do
	local inst = Instance.new(kind)
	if kind ~= "Frame" then
		inst.Text = "churn " .. i
	end
	inst.Parent = root
	table.insert(made, inst)
end
for _, inst in ipairs(made) do
	inst:Destroy()
end
`, kind)

		run(&script_vm, source, "probe4_churn")
		frames(&environment, &script_vm, surface, width, height, 3)
		luauh.lua_gc(script_vm.L, 2, 0)
		snapshot(fmt.tprintf("A r%d %s", round, kind), start)
	}

	// ---- Phase B: empty-selection churn through the full editor reaction path.
	for round in 0 ..< 5 {
		start := time.now()
		for _ in 0 ..< 30 {
			run(&script_vm, `
local Selection = game:GetService("Selection")
Selection:Set({})
`, "probe4_sel_empty")
			frames(&environment, &script_vm, surface, width, height, 1)
		}
		luauh.lua_gc(script_vm.L, 2, 0)
		snapshot(fmt.tprintf("B r%d empty-select", round), start)
	}

	// ---- Phase C: same churn but parented to the editor's real Studio ScreenGui.
	run(&script_vm, `
_G.__studio_parent = UI.root()
`, "probe4_studio")

	for round in 0 ..< 9 {
		start := time.now()
		kind := kind_names[round % 3]

		source := fmt.tprintf(`
local parent = _G.__studio_parent
local kind = "%s"
local made = {}
for i = 1, 2500 do
	local inst = Instance.new(kind)
	if kind ~= "Frame" then
		inst.Text = "churn " .. i
	end
	inst.Parent = parent
	table.insert(made, inst)
end
for _, inst in ipairs(made) do
	inst:Destroy()
end
`, kind)

		run(&script_vm, source, "probe4_studio_churn")
		frames(&environment, &script_vm, surface, width, height, 3)
		luauh.lua_gc(script_vm.L, 2, 0)
		snapshot(fmt.tprintf("C r%d studio %s", round, kind), start)
	}

	fmt.println("EDITOR_LEAK_PROBE4_DONE")
}
