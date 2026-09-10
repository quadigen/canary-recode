package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "vendor:sdl3"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("UserInputService smoke test failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	run_script(&script_vm, `
local input = game:GetService("UserInputService")
assert(input.KeyboardEnabled and input.MouseEnabled)
assert(not input.TouchEnabled and not input.GamepadEnabled)
assert(input.InputBegan == input.InputBegan)

began = {}
changed = {}
ended = {}

input.InputBegan:Connect(function(inputObject, gameProcessedEvent)
    assert(inputObject.ClassName == "InputObject")
    assert(gameProcessedEvent == false)
    table.insert(began, inputObject)
end)
input.InputChanged:Connect(function(inputObject, gameProcessedEvent)
    assert(inputObject.ClassName == "InputObject")
    assert(gameProcessedEvent == false)
    table.insert(changed, inputObject)
end)
input.InputEnded:Connect(function(inputObject, gameProcessedEvent)
    assert(inputObject.ClassName == "InputObject")
    assert(gameProcessedEvent == false)
    table.insert(ended, inputObject)
end)
`, "user_input_setup")

	key_down: sdl3.Event
	key_down.type = .KEY_DOWN
	key_down.key.scancode = .A
	engine_runtime.Environment_SetEvent(&environment, &script_vm, key_down)
	run_script(&script_vm, `
local input = game:GetService("UserInputService")
assert(#began == 1)
assert(began[1].UserInputType == Enum.UserInputType.Keyboard)
assert(began[1].UserInputState == Enum.UserInputState.Begin)
assert(began[1].KeyCode == Enum.KeyCode.A)
assert(input:IsKeyDown(Enum.KeyCode.A))
assert(#input:GetKeysPressed() == 1)
assert(input:GetKeysPressed()[1].KeyCode == Enum.KeyCode.A)
assert(input:GetLastInputType() == Enum.UserInputType.Keyboard)
`, "user_input_key_down")

	key_up: sdl3.Event
	key_up.type = .KEY_UP
	key_up.key.scancode = .A
	engine_runtime.Environment_SetEvent(&environment, &script_vm, key_up)
	run_script(&script_vm, `
local input = game:GetService("UserInputService")
assert(#ended == 1)
assert(ended[1].UserInputState == Enum.UserInputState.End)
assert(ended[1].KeyCode == Enum.KeyCode.A)
assert(not input:IsKeyDown(Enum.KeyCode.A))
assert(#input:GetKeysPressed() == 0)
`, "user_input_key_up")

	mouse_down: sdl3.Event
	mouse_down.type = .MOUSE_BUTTON_DOWN
	mouse_down.button.button = sdl3.BUTTON_LEFT
	mouse_down.button.x = 12
	mouse_down.button.y = 34
	engine_runtime.Environment_SetEvent(&environment, &script_vm, mouse_down)
	run_script(&script_vm, `
local input = game:GetService("UserInputService")
assert(#began == 2)
assert(began[2].UserInputType == Enum.UserInputType.MouseButton1)
assert(began[2].Position.X == 12 and began[2].Position.Y == 34)
assert(input:IsMouseButtonPressed(Enum.UserInputType.MouseButton1))
assert(#input:GetMouseButtonsPressed() == 1)
assert(input:GetMouseLocation() == Vector2.new(12, 34))
input.MouseDeltaSensitivity = 2
`, "user_input_mouse_down")

	motion: sdl3.Event
	motion.type = .MOUSE_MOTION
	motion.motion.x = 20
	motion.motion.y = 30
	motion.motion.xrel = 3.5
	motion.motion.yrel = -2.25
	engine_runtime.Environment_SetEvent(&environment, &script_vm, motion)

	input_descriptor := services.Find_Service(&environment.services, "UserInputService")
	assert(input_descriptor != nil && input_descriptor.object != nil)
	services.User_Input_Begin_Frame(cast(^services.UserInputService)input_descriptor.object)
	run_script(&script_vm, `
local input = game:GetService("UserInputService")
assert(#changed == 1)
assert(changed[1].UserInputType == Enum.UserInputType.MouseMovement)
assert(changed[1].UserInputState == Enum.UserInputState.Change)
assert(changed[1].Delta.X == 7 and changed[1].Delta.Y == -4.5)
assert(input:GetMouseLocation() == Vector2.new(20, 30))
assert(input:GetMouseDelta() == Vector2.new(7, -4.5))
assert(input:GetMouseDelta() == Vector2.new(7, -4.5))
`, "user_input_mouse_motion")

	services.User_Input_Begin_Frame(cast(^services.UserInputService)input_descriptor.object)
	run_script(&script_vm, `
assert(game:GetService("UserInputService"):GetMouseDelta() == Vector2.zero)
`, "user_input_next_frame")

	wheel: sdl3.Event
	wheel.type = .MOUSE_WHEEL
	wheel.wheel.x = -1
	wheel.wheel.y = 2
	wheel.wheel.mouse_x = 20
	wheel.wheel.mouse_y = 30
	engine_runtime.Environment_SetEvent(&environment, &script_vm, wheel)

	mouse_up: sdl3.Event
	mouse_up.type = .MOUSE_BUTTON_UP
	mouse_up.button.button = sdl3.BUTTON_LEFT
	mouse_up.button.x = 20
	mouse_up.button.y = 30
	engine_runtime.Environment_SetEvent(&environment, &script_vm, mouse_up)
	run_script(&script_vm, `
local input = game:GetService("UserInputService")
assert(#changed == 2)
assert(changed[2].UserInputType == Enum.UserInputType.MouseWheel)
assert(changed[2].Delta.X == -1 and changed[2].Delta.Z == 2)
assert(#ended == 2)
assert(ended[2].UserInputType == Enum.UserInputType.MouseButton1)
assert(not input:IsMouseButtonPressed(Enum.UserInputType.MouseButton1))
assert(#input:GetMouseButtonsPressed() == 0)
`, "user_input_mouse_end")

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("USER_INPUT_SERVICE_SMOKE_PASSED")
}
