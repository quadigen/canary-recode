package main

import kineffi "../src/engine/bindings"
import sdl3 "../src/engine/platform"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run_script :: proc(script_vm: ^vm.VM, source: string) {
	ok, err := vm.Run(script_vm, source, "console_overlay_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("Console overlay smoke failed")
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
	surface := kineffi.Kine_Skia_Surface_Create(640, 480)
	assert(surface != nil)
	defer kineffi.Kine_Skia_Surface_Destroy(surface)
	for _ in 0 ..< 12 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	}
	run_script(
		&script_vm,
		`
local gui = game.CoreGui:FindFirstChild("ConsoleOverlay")
assert(gui and not gui.Enabled and not gui.Archivable and not gui.CanReplicate)
assert(gui.Panel.BackgroundTransparency == 0.5)
local console = game:GetService("ConsoleService")
assert(not console.Enabled)
local logs = game:GetService("LogService")
logs:Clear()
print("console test output")
logs:Info("console test info")
warn("console test warning")
logs:Error("console test error")
task.defer(function() error("scheduled console error") end)
`,
	)
	event := sdl3.Event{}
	event.type = .KEY_DOWN
	event.key.scancode = .F9
	engine_runtime.Environment_SetEvent(&environment, &script_vm, event)
	for _ in 0 ..< 30 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
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
	}
	run_script(
		&script_vm,
		`
local gui = game.CoreGui.ConsoleOverlay
assert(gui.Enabled)
local p = gui.Panel
assert(p.AnchorPoint == Vector2.new(0.5, 0.5))
assert(p.Position == UDim2.fromScale(0.5, 0.5))
assert(p.LogTab.Text == "Output 1", p.LogTab.Text)
assert(p.WarnTab.Text == "Warnings 1", p.WarnTab.Text)
assert(p.ErrorTab.Text == "Errors 2", p.ErrorTab.Text)
local found = false
for _, row in ipairs(p.Logs:GetChildren()) do
	assert(not row:IsA("TextBox"))
	if row:IsA("TextLabel") and row.Text:find("scheduled console error", 1, true) then
		found = true
		assert(row.TextColor3.R == 1)
	end
end
assert(found, "scheduled error not visible")
local inputs = 0
for _, item in ipairs(gui:GetDescendants()) do
	if item:IsA("TextBox") then
		inputs += 1
		assert(item == p.Search and not item.MultiLine, "unexpected console input")
	end
end
assert(inputs == 1)
p.Search:CaptureFocus()
`,
	)
	input: sdl3.Event
	input.type = .TEXT_INPUT
	input.text.text = cstring("SCHEDULED CONSOLE")
	engine_runtime.Environment_SetEvent(&environment, &script_vm, input)
	for _ in 0 ..< 25 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
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
	}
	run_script(
		&script_vm,
		`
local p = game.CoreGui.ConsoleOverlay.Panel
assert(p.Search.Text == "SCHEDULED CONSOLE", p.Search.Text)
assert(p.Footer.Text:find("1 matching", 1, true), p.Footer.Text)
assert(not p.Empty.Visible)
for _, row in ipairs(p.Logs:GetChildren()) do
	if row:IsA("TextLabel") and row.Visible then
		assert(not row.Text:find("console test output", 1, true))
	end
end
p.Search.Text = "[%("
`,
	)
	for _ in 0 ..< 25 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	}
	run_script(
		&script_vm,
		`
local p = game.CoreGui.ConsoleOverlay.Panel
assert(p.Empty.Visible and p.Empty.Text == "No matching logs")
p.Search.Text = "error('must never execute')"
`,
	)
	input.type = .KEY_DOWN
	input.key.scancode = .RETURN
	engine_runtime.Environment_SetEvent(&environment, &script_vm, input)
	for _ in 0 ..< 25 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	}
	run_script(
		&script_vm,
		`
local p = game.CoreGui.ConsoleOverlay.Panel
assert(game:GetService("LogService").ErrorCount == 2)
assert(p.Empty.Visible)
p.Search.Text = ""
`,
	)
	for _ in 0 ..< 25 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	}
	run_script(
		&script_vm,
		`
local p = game.CoreGui.ConsoleOverlay.Panel
assert(p.Footer.Text:find("5 matching", 1, true), p.Footer.Text)
assert(not p.Empty.Visible)
`,
	)
	event.key.repeat = true
	engine_runtime.Environment_SetEvent(&environment, &script_vm, event)
	run_script(&script_vm, `assert(game:GetService("ConsoleService").Enabled)`)
	event.key.repeat = false
	engine_runtime.Environment_SetEvent(&environment, &script_vm, event)
	for _ in 0 ..< 12 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	}
	run_script(&script_vm, `assert(not game.CoreGui.ConsoleOverlay.Enabled)`)
	fmt.println("CONSOLE_OVERLAY_SMOKE_PASSED")
}
