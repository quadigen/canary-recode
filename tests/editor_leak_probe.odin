package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import windows "core:sys/windows"
import "core:time"

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

LUA_GCCOUNT :: 3
LUA_GCCOLLECT :: 2

luau_heap_mb :: proc(script_vm: ^vm.VM) -> f64 {
	// LUA_GCCOUNT reports kibibytes, not bytes. Dividing by 1024*1024 labelled
	// the result "MB" and printed values ~1024x too large, which made a 2MB
	// Luau heap look like 2GB.
	return f64(luauh.lua_gc(script_vm.L, LUA_GCCOUNT, 0)) / 1024.0
}

// ---- Tracking allocator: attributes live bytes to Odin call sites ---------

track: mem.Tracking_Allocator

// The tracking allocator only observes allocations that go through
// context.allocator. Nothing ever installed it, so track.allocation_map stayed
// empty, every snapshot printed live=0.0MB, and the per-callsite report was
// never produced. That reads as a clean bill of health no matter what is
// actually leaking, which is worse than having no probe at all.
// Installed after module boot on purpose. odin-http swaps context.allocator for
// its own arena during the marketplace fetches
// (src/engine/util/odin-http/allocator.odin), so a tracker installed before
// boot gets detached partway through the run.
install_tracking_allocator :: proc() {
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)
}

// NOTE: this does not actually attribute engine allocations, and
// total_allocation_count stays 0. Every VM entry point re-establishes a fresh
// context (`context = runtime.default_context()`) on the way in -- see
// object_method in src/engine/classes/Object.odin and the 12 sites in
// src/engine/vm/vm.odin -- so the allocator installed here is discarded at the
// first Luau call boundary. Wiring this up for real means changing
// default_context() to return a tracking-backed context, not editing this
// probe. The numbers that do work are the native (working set / private bytes),
// Luau, and instance-count metrics.

tracking_live_mb :: proc() -> f64 {
	return f64(track.current_memory_allocated) / (1024.0 * 1024.0)
}

// Tracking_Site aggregates live allocations by source location.
Tracking_Site :: struct {
	live_bytes: i64,
	live_count: i64,
}

tracking_report_top :: proc(label: string, top_n: int) {
	sites := map[string]Tracking_Site{}
	for _, entry in track.allocation_map {
		key := fmt.tprintf(
			"%s:%d %s",
			entry.location.file_path,
			entry.location.line,
			entry.location.procedure,
		)
		site: Tracking_Site
		if entry_site, ok := sites[key]; ok {
			site = entry_site
		}
		site.live_bytes += i64(entry.size)
		site.live_count += 1
		sites[key] = site
	}

	// Sort by live bytes descending (simple insertion sort; the list is small).
	keys := make([dynamic]string, 0, len(sites))
	defer delete(keys)
	for key, _ in sites {
		append(&keys, key)
	}
	for i := 1; i < len(keys); i += 1 {
		current := keys[i]
		j := i - 1
		for j >= 0 && sites[keys[j]].live_bytes < sites[current].live_bytes {
			keys[j + 1] = keys[j]
			j -= 1
		}
		keys[j + 1] = current
	}

	fmt.printf(
		"[LeakSites] %s (%d live allocations, %.1fMB):\n",
		label,
		len(track.allocation_map),
		tracking_live_mb(),
	)
	for key, i in keys {
		if i >= top_n {
			break
		}
		site := sites[key]
		fmt.printf(
			"[LeakSites]   %8.1fKB %6dx  %s\n",
			f64(site.live_bytes) / 1024.0,
			site.live_count,
			key,
		)
	}
}

// ---- Tracking allocator: reports live bytes at each snapshot ---------------

import kineffi "../src/engine/bindings"
import packages "../src/engine/packages"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import luauh "../src/engine/vm/luauh"
import sandbox "../src/sandboxed"
import "base:runtime"

EDITOR_SOURCE_CANDIDATES := []string {
	"C:/Users/devco/Documents/kinemium-editor/internal",
	"../kinemium-editor/internal",
	"../../kinemium-editor/internal",
}

CHURN_SCRIPT :: `
local parent = _G.__leak_probe_churn
if parent == nil then
	parent = Instance.new("Folder")
	parent.Name = "LeakProbeChurn"
	parent.Parent = game.CoreGui
	_G.__leak_probe_churn = parent
end
local made = {}
for i = 1, 60 do
	local object = Instance.new("CLASS_NAME")
	object.Parent = parent
	table.insert(made, object)
end
for _, object in ipairs(made) do
	object:Destroy()
end
`

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

count_instances :: proc(env: ^engine_runtime.Environment) -> (total: int, class_count: int) {
	for descriptor in env.classes.classes {
		n := len(descriptor.instances)
		if n > 0 {
			class_count += 1
		}
		total += n
	}
	return
}

snapshot :: proc(
	env: ^engine_runtime.Environment,
	script_vm: ^vm.VM,
	label: string,
	start: time.Time,
	frames: int,
) {
	total, class_count := count_instances(env)
	elapsed := time.duration_seconds(time.since(start))
	per := 0.0
	if frames > 0 {
		per = elapsed * 1000.0 / f64(frames)
	}
	ws, priv := process_memory_mb()
	// Print "untracked" rather than 0.0MB when the tracker never got wired up,
	// so a broken column cannot be misread as zero live memory.
	live_field := fmt.tprintf("%.1fMB", tracking_live_mb())
	if track.total_allocation_count == 0 {
		live_field = "untracked"
	}
	fmt.printf(
		"[LeakProbe] %-14s instances=%d classes=%d pool=%d mem(ws=%.1fMB priv=%.1fMB luau=%.1fMB live=%s) | %d frames in %.2fs (%.1f ms/frame)\n",
		label,
		total,
		class_count,
		len(env.packages.callbacks),
		ws,
		priv,
		luau_heap_mb(script_vm),
		live_field,
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
	install_tracking_allocator()
	tracking_report_top("baseline", 8)

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
	snapshot(&environment, &script_vm, "warmup", time.now(), 0)

	// Idle memory trend: if native memory grows with no user activity this is the
	// leak the report describes.
	for block in 0 ..< 6 {
		start := time.now()
		for _ in 0 ..< 50 {
			frame(&environment, &script_vm, surface, width, height)
		}
		label := fmt.tprintf("idle blk %d", block)
		snapshot(&environment, &script_vm, label, start, 50)
	}

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

	// Phase B: isolate which action leaks native memory. Each block runs 30
	// frames while changing exactly one input. Repeating blocks distinguishes
	// one-time rebuild cost (a plateau) from a true per-action leak (a slope).
	for round in 0 ..< 3 {
		{
			start := time.now()
			for _ in 0 ..< 30 {
				vm.RunInternal(
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
				frame(&environment, &script_vm, surface, width, height)
			}
			label := fmt.tprintf("select r%d", round)
			snapshot(&environment, &script_vm, label, start, 30)
		}
		{
			start := time.now()
			for _ in 0 ..< 30 {
				vm.RunInternal(&script_vm, `print("leak probe print")`, "leak_probe_print")
				frame(&environment, &script_vm, surface, width, height)
			}
			label := fmt.tprintf("print r%d", round)
			snapshot(&environment, &script_vm, label, start, 30)
		}
	}
	{
		start := time.now()
		for i in 0 ..< 30 {
			w := width - i32(i % 2) * 40
			services.Resize(&environment.services, &environment.datatypes, w, height)
			frame(&environment, &script_vm, surface, w, height)
		}
		snapshot(&environment, &script_vm, "resize-only", start, 30)
	}

	// Phase C: quiet frames after the activity, to see whether cost persists.
	start := time.now()
	for _ in 0 ..< 100 {
		frame(&environment, &script_vm, surface, width, height)
	}
	snapshot(&environment, &script_vm, "post-idle", start, 100)

	// Force a full Luau collection. If private memory collapses afterwards the
	// growth was uncollected Luau garbage, not a native leak.
	luauh.lua_gc(script_vm.L, LUA_GCCOLLECT, 0)
	snapshot(&environment, &script_vm, "post-gc", time.now(), 0)

	// Phase D: pure create/destroy churn per GUI class. Repeats must plateau if
	// the class cleans up after itself; a rising slope names the leaking class.
	churn_classes := []string{"TextLabel-raw", "Frame-raw", "TextLabel-rendered"}
	churn_builders := []string {
		"Instance.new(\"TextLabel\")",
		"Instance.new(\"Frame\")",
		"UI.create(\"TextLabel\", {Text = \"probe row\"})",
	}
	for round in 0 ..< 3 {for class_index in 0 ..< len(churn_classes) {
			class_name := churn_classes[class_index]
			class_builder := churn_builders[min(class_index, len(churn_builders) - 1)]
			start := time.now()
			source, source_err := strings.concatenate(
				{
					"local UI = require(\"@internal/editor_ui\")\n",
					"local shared = UI.shared()\n",
					"local parent = _G.__leak_probe_churn\n",
					"if parent == nil then\n",
					"\tparent = Instance.new(\"Folder\")\n",
					"\tparent.Name = \"LeakProbeChurn\"\n",
					"\tparent.Parent = game.CoreGui\n",
					"\t_G.__leak_probe_churn = parent\n",
					"end\n",
					"local before = #shared.buttons\n",
					"local made = {}\n",
					"for i = 1, 2500 do\n",
					"\tlocal widget = (function() return ",
					class_builder,
					" end)()\n",
					"\twidget.Parent = parent\n",
					"\ttable.insert(made, widget)\n",
					"end\n",
					"for _, object in ipairs(made) do\n",
					"\tobject:Destroy()\n",
					"end\n",
					"UI.forgetButtons(parent)\n",
					"print(\"CHURN_BUTTONS \" .. (#shared.buttons - before))\n",
				},
			)
			if source_err != nil {
				panic("churn script build failed")
			}
			ok, err := vm.RunInternal(&script_vm, source, "leak_probe_churn")
			delete(source)
			if !ok {
				fmt.eprintln(err)
			}
			frame(&environment, &script_vm, surface, width, height)
			frame(&environment, &script_vm, surface, width, height)
			label := fmt.tprintf("churn %s r%d", class_name, round)
			snapshot(&environment, &script_vm, label, start, 2)
		}
	}

	// Phase E: the two typeface-heavy paths no churn covered.
	// E1: TextService:GetTextSize (loads + destroys a typeface per call).
	// Split: first 2 rounds measure growth while calling, then GC + measure to
	// see whether the cost is uncollected garbage or a hard native leak.
	//
	// start is re-taken inside the round loop on purpose. Capturing it once
	// before the loop made the reported ms/frame cumulative, so a perfectly
	// steady per-round cost printed as a straight ramp and read as a leak.
	for round in 0 ..< 6 {
		start := time.now()
		for _ in 0 ..< 40 {
			ok, err := vm.RunInternal(
				&script_vm,
				`
local TextService = game:GetService("TextService")
for i = 1, 20 do
	TextService:GetTextSize("Workspace.Part", 12, "builtin://fonts/Montserrat-Regular.ttf", Vector2.new(10000, 10000))
end
`,
				"leak_probe_textsize",
			)
			if !ok {
				fmt.eprintln(err)
			}
		}
		label := fmt.tprintf("gettextsize r%d", round)
		snapshot(&environment, &script_vm, label, start, 40)
	}
	luauh.lua_gc(script_vm.L, LUA_GCCOLLECT, 0)
	snapshot(&environment, &script_vm, "gettextsize+gc", time.now(), 0)
	// E2: rendered labels inside the live Studio ScreenGui (construct + render + destroy).
	// start is re-taken per round for the same reason as E1.
	for round in 0 ..< 3 {
		start := time.now()
		ok, err := vm.RunInternal(
				&script_vm,
				`
local UI = require("@internal/editor_ui")
local host = UI.frame(UI.root(), UDim2.fromOffset(0, 0), UDim2.fromOffset(300, 400), Color3.new(0, 0, 0))
local made = {}
for i = 1, 60 do
	local row = UI.label(host, "row " .. i, UDim2.fromOffset(4, i * 6), UDim2.fromOffset(200, 14))
	table.insert(made, row)
end
_G.__leak_probe_render_host = host
`,
			"leak_probe_render_make",
		)
		if !ok {
			fmt.eprintln(err)
		}
		frame(&environment, &script_vm, surface, width, height)
		frame(&environment, &script_vm, surface, width, height)
		frame(&environment, &script_vm, surface, width, height)
		ok2, err2 := vm.RunInternal(
			&script_vm,
			`
local host = _G.__leak_probe_render_host
if host then host:Destroy() end
_G.__leak_probe_render_host = nil
`,
			"leak_probe_render_kill",
		)
		if !ok2 {
			fmt.eprintln(err2)
		}
		frame(&environment, &script_vm, surface, width, height)
		frame(&environment, &script_vm, surface, width, height)
		label := fmt.tprintf("rendered labels r%d", round)
		snapshot(&environment, &script_vm, label, start, 5)
	}

	// Attribute the growth: count live GUI nodes per major editor container.
	count_ok, count_err := vm.RunInternal(
		&script_vm,
		`
local function countDescendants(root)
	local n = 0
	for _ in ipairs(root:GetDescendants()) do n += 1 end
	return n
end
local studio = game.CoreGui:FindFirstChild("Studio")
if studio then
	for _, child in ipairs(studio:GetChildren()) do
		print("STUDIO_CHILD " .. child.Name .. "=" .. tostring(countDescendants(child)))
	end
end
local UI = require("@internal/editor_ui")
local shared = UI.shared()
print("SHARED_BUTTONS=" .. tostring(shared.buttons and #shared.buttons or -1))
print("SHARED_TOASTS=" .. tostring(shared.toasts and #shared.toasts or -1))
print("OVERLAY=" .. tostring(shared.overlayRoot and countDescendants(shared.overlayRoot) or -1))
`,
		"leak_probe_count",
	)
	if !count_ok {
		fmt.eprintln(count_err)
	}

	for descriptor in environment.classes.classes {
		n := len(descriptor.instances)
		if n >= 25 {
			fmt.printf("[LeakProbe]   %-28s %d\n", descriptor.info.name, n)
		}
	}

	fmt.printf(
		"[LeakProbe] tracker total_alloc=%d total_freed=%d live=%d peak=%d map_len=%d\n",
		track.total_memory_allocated,
		track.total_memory_freed,
		track.current_memory_allocated,
		track.peak_memory_allocated,
		len(track.allocation_map),
	)
	// Without this guard a tracker that never received a single allocation
	// prints "(0 live allocations, 0.0MB)" and reads as a clean result.
	if track.total_allocation_count == 0 {
		fmt.println(
			"[LeakProbe] WARNING: tracker saw zero allocations; the live= column is a false negative, not a clean bill of health.",
		)
		fmt.println("[LeakProbe] WARNING: engine resets context at every VM entry point, so Odin-side attribution is unavailable.")
		fmt.println("[LeakProbe] WARNING: trust ws/priv/luau/instances instead; see install_tracking_allocator.")
	}

	// The per-callsite report was defined but never called, so the run ended
	// without ever naming the Odin side of anything still live.
	tracking_report_top("final", 15)

	fmt.println("EDITOR_LEAK_PROBE_DONE")
}
