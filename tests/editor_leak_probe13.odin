#+feature dynamic-literals
package main

import "core:fmt"
import "core:os"
import "core:strconv"
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

churn_chunk :: proc(mode: string) -> string {
	// Recreate a VirtualizedScrolling ScrollingFrame with 20 rows each round.
	case_mode := mode
	_ = case_mode
	switch mode {
	case "virtscroll":
		return `
	local UI = require("@internal/editor_ui")
	if _G.__vsf ~= nil then _G.__vsf:Destroy() end
	local sf = UI.create("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 200),
		Size = UDim2.fromOffset(400, 300),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(0, 0, 0, 800),
		ScrollingEnabled = true,
		VirtualizedScrolling = true,
		ClipsDescendants = true,
	}, UI.root())
	for i = 1, 20 do
		local row = UI.frame(sf, UDim2.fromOffset(0, i * 20), UDim2.fromOffset(396, 19), nil)
		UI.label(row, "Row " .. i, UDim2.fromOffset(4, 2), UDim2.fromOffset(100, 15), nil, nil)
		UI.image(row, "builtin://icons/ArrowRight.svg", UDim2.fromOffset(110, 3), UDim2.fromOffset(12, 12))
	end
	_G.__vsf = sf
	`

	// Breadcrumb-style churn: UI.clear + GetTextSize + label + UIShadow + image.
	case "breadcrumb":
		return `
	local UI = require("@internal/editor_ui")
	local TextService = game:GetService("TextService")
	local bc = _G.__breadcrumb
	if bc == nil then
		bc = UI.create("Frame", {
			Position = UDim2.fromOffset(0, 100),
			Size = UDim2.fromOffset(600, 26),
			BackgroundTransparency = 1,
		}, UI.root())
		_G.__breadcrumb = bc
	end
	UI.clear(bc)
	local x = 8
	for index, item in ipairs({"game", "Workspace", "Camera", "Part"}) do
		local textSize = TextService:GetTextSize(item, 11, "builtin://fonts/Montserrat-Regular.ttf", Vector2.new(10000, 10000))
		local width = math.max(34, math.ceil(textSize.X) + 4)
		local label = UI.label(bc, item, UDim2.fromOffset(x, 4), UDim2.fromOffset(width, 18), nil, Color3.new(1, 1, 1))
		local shadow = Instance.new("UIShadow")
		shadow.ShowForText = true
		shadow.BlurRadius = UDim.new(0, 2.5)
		shadow.Offset = UDim2.fromOffset(2, 2)
		shadow.Spread = UDim2.fromOffset(0, 5)
		shadow.Color3 = Color3.fromRGB(0, 0, 0)
		shadow.Transparency = 0.8
		shadow.Parent = label
		x += width + 2
		if index < 4 then
			UI.image(bc, "builtin://icons/ArrowRight.svg", UDim2.fromOffset(x + 1, 7), UDim2.fromOffset(10, 10))
			x += 13
		end
	end
	`

	// Inspector-style churn: UI.clear on a ScrollingFrame + category bubbles
	// with rows (label + textbutton/input + stroke + corner).
	case "inspbubble":
		return `
	local UI = require("@internal/editor_ui")
	local sf = _G.__inssf
	if sf == nil then
		sf = UI.create("ScrollingFrame", {
			Position = UDim2.fromOffset(500, 100),
			Size = UDim2.fromOffset(420, 500),
			BackgroundTransparency = 1,
			CanvasSize = UDim2.new(0, 0, 0, 2000),
			ScrollingEnabled = true,
			ClipsDescendants = true,
		}, UI.root())
		_G.__inssf = sf
	end
	UI.clear(sf)
	local y = 1
	for cat = 1, 3 do
		local bubble = UI.frame(sf, UDim2.fromOffset(4, y), UDim2.fromOffset(400, 180), nil)
		UI.corner(bubble, 6)
		UI.stroke(bubble, nil, 1, 0)
		UI.label(bubble, "Category " .. cat, UDim2.fromOffset(10, 4), UDim2.fromOffset(150, 16), nil, nil)
		for row = 1, 6 do
			local rl = UI.label(bubble, "Prop" .. row, UDim2.fromOffset(10, 30 + row * 22), UDim2.fromOffset(120, 18), nil, nil)
			_ = rl
			if row % 2 == 0 then
				local btn = UI.button(bubble, "value", UDim2.fromOffset(140, 30 + row * 22), UDim2.fromOffset(200, 18), function() end, nil)
				_ = btn
			else
				local inp = UI.input(bubble, "value", UDim2.fromOffset(140, 30 + row * 22), UDim2.fromOffset(200, 18), nil)
				_ = inp
			end
		end
		y += 190
	end
	`

	// Bisect: UI.clear + labels + UIShadow only (no GetTextSize).
	case "shadowonly":
		return `
	local UI = require("@internal/editor_ui")
	local bc = _G.__breadcrumb
	if bc == nil then
		bc = UI.create("Frame", {
			Position = UDim2.fromOffset(0, 100),
			Size = UDim2.fromOffset(600, 26),
			BackgroundTransparency = 1,
		}, UI.root())
		_G.__breadcrumb = bc
	end
	UI.clear(bc)
	local x = 8
	for _, item in ipairs({"game", "Workspace", "Camera", "Part"}) do
		local label = UI.label(bc, item, UDim2.fromOffset(x, 4), UDim2.fromOffset(60, 18), nil, Color3.new(1, 1, 1))
		local shadow = Instance.new("UIShadow")
		shadow.ShowForText = true
		shadow.BlurRadius = UDim.new(0, 2.5)
		shadow.Offset = UDim2.fromOffset(2, 2)
		shadow.Spread = UDim2.fromOffset(0, 5)
		shadow.Color3 = Color3.fromRGB(0, 0, 0)
		shadow.Transparency = 0.8
		shadow.Parent = label
		x += 65
	end
	`

	// Bisect: UI.clear + GetTextSize + labels (no UIShadow).
	case "gtslabel":
		return `
	local UI = require("@internal/editor_ui")
	local TextService = game:GetService("TextService")
	local bc = _G.__breadcrumb
	if bc == nil then
		bc = UI.create("Frame", {
			Position = UDim2.fromOffset(0, 100),
			Size = UDim2.fromOffset(600, 26),
			BackgroundTransparency = 1,
		}, UI.root())
		_G.__breadcrumb = bc
	end
	UI.clear(bc)
	local x = 8
	for _, item in ipairs({"game", "Workspace", "Camera", "Part"}) do
		local textSize = TextService:GetTextSize(item, 11, "builtin://fonts/Montserrat-Regular.ttf", Vector2.new(10000, 10000))
		local width = math.max(34, math.ceil(textSize.X) + 4)
		UI.label(bc, item, UDim2.fromOffset(x, 4), UDim2.fromOffset(width, 18), nil, Color3.new(1, 1, 1))
		x += width + 2
	end
	`

	// Explorer exact shape: kept virtualized list + UI.clear + addRow-shaped
	// rows (button + Activated connect + images + label).
	case "explorer":
		return `
	local UI = require("@internal/editor_ui")
	local Selection = game:GetService("Selection")
	local list = _G.__explorerlist
	if list == nil then
		list = UI.create("ScrollingFrame", {
			Position = UDim2.fromOffset(0, 200),
			Size = UDim2.fromOffset(400, 300),
			BackgroundTransparency = 1,
			CanvasSize = UDim2.new(0, 0, 0, 800),
			ScrollingEnabled = true,
			VirtualizedScrolling = true,
			ClipsDescendants = true,
			Active = true,
			InputSink = true,
		}, UI.root())
		_G.__explorerlist = list
	end
	UI.clear(list)
	local y = 1
	for i = 1, 20 do
		local row = UI.button(list, "", UDim2.fromOffset(1, y), UDim2.new(1, -2, 0, 20), function()
			Selection:Set({})
		end, { border = false })
		row.Activated:Connect(function(input, clickCount)
			_ = input
			_ = clickCount
		end)
		UI.image(row, "builtin://icons/ArrowRight.svg", UDim2.fromOffset(7, 4), UDim2.fromOffset(12, 12))
		UI.image(row, "builtin://icons/Part.svg", UDim2.fromOffset(23, 3), UDim2.fromOffset(14, 14))
		UI.label(row, "Instance" .. i, UDim2.fromOffset(38, 2), UDim2.new(1, -41, 0, 17), nil, nil)
		y += 20
	end
	`

	// Pure GetTextSize churn.
	case "gettextsize":
		return `
	local TextService = game:GetService("TextService")
	for i = 1, 30 do
		local ts = TextService:GetTextSize("Some Label Text " .. i, 11, "builtin://fonts/Montserrat-Regular.ttf", Vector2.new(10000, 10000))
		_ = ts
	end
	`

	// Control: the real selection churn.
	case "sel":
		return `
	local Selection = game:GetService("Selection")
	local list = _G.__sel_candidates
	local index = _G.__sel_index
	_G.__sel_index = (index % #list) + 1
	Selection:Set({ list[index] })
	`
	}
	return ""
}

CHURN_MODE :: "CHURN_MODE"
SOAK_ROUNDS :: "SOAK_ROUNDS"

main :: proc() {
	mode_buf: [32]u8
	mode := os.get_env(mode_buf[:], CHURN_MODE)
	if mode == "" {
		mode = "sel"
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
	`, "probe13_boot")

	chunk := churn_chunk(mode)
	assert(chunk != "", "unknown churn mode")

	soak_buf: [16]u8
	soak_rounds := 4
	soak_value := os.get_env(soak_buf[:], SOAK_ROUNDS)
	if soak_value != "" {
		if v, ok := strconv.parse_u64(soak_value); ok {
			soak_rounds = int(v)
		}
	}

	fmt.printf("[Mode] %s rounds=%d\n", mode, soak_rounds)

	for round in 0 ..< soak_rounds {
		start := time.now()
		for _ in 0 ..< 30 {
			run(&script_vm, chunk, "probe13_churn")
			frames(&environment, &script_vm, surface, width, height, 1)
		}
		luauh.lua_gc(script_vm.L, 2, 0)
		snapshot(fmt.tprintf("%s r%d", mode, round), start)
	}

	fmt.println("EDITOR_LEAK_PROBE13_DONE")
}
