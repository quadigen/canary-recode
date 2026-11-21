package main
import runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"
import "vendor:sdl3"

run :: proc(state: ^vm.VM, source: string) {
	ok, err := vm.Run(state, source, "input_parity")
	if !ok {fmt.eprintln(err); panic("input parity failed")}
}
main :: proc() {
	state := vm.New()
	env: runtime.Environment
	runtime.Environment_Init(&env, &state)
	run(
		&state,
		`
local input = game:GetService("UserInputService")
assert(input:GetStringForKeyCode(Enum.KeyCode.A):upper() == "A")
assert(#input:GetNavigationGamepads() == 0)
pressedWithShift = false
pressedWithoutShift = false
input.InputBegan:Connect(function(event)
	if event.KeyCode == Enum.KeyCode.A then
		if event:IsModifierKeyDown(Enum.ModifierKey.Shift) then pressedWithShift = true
		else pressedWithoutShift = true end
	end
end)
`,
	)
	event: sdl3.Event
	event.type = .KEY_DOWN
	event.key.scancode = .LSHIFT
	runtime.Environment_SetEvent(&env, &state, event)
	event.key.scancode = .A
	runtime.Environment_SetEvent(&env, &state, event)
	event.type = .KEY_UP
	runtime.Environment_SetEvent(&env, &state, event)
	event.key.scancode = .LSHIFT
	runtime.Environment_SetEvent(&env, &state, event)
	event.type = .KEY_DOWN
	event.key.scancode = .A
	runtime.Environment_SetEvent(&env, &state, event)
	run(&state, `assert(pressedWithShift and pressedWithoutShift)`)
	event = {}
	event.type = .GAMEPAD_ADDED
	event.gdevice.which = 42
	runtime.Environment_SetEvent(&env, &state, event)
	run(
		&state,
		`
local input = game:GetService("UserInputService")
assert(input:IsNavigationGamepad(Enum.UserInputType.Gamepad1))
assert(#input:GetNavigationGamepads() == 1)
input:SetNavigationGamepad(Enum.UserInputType.Gamepad1,false)
assert(not input:IsNavigationGamepad(Enum.UserInputType.Gamepad1))
assert(#input:GetNavigationGamepads() == 0)
assert(input:GetGamepadConnected(Enum.UserInputType.Gamepad1))
input:SetNavigationGamepad(Enum.UserInputType.Gamepad1,true)
assert(input:IsNavigationGamepad(Enum.UserInputType.Gamepad1))
`,
	)
	vm.Close(&state)
	runtime.Environment_Destroy(&env)
	fmt.println("LOCAL_INPUT_PARITY_SMOKE_PASSED")
}
