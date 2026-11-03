package main

import enums "../src/engine/enum"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"

run_script :: proc(script_vm: ^vm.VM, source: string) {
	ok, err := vm.Run(script_vm, source, "constraint_car_turn_smoke")
	assert(ok, err)
}

step_frames :: proc(environment: ^engine_runtime.Environment, script_vm: ^vm.VM, count: int) {
	for _ in 0..<count {
		engine_runtime.Environment_Update_Step(environment, script_vm, 1.0 / 60.0)
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)
	defer {
		vm.Close(&script_vm)
		engine_runtime.Environment_Destroy(&environment)
	}

	source, err := os.read_entire_file("examples/constraint_car.luau", context.allocator)
	assert(err == nil)
	defer delete(source)
	run_script(&script_vm, string(source))
	run_script(&script_vm, `
car = workspace.ConstraintCar
maxAxleTilt = 0
game:GetService("RunService").Heartbeat:Connect(function()
	maxAxleTilt = math.max(maxAxleTilt,
		math.abs(car.FrontLeftWheel.CFrame.UpVector.Y),
		math.abs(car.FrontRightWheel.CFrame.UpVector.Y))
end)
`)

	input := cast(^services.UserInputService)services.Ensure_Service(&environment.services, "UserInputService")
	step_frames(&environment, &script_vm, 120)
	append(&input.keys_down, enums.KeyCode.W)
	step_frames(&environment, &script_vm, 65)
	run_script(&script_vm, `beforeTurn = car.Chassis.CFrame`)

	append(&input.keys_down, enums.KeyCode.D)
	step_frames(&environment, &script_vm, 120)
	run_script(&script_vm, `
assert(car.Chassis.CFrame.LookVector:Dot(beforeTurn.RightVector) > 0.3, "car should turn right")
beforeTurn = car.Chassis.CFrame
`)

	input.keys_down[1] = enums.KeyCode.A
	step_frames(&environment, &script_vm, 120)
	run_script(&script_vm, `
assert(car.Chassis.CFrame.LookVector:Dot(beforeTurn.RightVector) < -0.3, "car should turn left")
assert(maxAxleTilt < 0.30, "front wheels must stay upright throughout the turns: " .. tostring(maxAxleTilt))
car:Destroy()
workspace.TestFloor:Destroy()
`)
	fmt.println("CONSTRAINT_CAR_TURN_SMOKE_PASSED")
}
