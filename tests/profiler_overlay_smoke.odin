package main

import kineffi "../src/engine/bindings"
import classes "../src/engine/classes"
import sdl3 "../src/engine/platform"
import profiling "../src/engine/profiling"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run_script :: proc(script_vm: ^vm.VM, source: string) {
	ok, err := vm.Run(script_vm, source, "profiler_overlay_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("Profiler overlay smoke failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	view: renderer.RendererObject
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm, &view, .Editor)
	defer {
		vm.Close(&script_vm)
		engine_runtime.Environment_Destroy(&environment)
	}
	profiling.set_enabled(false)
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	run_script(
		&script_vm,
		`
local gui = game.CoreGui:FindFirstChild("ProfilerOverlay")
assert(gui and gui.Parent == game.CoreGui, "overlay must be parented in editor")
assert(not gui.Enabled and not gui.Archivable and not gui.CanReplicate)
assert(gui.Panel.BackgroundTransparency == 0.5)
`,
	)
	event := sdl3.Event{}
	event.type = .KEY_DOWN
	event.key.scancode = .F2
	profiling.trigger_event(event)
	for _ in 0 ..< 20 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	}
	run_script(
		&script_vm,
		`
local gui = game.CoreGui.ProfilerOverlay
assert(gui.Enabled)
assert(gui.Panel.Headline.Text == "60.0 FPS", gui.Panel.Headline.Text)
assert(gui.Panel.FrameTime.Text:find("ms", 1, true))
local objectStats = game:GetService("ProfilerService"):GetObjectStats()
local total = 0
for _, item in ipairs(objectStats.classes) do total += item.count end
assert(total == objectStats.total and total > 0)
assert(gui.Panel.FrameGraph.Sample60.Visible)
assert(not gui.Panel.FrameGraph.Sample1.Visible)
`,
	)
	surface := kineffi.Kine_Skia_Surface_Create(640, 480)
	assert(surface != nil)
	defer kineffi.Kine_Skia_Surface_Destroy(surface)
	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 0)
	engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, 640, 480, 1.0 / 60.0)
	engine_runtime.Environment_Render_Overlay(
		&environment,
		&script_vm,
		surface,
		640,
		480,
		1.0 / 60.0,
	)
	kineffi.Kine_Skia_Surface_Flush(surface)
	r, g, b, a: u8
	kineffi.Kine_Skia_Surface_GetPixel(surface, 12, 12, &r, &g, &b, &a)
	assert(a >= 120 && a <= 135, "expected half-transparent background")
	kineffi.Kine_Skia_Surface_GetPixel(surface, 500, 300, &r, &g, &b, &a)
	assert(a == 0, "overlay obscures the rest of the screen")
	headings := []string {
		"CPU ZONES (INCLUSIVE)",
		"LUAU VM (LIVE)",
		"RENDERER (LIVE)",
		"REPLICATION (LIVE)",
		"ENGINE OBJECTS (LIVE)",
		"FRAME STATISTICS",
	}
	tabs := []string{"CPU", "Luau", "GPU", "Net", "Objects", "Frame"}
	for tab, i in tabs {
		tab_index := (i + 1) % 6
		x := f32(10 + (tab_index * 460) / 6 + 30)
		hit := classes.GuiObject_find_topmost(&environment.classes, x, 56)
		assert(
			hit != nil && hit.name == fmt.tprintf("%sTab", tab),
			fmt.tprintf("tab hit: %s", tab),
		)
		click: sdl3.Event
		click.type = .MOUSE_MOTION
		click.motion.x, click.motion.y = x, 56
		engine_runtime.Environment_SetEvent(&environment, &script_vm, click)
		click.type = .MOUSE_BUTTON_DOWN
		click.button.x, click.button.y = x, 56
		click.button.button = sdl3.BUTTON_LEFT
		engine_runtime.Environment_SetEvent(&environment, &script_vm, click)
		click.type = .MOUSE_BUTTON_UP
		engine_runtime.Environment_SetEvent(&environment, &script_vm, click)
		for _ in 0 ..< 15 {
			engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
		}
		engine_runtime.Environment_Render_2D(
			&environment,
			&script_vm,
			surface,
			640,
			480,
			1.0 / 60.0,
		)
		engine_runtime.Environment_Render_Overlay(
			&environment,
			&script_vm,
			surface,
			640,
			480,
			1.0 / 60.0,
		)
		run_script(
			&script_vm,
			fmt.tprintf(
				`local p = game.CoreGui.ProfilerOverlay.Panel
assert(p.%sTab.TextColor3.R == 1, "tab did not switch")
local label = p.Metrics.Row1:FindFirstChild("Name")
assert(label.Text == "%s", label.Text)
assert(p.FrameGraph.Visible == %s)
`,
				tab,
				headings[i],
				tab == "Frame" ? "true" : "false",
			),
		)
	}
	profiling.trigger_event(event)
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	run_script(&script_vm, `assert(not game.CoreGui.ProfilerOverlay.Enabled)`)
	fmt.println("PROFILER_OVERLAY_SMOKE_PASSED")
}
