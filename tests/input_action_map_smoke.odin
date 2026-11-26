package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"
import "vendor:sdl3"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("input action binding smoke failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	run_script(
		&script_vm,
		`
local actions = game:GetService("ContextActionService")
fired = 0
actions:BindAction("Dash", function(name, state)
    assert(name == "Dash")
    if state == Enum.UserInputState.Begin then fired += 1 end
    return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.A)
assert(actions:GetActionBindings("Dash")[1] == Enum.KeyCode.A)
actions:SetActionBindings("Dash", Enum.KeyCode.B, Enum.KeyCode.C)
local bindings = actions:GetActionBindings("Dash")
assert(#bindings == 2 and bindings[1] == Enum.KeyCode.B and bindings[2] == Enum.KeyCode.C)
assert(actions:GetBoundActionInfo("Dash").inputTypes[1] == Enum.KeyCode.B)
local ok = pcall(function() actions:SetActionBindings("Dash", Enum.Material.Plastic) end)
assert(not ok)
assert(actions:GetActionBindings("Dash")[1] == Enum.KeyCode.B)
local exported = actions:ExportActionMap()
assert(exported.Dash[1] == "KeyCode.B" and exported.Dash[2] == "KeyCode.C")
local codec = game:GetService("HttpService")
local restored = codec:JSONDecode(codec:JSONEncode(exported))
actions:ResetActionBindings("Dash")
assert(actions:GetActionBindings("Dash")[1] == Enum.KeyCode.A)
actions:ImportActionMap(restored)
assert(actions:GetActionBindings("Dash")[1] == Enum.KeyCode.B)
ok = pcall(function() actions:ImportActionMap({Dash = {"KeyCode.A"}, Unknown = {"KeyCode.B"}}) end)
assert(not ok)
assert(actions:GetActionBindings("Dash")[1] == Enum.KeyCode.B)
`,
		"action_setup",
	)
	a: sdl3.Event
	a.type = .KEY_DOWN
	a.key.scancode = .A
	engine_runtime.Environment_SetEvent(&environment, &script_vm, a)
	run_script(&script_vm, "assert(fired == 0)", "old_binding_disabled")

	b: sdl3.Event
	b.type = .KEY_DOWN
	b.key.scancode = .B
	engine_runtime.Environment_SetEvent(&environment, &script_vm, b)
	run_script(&script_vm, "assert(fired == 1)", "new_binding_active")

	run_script(
		&script_vm,
		`
local actions = game:GetService("ContextActionService")
actions:ResetActionBindings("Dash")
assert(#actions:GetActionBindings("Dash") == 1)
assert(actions:GetActionBindings("Dash")[1] == Enum.KeyCode.A)
`,
		"action_reset",
	)
	engine_runtime.Environment_SetEvent(&environment, &script_vm, a)
	run_script(&script_vm, "assert(fired == 2)", "original_binding_restored")

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("INPUT_ACTION_MAP_SMOKE_PASSED")
}
