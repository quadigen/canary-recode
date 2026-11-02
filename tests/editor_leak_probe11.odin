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

EDITOR_SOURCE_CANDIDATES :: []string {
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

snapshot :: proc(label: string, start: time.Time) {
	elapsed := time.duration_seconds(time.since(start))
	ws, priv := process_memory_mb()
	fmt.printf("[LeakProbe] %-20s mem(ws=%.1fMB priv=%.1fMB) | %.2fs\n", label, ws, priv, elapsed)
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


SNAP_CHUNK :: `
local function pathOf(inst)
	local parts = {}
	local cur = inst
	while cur ~= nil and cur ~= game do
		table.insert(parts, 1, cur.Name)
		cur = cur.Parent
	end
	return table.concat(parts, "/")
end

local snap = {}
local stack = {game}
while #stack > 0 do
	local inst = table.remove(stack)
	local p = pathOf(inst)
	snap[p] = (snap[p] or 0) + 1
	for _, k in ipairs(inst:GetChildren()) do
		table.insert(stack, k)
	end
end

local rounds = _G.__snap_rounds
if rounds == nil then
	rounds = {}
	_G.__snap_rounds = rounds
end
table.insert(rounds, snap)
local round = #rounds

local total = 0
for _, c in pairs(snap) do total += c end
print(("[Round %d] total=%d"):format(round, total))

if round > 1 then
	local prev = rounds[round - 1]

	-- Classify current instances as new if the multiset grew at that path.
	local now = {}
	for p, c in pairs(snap) do now[p] = c end
	local newInstances = {}
	local stack2 = {game}
	while #stack2 > 0 do
		local inst = table.remove(stack2)
		local p = pathOf(inst)
		local n = now[p] or 0
		if n > (prev[p] or 0) then
			now[p] = n - 1
			table.insert(newInstances, inst)
		end
		for _, k in ipairs(inst:GetChildren()) do
			table.insert(stack2, k)
		end
	end

	local byParent = {}
	for _, inst in ipairs(newInstances) do
		local parent = inst.Parent
		local pp = "<orphan>"
		if parent ~= nil then pp = pathOf(parent) end
		byParent[pp] = (byParent[pp] or 0) + 1
	end
	local arr = {}
	for pp, c in pairs(byParent) do table.insert(arr, {k = pp, c = c}) end
	table.sort(arr, function(a, b) return a.c > b.c end)
	for i, e in ipairs(arr) do
		if i > 12 then break end
		print(("[Gain r%d]   +%-3d %s"):format(round, e.c, e.k))
	end

	-- Also report paths that LOST instances (shrinkage, sanity check).
	local lost = 0
	for p, c in pairs(prev) do
		local n = snap[p] or 0
		if n < c then lost += (c - n) end
	end
	print(("[Round %d] lost=%d gained=%d"):format(round, lost, #newInstances))
end

-- Subtree sizes of the suspect containers, per round.
local coregui = game:GetService("CoreGui")
local function subtree(root)
	local n = 0
	local s = {root}
	while #s > 0 do
		local inst = table.remove(s)
		n += 1
		for _, k in ipairs(inst:GetChildren()) do
			table.insert(s, k)
		end
	end
	return n
end

local studio = coregui:FindFirstChild("Studio")
local overlay = coregui:FindFirstChild("Overlay")
if studio then
	local inspector = studio:FindFirstChild("Inspector")
	if inspector then
		local sf = inspector:FindFirstChild("Content")
		sf = sf and sf:FindFirstChild("ScrollingFrame")
		print(("[Round %d] InspectorScrollingFrame subtree=" .. subtree(sf)):format(round))
	end
	local output = studio:FindFirstChild("Output")
	if output then
		print(("[Round %d] Output subtree=" .. subtree(output)):format(round))
	end
end
if overlay then
	local bc = overlay:FindFirstChild("ViewportOverlay")
	bc = bc and bc:FindFirstChild("ViewportBreadcrumb")
	if bc then
		print(("[Round %d] ViewportBreadcrumb subtree=" .. subtree(bc)):format(round))
	end
end

_G.__gc = collectgarbage
collectgarbage()
`

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

	run(
		&script_vm,
		`
	local Selection = game:GetService("Selection")
	local candidates = {}
	for _, child in ipairs(game:GetChildren()) do
		table.insert(candidates, child)
	end
	_G.__sel_candidates = candidates
	_G.__sel_index = 1
	`,
		"probe11_boot",
	)


	for round in 0 ..< 6 {
		start := time.now()
		for _ in 0 ..< 30 {
			run(
				&script_vm,
				`
			local Selection = game:GetService("Selection")
			local list = _G.__sel_candidates
			local index = _G.__sel_index
			_G.__sel_index = (index % #list) + 1
			Selection:Set({ list[index] })
			`,
				"probe11_sel",
			)
			frames(&environment, &script_vm, surface, width, height, 1)
		}
		luauh.lua_gc(script_vm.L, 2, 0)
		run(&script_vm, SNAP_CHUNK, "probe11_snap")
		snapshot(fmt.tprintf("sel r%d", round), start)
	}

	fmt.println("EDITOR_LEAK_PROBE11_DONE")
}
