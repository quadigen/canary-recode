package main

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"
import "core:math"

main :: proc() {
	movement := classes.MovementController {
		walk_speed              = 16,
		acceleration            = 40,
		air_control             = 0.25,
		speed_multiplier        = 1,
		deceleration_multiplier = 2,
		analog_input            = true,
		jump_buffer_duration    = 0,
		input_direction         = {0.5, 0, 0},
	}
	v, _ := classes.MovementController_Step(&movement, 0.1, false)
	assert(math.abs(v.x - 1) < 0.001)
	v, _ = classes.MovementController_Step(&movement, 1, true)
	assert(math.abs(v.x - 8) < 0.001)
	movement.input_direction = {}
	v, _ = classes.MovementController_Step(&movement, 0.05, true)
	assert(math.abs(v.x - 4) < 0.001)
	classes.MovementController_Queue_Jump(&movement)
	_, jumped := classes.MovementController_Step(&movement, 0.01)
	assert(jumped)
	_, jumped = classes.MovementController_Step(&movement, 0.01)
	assert(!jumped)
	rotation := classes.RotationController {
		yaw        = 170,
		target_yaw = -170,
		turn_rate  = 100,
	}
	yaw := classes.RotationController_Step(&rotation, 0.1)
	assert(math.abs(yaw - 180) < 0.001)
	controller := classes.CharacterController {
		knockback_mass = 20,
	}
	assert(classes.CharacterController_Apply_Impulse(&controller, {100, 40, 0}))
	assert(controller.knockback.x == 5 && controller.vertical_speed == 2)

	script_vm := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm)
	ok, err := vm.Run(
		&script_vm,
		`
local controller = Instance.new("CharacterController")
local movement = Instance.new("MovementController", controller)
local rotation = Instance.new("RotationController", controller)
local collision = Instance.new("CollisionController", controller)
local ground = Instance.new("GroundDetector", controller)
local motor = Instance.new("CharacterMotor", controller)
assert(math.abs(controller.Gravity - 196.2) < 0.001)
assert(movement.Acceleration == 160 and movement.UseAutomaticAcceleration)
assert(rotation.TurnRate == 720 and rotation.FaceMovement)
assert(collision.StepHeight == 0.5 and collision.SweepIterations == 4)
assert(math.abs(ground.SnapDistance - 0.6) < 0.001)
assert(motor.StepsPerSecond == 120)
controller.Gravity = 80
controller.JumpEnabled = false
movement.UseAutomaticAcceleration = false
movement.Acceleration = 50
movement.AnalogInput = true
rotation.FaceMovement = false
rotation.TargetYaw = -90
collision.StepHeight = 0
collision.SweepIterations = 100
ground.SnapDistance = 0.2
motor.StepsPerSecond = 0
assert(collision.SweepIterations == 16 and motor.StepsPerSecond == 15)
assert(not pcall(function() controller.Gravity = 0/0 end))
assert(controller.Gravity == 80)
local clone = controller:Clone()
assert(clone.Gravity == 80 and clone.JumpEnabled == false)
assert(clone:FindFirstChildOfClass("MovementController").Acceleration == 50)
assert(clone:FindFirstChildOfClass("RotationController").TargetYaw == -90)
assert(clone:FindFirstChildOfClass("CollisionController").SweepIterations == 16)
assert(math.abs(clone:FindFirstChildOfClass("GroundDetector").SnapDistance - 0.2) < 0.001)
assert(clone:FindFirstChildOfClass("CharacterMotor").StepsPerSecond == 15)
clone:Destroy()
controller:Destroy()
`,
		"character_tuning",
	)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("character tuning smoke failed")
	}
	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&env)

	server_vm := vm.New()
	client_vm := vm.New()
	server, client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)
	run_tuning(
		&server_vm,
		`
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39191))
local floor = Instance.new("Part", workspace)
floor.Name = "Spawn"
floor.Size = Vector3.new(500, 1, 500)
floor.CFrame = CFrame.new(0, 4, 0)
floor.Anchored = true
`,
	)
	run_tuning(
		&client_vm,
		`assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39191))`,
	)
	for _ in 0 ..< 180 {
		engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&client, &client_vm, 1.0 / 60.0)
	}
	run_tuning(
		&server_vm,
		`
local char = game:GetService("Players"):GetPlayers()[1].Character
local ctrl = char:FindFirstChildOfClass("CharacterController")
ctrl.Gravity = 80
ctrl.JumpEnabled = false
local m = ctrl:FindFirstChildOfClass("MovementController")
m.SpeedMultiplier = 0.5
m.AnalogInput = true
m.UseAutomaticAcceleration = false
m.Acceleration = 90
ctrl:FindFirstChildOfClass("RotationController").TurnRate = 300
ctrl:FindFirstChildOfClass("CollisionController").StepHeight = 0
ctrl:FindFirstChildOfClass("GroundDetector").SnapDistance = 0.25
char:FindFirstChildOfClass("CharacterMotor").StepsPerSecond = 60
`,
	)
	for _ in 0 ..< 90 {
		engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&client, &client_vm, 1.0 / 60.0)
	}
	run_tuning(
		&client_vm,
		`
local char = game:GetService("Players").LocalPlayer.Character
local ctrl = char:FindFirstChildOfClass("CharacterController")
local m = ctrl:FindFirstChildOfClass("MovementController")
assert(ctrl.Gravity == 80 and not ctrl.JumpEnabled, "replicated character tuning")
assert(m.SpeedMultiplier == 0.5 and m.AnalogInput and m.Acceleration == 90 and not m.UseAutomaticAcceleration, "replicated movement tuning")
assert(ctrl:FindFirstChildOfClass("RotationController").TurnRate == 300)
assert(ctrl:FindFirstChildOfClass("CollisionController").StepHeight == 0)
assert(ctrl:FindFirstChildOfClass("GroundDetector").SnapDistance == 0.25)
assert(char:FindFirstChildOfClass("CharacterMotor").StepsPerSecond == 60)
start_position = char.RootPart.CFrame.Position
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(0.5, 0, 0)))
assert(game:GetService("CharacterService"):Jump())
`,
	)
	for _ in 0 ..< 60 {
		engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&client, &client_vm, 1.0 / 60.0)
	}
	run_tuning(
		&client_vm,
		`
local position = game:GetService("Players").LocalPlayer.Character.RootPart.CFrame.Position
local delta = position.X - start_position.X
assert(delta > 2 and delta < 5.5, "analog movement delta " .. tostring(delta))
assert(math.abs(position.Y - start_position.Y) < 0.5, "disabled jump moved character vertically")
game:GetService("ReplicatorService"):Stop()
`,
	)
	run_tuning(&server_vm, `game:GetService("ReplicatorService"):Stop()`)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&client)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("character_tuning_smoke PASSED")
}

run_tuning :: proc(script_vm: ^vm.VM, source: string) {
	ok, err := vm.Run(script_vm, source, "character_tuning_network")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("character tuning network smoke failed")
	}
}
