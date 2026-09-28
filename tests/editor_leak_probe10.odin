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

	run(&script_vm, `
	local Selection = game:GetService("Selection")
	local candidates = {}
	for _, child in ipairs(game:GetChildren()) do
		table.insert(candidates, child)
	end
	_G.__sel_candidates = candidates
	_G.__sel_index = 1
	`, "probe10_boot")

	// Baseline: multiset of full instance paths (name chain from game).
	run(&script_vm, `
	local function pathOf(inst)
		local parts = {}
		local cur = inst
		while cur ~= nil and cur ~= game do
			table.insert(parts, 1, cur.Name)
			cur = cur.Parent
		end
		return table.concat(parts, "/")
	end

	local base = {}
	local classCounts = {}
	local stack = {game}
	while #stack > 0 do
		local inst = table.remove(stack)
		local p = pathOf(inst)
		base[p] = (base[p] or 0) + 1
		classCounts[inst.ClassName] = (classCounts[inst.ClassName] or 0) + 1
		for _, k in ipairs(inst:GetChildren()) do
			table.insert(stack, k)
		end
	end
	_G.__base_paths = base
	_G.__base_classes = classCounts
	local total = 0
	for _, c in pairs(classCounts) do total += c end
	print("[Baseline] total=" .. total)
	`, "probe10_baseline")

	for round in 0 ..< 5 {
		start := time.now()
		for _ in 0 ..< 30 {
			run(&script_vm, `
			local Selection = game:GetService("Selection")
			local list = _G.__sel_candidates
			local index = _G.__sel_index
			_G.__sel_index = (index % #list) + 1
			Selection:Set({ list[index] })
			`, "probe10_sel")
			frames(&environment, &script_vm, surface, width, height, 1)
		}
		luauh.lua_gc(script_vm.L, 2, 0)
		snapshot(fmt.tprintf("sel r%d", round), start)
	}

	// Diff: classify every current instance as base or extra by path multiset,
	// then histogram the parents of the extras.
	run(&script_vm, `
	local function pathOf(inst)
		local parts = {}
		local cur = inst
		while cur ~= nil and cur ~= game do
			table.insert(parts, 1, cur.Name)
			cur = cur.Parent
		end
		return table.concat(parts, "/")
	end

	local base = _G.__base_paths or {}

	-- current per-path counts
	local now = {}
	local stack = {game}
	while #stack > 0 do
		local inst = table.remove(stack)
		local p = pathOf(inst)
		now[p] = (now[p] or 0) + 1
		for _, k in ipairs(inst:GetChildren()) do
			table.insert(stack, k)
		end
	end

	-- second walk: classify each instance; consume one "now" credit per extra
	local newInstances = {}
	local stack2 = {game}
	while #stack2 > 0 do
		local inst = table.remove(stack2)
		local p = pathOf(inst)
		local b = base[p] or 0
		local n = now[p] or 0
		if n > b then
			now[p] = n - 1
			table.insert(newInstances, {inst = inst, path = p})
		end
		for _, k in ipairs(inst:GetChildren()) do
			table.insert(stack2, k)
		end
	end

	print("[NewInstances] total=" .. #newInstances)

	-- by class
	local byClass = {}
	for _, e in ipairs(newInstances) do
		byClass[e.inst.ClassName] = (byClass[e.inst.ClassName] or 0) + 1
	end
	local arr = {}
	for class, c in pairs(byClass) do table.insert(arr, {k = class, c = c}) end
	table.sort(arr, function(a, b) return a.c > b.c end)
	for _, e in ipairs(arr) do
		print(("[ByClass]   +%-4d %s"):format(e.c, e.k))
	end

	-- by parent path
	local byParent = {}
	for _, e in ipairs(newInstances) do
		local parent = e.inst.Parent
		local pp = "<destroyed-parent>"
		if parent ~= nil then pp = pathOf(parent) end
		byParent[pp] = (byParent[pp] or 0) + 1
	end
	arr = {}
	for pp, c in pairs(byParent) do table.insert(arr, {k = pp, c = c}) end
	table.sort(arr, function(a, b) return a.c > b.c end)
	for i, e in ipairs(arr) do
		if i > 25 then break end
		print(("[ByParent]  +%-4d %s"):format(e.c, e.k))
	end

	-- sample of extras
	for i, e in ipairs(newInstances) do
		if i > 40 then break end
		local inst = e.inst
		local parent = inst.Parent
		local pp = "<nil>"
		if parent ~= nil then pp = pathOf(parent) end
		print(("[NewInst]    %-12s %-26s parent=%s"):format(inst.ClassName, inst.Name, pp))
	end

	-- per top-level CoreGui child: subtree delta vs baseline count
	print("[CoreGui] ---")
	for _, child in ipairs(game:GetService("CoreGui"):GetChildren()) do
		local n = 0
		local stack3 = {child}
		while #stack3 > 0 do
			local inst = table.remove(stack3)
			n += 1
			for _, k in ipairs(inst:GetChildren()) do
				table.insert(stack3, k)
			end
		end
		print(("[CoreGui]   %-28s subtree=%d"):format(child.Name, n))
	end
	`, "probe10_diff")

	fmt.println("EDITOR_LEAK_PROBE10_DONE")
}
