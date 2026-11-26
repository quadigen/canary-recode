package main

import classes "../src/engine/classes"
import platform "../src/engine/platform"
import rt "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run :: proc(state: ^vm.VM, source: string) {
	ok, err := vm.RunInternal(state, source, "textbox_submit")
	assert(ok, err)
}

key :: proc(env: ^rt.Environment, state: ^vm.VM, code: platform.Scancode) {
	event: platform.Event
	event.type = .KEY_DOWN
	event.key.scancode = code
	rt.Environment_SetEvent(env, state, event)
}

main :: proc() {
	state := vm.New()
	env: rt.Environment
	rt.Environment_Init(&env, &state)
	run(
		&state,
		`
part = Instance.new("Part", workspace)
part.Name = "SubmitProbe"
property = Instance.new("TextBox")
property.ClearTextOnFocus = false
property.Text = "12"
property.FocusLost:Connect(function(enter)
    property.Text = tostring(tonumber(property.Text))
    part.Transparency = tonumber(property.Text) / 100
    propertySubmitted = enter
end)
property:CaptureFocus()
`,
	)
	key(&env, &state, .RETURN)
	run(
		&state,
		`assert(propertySubmitted == true, "no property submit"); assert(math.abs(part.Transparency - 0.12) < 0.001); assert(not property:IsFocused())`,
	)
	run(
		&state,
		`
command = Instance.new("TextBox")
command.ClearTextOnFocus = false
command.Text = "workspace.SubmitProbe.Transparency = 0.42"
submitted = {}
command.FocusLost:Connect(function(enter)
    if enter then
        table.insert(submitted, command.Text)
        assert(game:GetService("ScriptContext"):Run(command.Text, "Console"))
        command.Text = ""
        command:CaptureFocus()
    end
end)
command:CaptureFocus()
`,
	)
	key(&env, &state, .RETURN)
	run(
		&state,
		`assert(#submitted == 1 and submitted[1] == "workspace.SubmitProbe.Transparency = 0.42", "no command submit"); assert(command:IsFocused(), "command lost focus"); assert(game:GetService("UserInputService"):GetFocusedTextBox() == command, "focused textbox pointer lost"); assert(math.abs(part.Transparency - 0.42) < 0.001, "command not executed"); command.Text = "workspace.SubmitProbe.Transparency = 0.65"`,
	)
	key(&env, &state, .KP_ENTER)
	run(
		&state,
		`assert(#submitted == 2 and submitted[2] == "workspace.SubmitProbe.Transparency = 0.65", "keypad enter did not submit"); assert(math.abs(part.Transparency - 0.65) < 0.001)`,
	)
	run(
		&state,
		`
other = Instance.new("TextBox")
other.ClearTextOnFocus = false
other:CaptureFocus()
assert(not command:IsFocused() and other:IsFocused())
other.Text = "line"
other.CursorPosition = #other.Text + 1
other.SelectionStart = #other.Text + 1
other.MultiLine = true
`,
	)
	key(&env, &state, .RETURN)
	run(
		&state,
		`assert(other:IsFocused() and other.Text == "line\n", "multiline return behavior changed: " .. tostring(other:IsFocused()) .. " text=" .. string.format("%q",other.Text))`,
	)
	fmt.println("TEXTBOX_SUBMIT_SMOKE_PASSED")
}
