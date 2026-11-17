package main

import classes "../src/engine/classes"
import sdl3 "../src/engine/platform"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"
import "core:strings"
import sdl "vendor:sdl3"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("textbox type/undo smoke test setup failed")
	}
}

make_key_down :: proc(scancode: sdl3.Scancode, mod: sdl.Keymod) -> sdl3.Event {
	e: sdl3.Event
	e.type = .KEY_DOWN
	e.key.scancode = scancode
	e.key.mod = mod
	return e
}

make_text_input :: proc(text: string) -> (sdl3.Event, cstring) {
	buf := strings.clone_to_cstring(text)
	e: sdl3.Event
	e.type = .TEXT_INPUT
	e.text.text = buf
	return e, buf
}

// send_key / send_text wrap the exact engine event path used per frame.
send_key :: proc(
	env: ^engine_runtime.Environment,
	vm_state: ^vm.VM,
	scancode: sdl3.Scancode,
	mod: sdl.Keymod,
) {
	event := make_key_down(scancode, mod)
	classes.TextBox_Handle_Event(&env.classes, vm_state.L, event)
}

send_text :: proc(env: ^engine_runtime.Environment, vm_state: ^vm.VM, text: string) {
	event, buf := make_text_input(text)
	defer delete(buf)
	classes.TextBox_Handle_Event(&env.classes, vm_state.L, event)
}

assert_text :: proc(
	env: ^engine_runtime.Environment,
	vm_state: ^vm.VM,
	box: ^classes.TextBox,
	expected: string,
	iteration: int,
	label: string,
) {
	if !classes.TextBox_get(
		vm_state.L,
		cast(^classes.Object)box,
		&env.datatypes,
		&env.enums,
		"Text",
	) {
		panic("TextBox_get(Text) failed")
	}
	text, ok := vm.ToString(vm_state.L, -1)
	if !ok || text != expected {
		fmt.eprintfln("mismatch iter=%d %s: expected %q, got %q", iteration, label, expected, text)
		panic("textbox undo state mismatch")
	}
	vm.Pop(vm_state.L, 1)
}

main :: proc() {
	ok := sdl3.Init(sdl3.INIT_VIDEO | sdl3.INIT_EVENTS)
	if !ok {
		fmt.eprintln("SDL_Init failed: ", sdl3.GetError())
		panic("SDL init failure")
	}

	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	run_script(
		&script_vm,
		`
local box = Instance.new("TextBox")
box.Name = "StressBox"
box.Text = "abc"
box.CodeEditor = true
box.AutoClose = false
box.MaxLength = -1
Instance.new("SyntaxHighlighter", box)
TEXT_CHANGES = {}
box:GetPropertyChangedSignal("Text"):Connect(function()
	table.insert(TEXT_CHANGES, box.Text)
	box.Text = box.Text
end)
box.Text = "abc"
assert(#TEXT_CHANGES == 0, "unchanged assignments must not fire Text signals")
_G.box = box
`,
		"textbox_setup",
	)

	descriptor := classes.Find_Class(&environment.classes, "TextBox")
	if descriptor == nil || len(descriptor.instances) != 1 {
		panic("expected exactly one TextBox instance")
	}
	box := cast(^classes.TextBox)descriptor.instances[0]
	highlight_descriptor := classes.Find_Class(&environment.classes, "SyntaxHighlighter")
	assert(highlight_descriptor != nil && len(highlight_descriptor.instances) == 1)
	highlighter := cast(^classes.SyntaxHighlighter)highlight_descriptor.instances[0]

	classes.TextBox_focus(box)
	if !box.focused {
		panic("expected box to become focused")
	}

	// Reproduces the typing-over-a-selection path:
	//   Ctrl+A selects all, then consecutive TEXT_INPUT chars merge into the
	//   same undo entry which also carries the erased text. Consecutive chars
	//   after a replacement are the exact "typing in the textbox" crash path.
	keys := []string{"X", "Y", "Z"}
	for iter in 0 ..< 50 {
		send_key(&environment, &script_vm, .A, sdl.KMOD_CTRL) // select all "abc"
		for key in keys {
			send_text(&environment, &script_vm, key)
			classes.syntax_highlighter_ensure(highlighter, box.text)
			assert(highlighter.spans_valid && highlighter.cached_text == box.text)
		}
		assert_text(&environment, &script_vm, box, "XYZ", iter, "after typing")
		if iter == 0 {
			run_script(
				&script_vm,
				`
assert(#TEXT_CHANGES == 4)
assert(table.concat(TEXT_CHANGES, ",") == ",X,XY,XYZ")
`,
				"textbox_native_text_changes",
			)
		}

		send_key(&environment, &script_vm, .Z, sdl.KMOD_CTRL) // undo replacement
		assert_text(&environment, &script_vm, box, "abc", iter, "after undo")

		send_key(&environment, &script_vm, .Y, sdl.KMOD_CTRL) // redo replacement
		assert_text(&environment, &script_vm, box, "XYZ", iter, "after redo")

		send_key(&environment, &script_vm, .Z, sdl.KMOD_CTRL) // undo again
		assert_text(&environment, &script_vm, box, "abc", iter, "after second undo")
	}

	display := classes.text_box_display_cstring("\té\t\x01z\r", 4)
	assert(string(display) == "    é   z")
	delete(display)
	segment := classes.text_box_display_cstring("\té\t\x01z\r", 4, len("\té"))
	assert(string(segment) == "   z")
	delete(segment)

	run_script(&script_vm, `_G.box.Text = "a\tb"; _G.box.TabSize = 4`, "textbox_tab_measure")
	width_with_tab := classes.text_box_measure_range(box, 0, len(box.text))
	assert_text(&environment, &script_vm, box, "a\tb", 0, "preserve stored tab")
	run_script(&script_vm, `_G.box.Text = "a   b"`, "textbox_spaces_measure")
	assert(width_with_tab == classes.text_box_measure_range(box, 0, len(box.text)))
	run_script(&script_vm, `_G.box.Text = "a\t"; _G.box.CursorPosition = 3`, "textbox_tab_indent")
	send_key(&environment, &script_vm, .TAB, {})
	assert_text(&environment, &script_vm, box, "a\t    ", 0, "indent after an existing tab")

	run_script(
		&script_vm,
		`
_G.box.Position = UDim2.fromOffset(50, 50)
_G.box.Size = UDim2.fromOffset(300, 120)
_G.box.Text = "alpha\nbeta_name! gamma"
`,
		"textbox_click_setup",
	)
	classes.Update_GUI_Layout(&environment.classes, 800, 600)
	last_glyph_left := classes.text_box_measure_range(box, 6, 14)
	last_glyph_right := classes.text_box_measure_range(box, 6, 15)
	event: sdl3.Event
	event.type = .MOUSE_BUTTON_DOWN
	event.button.button = sdl3.BUTTON_LEFT
	event.button.clicks = 2
	event.button.x =
		box.absolute_position.X +
		box.editor_padding +
		classes.text_box_gutter_width(box) +
		last_glyph_left +
		(last_glyph_right - last_glyph_left) * 0.75
	event.button.y =
		box.absolute_position.Y + box.editor_padding + 1.5 * classes.text_box_line_height(box)
	classes.TextBox_Handle_Event(&environment.classes, script_vm.L, event)
	run_script(
		&script_vm,
		`assert(_G.box.SelectedText == "beta_name", _G.box.SelectedText)`,
		"textbox_word_selection",
	)
	event.button.clicks = 3
	classes.TextBox_Handle_Event(&environment.classes, script_vm.L, event)
	run_script(
		&script_vm,
		`assert(_G.box.SelectedText == "beta_name! gamma")`,
		"textbox_line_selection",
	)

	run_script(
		&script_vm,
		`
box:ReleaseFocus()
local input = Instance.new("TextBox")
input.Name = "IrisTextBox"
input.ClearTextOnFocus = false
input.MultiLine = true
input.TextWrapped = true
input.RichText = true
input.TextTruncate = Enum.TextTruncate.AtEnd
assert(input.MultiLine and input.TextWrapped and input.WordWrap)
assert(input.RichText and input.TextTruncate == Enum.TextTruncate.AtEnd)
assert(not input.CodeEditor)
_G.irisInput = input
_G.irisFocusCount = 0
input.Focused:Connect(function()
	assert(input:IsFocused())
	_G.irisFocusCount += 1
end)
input.Text = "first"
input:CaptureFocus()
input:CaptureFocus()
assert(_G.irisFocusCount == 1)
input.CursorPosition = 6
`,
		"textbox_iris_focus",
	)
	send_key(&environment, &script_vm, .RETURN, {})
	send_text(&environment, &script_vm, "second")
	run_script(
		&script_vm,
		`
assert(_G.irisInput.Text == "first\nsecond" and _G.irisInput:IsFocused())
_G.irisInput:ReleaseFocus()
_G.irisInput:CaptureFocus()
assert(_G.irisFocusCount == 2)
`,
		"textbox_iris_multiline",
	)

	// Teardown mirrors gui_component_smoke: close the Lua state first so the
	// GC destroys the still-alive userdata, then free the environment.
	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("TEXTBOX_TYPE_UNDO_SMOKE_PASSED")
}
