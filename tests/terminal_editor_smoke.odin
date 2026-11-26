package main

import kineffi "../src/engine/bindings"
import packages "../src/engine/packages"
import sdl "../src/engine/platform"
import renderer "../src/engine/renderer"
import runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.RunInternal(v, source, "terminal_editor_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("terminal editor test failed")
	}
}

main :: proc() {
	v := vm.New()
	env: runtime.Environment
	view: renderer.RendererObject
	runtime.Environment_Init(&env, &v, &view, .Editor)
	defer {
		vm.Close(&v)
		runtime.Environment_Destroy(&env)
	}
	surface := kineffi.Kine_Skia_Surface_Create(1024, 768)
	assert(surface != nil)
	defer kineffi.Kine_Skia_Surface_Destroy(surface)
	assert(len(os.args) > 1)
	assert(packages.Load_Internal_Modules_From_Directory(&env.packages, os.args[1]))
	run(
		&v,
		`
local UI = require("@internal/editor_ui")
consoleUI = require("@internal/console")
require("@internal/output")
consolePanel = consoleUI.createConsole()
panel = UI.getWindow("Console")
assert(panel and consolePanel.window == panel)
assert(consolePanel.getSelectedTab() == "Console")
assert(UI.getWindow("Terminal") == nil)
service = game:GetService("TerminalService")
assert(not pcall(function() service:IsRunning(1) end))
consoleUI.ShowTerminal()
assert(panel.Visible and consolePanel.getSelectedTab() == "Terminal")
local shellTabs = panel.Content:FindFirstChild("ShellTabs", true)
assert(shellTabs and not shellTabs.Visible and #shellTabs:GetChildren() == 0)
assert(panel.Content:FindFirstChild("TerminalInput", true))
service = game:GetService("TerminalService")
field = panel.Content:FindFirstChild("TerminalInput", true)
field.Text = "printf " .. string.char(39) .. "%s%s" .. string.char(92) .. "n" .. string.char(39) .. " " .. string.char(39) .. "EDITOR_" .. string.char(39) .. " " .. string.char(39) .. "TERMINAL_OK" .. string.char(39)
field:CaptureFocus()
`,
	)
	event: sdl.Event
	event.type = .KEY_DOWN
	event.key.scancode = .RETURN
	runtime.Environment_SetEvent(&env, &v, event)
	for _ in 0 ..< 100 {
		runtime.Environment_Update_Step(&env, &v, 1.0 / 60.0)
		runtime.Environment_Render_2D(&env, &v, surface, 1024, 768, 1.0 / 60.0)
		runtime.Environment_Render_Overlay(&env, &v, surface, 1024, 768, 1.0 / 60.0)
		sdl.Delay(10)
	}
	run(&v, `assert(service:Execute(1, "seq 1 200"))`)
	for _ in 0 ..< 90 {
		runtime.Environment_Update_Step(&env, &v, 1.0 / 60.0)
		runtime.Environment_Render_2D(&env, &v, surface, 1024, 768, 1.0 / 60.0)
		runtime.Environment_Render_Overlay(&env, &v, surface, 1024, 768, 1.0 / 60.0)
		sdl.Delay(10)
	}
	run(
		&v,
		`
local scroll = field.Parent
local bottom = scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y
assert(bottom > 100 and math.abs(scroll.CanvasPosition.Y - bottom) < 1, tostring(scroll.CanvasPosition.Y) .. " / " .. tostring(bottom))
scroll.CanvasPosition = Vector2.new(0, 0)
assert(service:Execute(1, "seq 201 250"))
`,
	)
	for _ in 0 ..< 90 {
		runtime.Environment_Update_Step(&env, &v, 1.0 / 60.0)
		runtime.Environment_Render_2D(&env, &v, surface, 1024, 768, 1.0 / 60.0)
		runtime.Environment_Render_Overlay(&env, &v, surface, 1024, 768, 1.0 / 60.0)
		sdl.Delay(10)
	}
	run(
		&v,
		`
assert(field.Parent.CanvasPosition.Y < 1, "scrollback moved")
field.Text = "echo ready"
assert(math.abs(field.Parent.CanvasPosition.Y - (field.Parent.AbsoluteCanvasSize.Y - field.Parent.AbsoluteWindowSize.Y)) < 1, "typing did not restore follow")
field.Text = ""
`,
	)
	run(
		&v,
		`
local output = panel.Content:FindFirstChild("TerminalHistory", true)
assert(output)
local historyArrows = 0
for _, item in output:GetDescendants() do
	if item.Name == "HistoricalPromptArrow" and item.Visible and item.Parent.Visible then
		historyArrows += 1
	end
end
assert(output:FindFirstChild("HistoricalPromptArrow", true), "historical prompts not pooled")
local History = require("@internal/terminal_history")
local history = History.new(field.Parent, 0)
local marker = "__KINE_PROMPT__0:/home/devcell__KINE_HOME__/home/devcell__KINE_END__ $ "
local failedMarker = "__KINE_PROMPT__1:/tmp__KINE_HOME__/home/devcell__KINE_END__ $ "
local text = marker .. "echo hello" .. string.char(10) .. "hello" .. string.char(10) .. failedMarker .. "pwd" .. string.char(10) .. "/tmp"
history:setText(text, {[1] = 0}, 0, "sh")
history:layout(600, 20)
assert(#history.rows == 6 and history.rows[2].code == "0" and history.rows[5].code == "1")
assert(history.rows[1].path == "~" and history.rows[4].path == "/tmp")
history.anchor = {row = 2, column = 0}
history.focus = {row = 3, column = 5}
assert(history:selectedText() == "echo hello" .. string.char(10) .. "hello")
history.anchor = {row = 5, column = 3}
history.focus = {row = 5, column = 0}
assert(history:selectedText() == "pwd")
history.root:Destroy()
assert(panel:GetAttribute("Dockable") and panel:FindFirstChild("DragHandle", true))
assert(panel.Content.Terminal.Visible and not panel.Content.Console.Visible)
assert(field.Parent.Name == "TerminalViewport")
assert(not field.BlockCaret and field.SmoothCaret and field.TextPadding == 0)
local prompt = field.Parent:FindFirstChild("TerminalPromptStrip")
assert(prompt and prompt.Visible)
assert(field.Position.Y.Offset > prompt.Position.Y.Offset)

assert(service:GetShellName(1) == "sh")
field.Text = "abcdef"
field:CaptureFocus()
field.CursorPosition = 1

`,
	)
	for _ in 0 ..< 24 {
		runtime.Environment_Update_Step(&env, &v, 1.0 / 60.0)
		runtime.Environment_Render_2D(&env, &v, surface, 1024, 768, 1.0 / 60.0)
		runtime.Environment_Render_Overlay(&env, &v, surface, 1024, 768, 1.0 / 60.0)
	}
	run(&v, "caretStart = field.CaretScreenPosition.X; field.CursorPosition = 7")
	runtime.Environment_Render_2D(&env, &v, surface, 1024, 768, 1.0 / 60.0)
	runtime.Environment_Render_Overlay(&env, &v, surface, 1024, 768, 1.0 / 60.0)
	run(&v, "caretMid = field.CaretScreenPosition.X")
	for _ in 0 ..< 30 {
		runtime.Environment_Render_2D(&env, &v, surface, 1024, 768, 1.0 / 60.0)
		runtime.Environment_Render_Overlay(&env, &v, surface, 1024, 768, 1.0 / 60.0)
	}
	run(
		&v,
		"assert(caretStart < caretMid and caretMid < field.CaretScreenPosition.X, tostring(caretStart) .. ' ' .. tostring(caretMid) .. ' ' .. tostring(field.CaretScreenPosition.X)); field.Text = ''; consolePanel.selectTab('Console')",
	)
	for _ in 0 ..< 30 {
		runtime.Environment_Update_Step(&env, &v, 1.0 / 60.0)
	}
	run(
		&v,
		`
assert(panel.Visible and consolePanel.getSelectedTab() == "Console")
assert(not panel.Content.Terminal.Visible and panel.Content.Console.Visible)
assert(not field:IsFocused())
assert(service:IsRunning(1))
assert(service:Execute(1, "echo hidden-output"))
consoleUI.ShowTerminal()
assert(panel.Visible and consolePanel.getSelectedTab() == "Terminal")
assert(not pcall(function() service:IsRunning(2) end))
assert(field:IsFocused())
consoleUI.Hide()
assert(not panel.Visible)
consoleUI.ShowTerminal()
assert(panel.Visible and consolePanel.getSelectedTab() == "Terminal")
assert(#service:GetHistory(1) == 4)
assert(service:IsRunning(2))
local shellTabs = panel.Content:FindFirstChild("ShellTabs", true)
assert(shellTabs.Visible and shellTabs:FindFirstChild("1Tab", true) and shellTabs:FindFirstChild("2Tab", true))
assert(#service:GetHistory(2) == 0)
assert(field.Text == "")
assert(field:IsFocused())
panel:Destroy()
assert(not pcall(function() service:IsRunning(1) end))
assert(not pcall(function() service:IsRunning(2) end))
`,
	)
	fmt.println("TERMINAL_EDITOR_SMOKE_PASSED")
}
