package main

import "core:fmt"
import "core:strings"
import engine_runtime "../src/engine/runtime"
import classes "../src/engine/classes"
import vm "../src/engine/vm"
import sdl3 "../src/engine/platform"
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

make_text_input :: proc(text: string) -> (sdl3.Event, string) {
	buf := strings.clone(text)
	e: sdl3.Event
	e.type = .TEXT_INPUT
	e.text.text = cstring(raw_data(buf))
	return e, buf
}

// send_key / send_text wrap the exact engine event path used per frame.
send_key :: proc(env: ^engine_runtime.Environment, vm_state: ^vm.VM, scancode: sdl3.Scancode, mod: sdl.Keymod) {
	event := make_key_down(scancode, mod)
	classes.TextBox_Handle_Event(&env.classes, vm_state.L, event)
}

send_text :: proc(env: ^engine_runtime.Environment, vm_state: ^vm.VM, text: string) {
	event, buf := make_text_input(text)
	defer delete(buf)
	classes.TextBox_Handle_Event(&env.classes, vm_state.L, event)
}

assert_text :: proc(env: ^engine_runtime.Environment, vm_state: ^vm.VM, box: ^classes.TextBox, expected: string, iteration: int, label: string) {
	if !classes.TextBox_get(vm_state.L, cast(^classes.Object)box, &env.datatypes, &env.enums, "Text") {
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

	run_script(&script_vm, `
local box = Instance.new("TextBox")
box.Name = "StressBox"
box.Text = "abc"
box.CodeEditor = true
box.AutoClose = false
box.MaxLength = -1
_G.box = box
`, "textbox_setup")

	descriptor := classes.Find_Class(&environment.classes, "TextBox")
	if descriptor == nil || len(descriptor.instances) != 1 {
		panic("expected exactly one TextBox instance")
	}
	box := cast(^classes.TextBox)descriptor.instances[0]

	classes.TextBox_focus(box)
	if !box.focused {
		panic("expected box to become focused")
	}

	// Reproduces the typing-over-a-selection path:
	//   Ctrl+A selects all, then consecutive TEXT_INPUT chars merge into the
	//   same undo entry which also carries the erased text. Consecutive chars
	//   after a replacement are the exact "typing in the textbox" crash path.
	for iter in 0 ..< 50 {
		send_key(&environment, &script_vm, .A, sdl.KMOD_CTRL) // select all "abc"
		send_text(&environment, &script_vm, "X")
		send_text(&environment, &script_vm, "Y")
		send_text(&environment, &script_vm, "Z")
		assert_text(&environment, &script_vm, box, "XYZ", iter, "after typing")

		send_key(&environment, &script_vm, .Z, sdl.KMOD_CTRL) // undo replacement
		assert_text(&environment, &script_vm, box, "abc", iter, "after undo")

		send_key(&environment, &script_vm, .Y, sdl.KMOD_CTRL) // redo replacement
		assert_text(&environment, &script_vm, box, "XYZ", iter, "after redo")

		send_key(&environment, &script_vm, .Z, sdl.KMOD_CTRL) // undo again
		assert_text(&environment, &script_vm, box, "abc", iter, "after second undo")
	}

	// Teardown mirrors gui_component_smoke: close the Lua state first so the
	// GC destroys the still-alive userdata, then free the environment.
	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("TEXTBOX_TYPE_UNDO_SMOKE_PASSED")
}