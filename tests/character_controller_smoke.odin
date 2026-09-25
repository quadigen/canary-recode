package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run_cc :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("character controller smoke failed")
	}
}

cc_step :: proc(env: ^engine_runtime.Environment, script_vm: ^vm.VM, frames: int) {
	for _ in 0..<frames {
		engine_runtime.Environment_Render_Step(env, script_vm, 1.0 / 60.0)
	}
}

cc_step_pair :: proc(server: ^engine_runtime.Environment, server_vm: ^vm.VM, client: ^engine_runtime.Environment, client_vm: ^vm.VM, frames: int) {
	for _ in 0..<frames {
		engine_runtime.Environment_Render_Step(server, server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(client, client_vm, 1.0 / 60.0)
	}
}

main :: proc() {
	script_vm := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm)
	run_cc(&script_vm, `
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39187))
local m = Instance.new("Model", workspace)
Instance.new("StateMachine", m)
Instance.new("CharacterAnimator", m)
Instance.new("CharacterInput", m)
Instance.new("CharacterCamera", m)
assert(m:FindFirstChildOfClass("StateMachine"))
assert(m:FindFirstChildOfClass("CharacterAnimator"))
assert(m:FindFirstChildOfClass("CharacterInput"))
assert(m:FindFirstChildOfClass("CharacterCamera"))
m:Destroy()
`, "character_controller_part1")
	cc_step(&env, &script_vm, 30)
	run_cc(&script_vm, `game:GetService("ReplicatorService"):Stop()`, "character_controller_part1_stop")
	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&env)

	// PART 2: controller facade drives the simulated character (client-authoritative).
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)
	run_cc(&server_vm, `
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39187))
assert(IsServer and not IsClient)
local floor = Instance.new("Part", workspace)
floor.Name = "Spawn"
floor.Size = vector.create(500, 1, 500)
floor.CFrame = CFrame.new(0, 4, 0)
floor.Anchored = true
`, "cc_part2_server_start")
	run_cc(&client_vm, `
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39187))
assert(IsClient and not IsServer)
`, "cc_part2_client_start")
	cc_step_pair(&server, &server_vm, &client, &client_vm, 180)
	run_cc(&server_vm, `
local player = game:GetService("Players"):GetPlayers()[1]
assert(player.Character and player.Character.RootPart)
assert(player.Character:FindFirstChildOfClass("CharacterController"))
assert(player.Character:FindFirstChildOfClass("CharacterMotor"))
`, "cc_part2_server_probe")
	run_cc(&client_vm, `
local players = game:GetService("Players")
local char = players.LocalPlayer.Character
assert(char and char.RootPart)
local ctrl
for _, c in ipairs(char:GetChildren()) do
    if c:IsA("CharacterController") then ctrl = c end
end
assert(ctrl, "client controller missing")
assert(math.abs(ctrl.WalkSpeed - 16) < 0.001, "walkSpeed=" .. tostring(ctrl.WalkSpeed))
assert(math.abs(ctrl.JumpHeight - 7.2) < 0.001, "jumpHeight=" .. tostring(ctrl.JumpHeight))
assert(ctrl.AutoRotate == true, "autoRotate")
assert(ctrl.MaxSlopeAngle == 89, "maxSlopeAngle")
assert(ctrl:FindFirstChildOfClass("MovementController"))
assert(ctrl:FindFirstChildOfClass("GroundDetector"))
assert(ctrl:FindFirstChildOfClass("RotationController"))
assert(char:FindFirstChildOfClass("CharacterMotor"))
cc = cc or {}
cc.sm = ctrl:FindFirstChildOfClass("StateMachine")
assert(cc.sm, "client state machine missing")
cc.rest_y = char.RootPart.CFrame.Position.Y
assert(cc.sm:GetState() == "Idle", "initial state " .. tostring(cc.sm:GetState()))
`, "cc_part2_client_probe")
	run_cc(&client_vm, `
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(1, 0, 0)))
`, "cc_part2_move")
	cc_step_pair(&server, &server_vm, &client, &client_vm, 60)
	run_cc(&client_vm, `
local x = game:GetService("Players").LocalPlayer.Character.RootPart.CFrame.Position.X
assert(x > 10, "moved x=" .. tostring(x))
assert(cc.sm:GetState() == "Running", "moving state " .. tostring(cc.sm:GetState()))
`, "cc_part2_moved")
	run_cc(&client_vm, `
cc.start_y = game:GetService("Players").LocalPlayer.Character.RootPart.CFrame.Position.Y
cc.peak_y = cc.start_y
assert(game:GetService("CharacterService"):Jump())
`, "cc_part2_jump")
	for _ in 0..<6 {
		cc_step_pair(&server, &server_vm, &client, &client_vm, 5)
		run_cc(&client_vm, `
cc.peak_y = math.max(cc.peak_y, game:GetService("Players").LocalPlayer.Character.RootPart.CFrame.Position.Y)
`, "cc_part2_jump_peak")
	}
	run_cc(&client_vm, `
local gain = cc.peak_y - cc.start_y
assert(gain >= 6 and gain <= 8, "jump apex gain " .. tostring(gain))
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(0, 0, 0)))
`, "cc_part2_jump_apex")
	cc_step_pair(&server, &server_vm, &client, &client_vm, 120)
	run_cc(&client_vm, `
local y = game:GetService("Players").LocalPlayer.Character.RootPart.CFrame.Position.Y
assert(math.abs(y - cc.rest_y) < 0.5, "rest y=" .. tostring(y) .. " rest_y=" .. tostring(cc.rest_y))
assert(cc.sm:GetState() == "Idle", "landed state " .. tostring(cc.sm:GetState()))
`, "cc_part2_landed")
	run_cc(&server_vm, `
local player = game:GetService("Players"):GetPlayers()[1]
local x = player.Character.RootPart.CFrame.Position.X
assert(x > 10, "server observed move x=" .. tostring(x))
`, "cc_part2_server_observe")

	// PART 3: kinematic capsule collision (client drives, server observes).
	run_cc(&server_vm, `
cc3 = cc3 or {}
local workspace = game:GetService("Workspace")
local wall = Instance.new("Part", workspace)
wall.Name = "Wall"
wall.Size = Vector3.new(2, 12, 200)
wall.CFrame = CFrame.new(40, 6, 0)
wall.Anchored = true
`, "cc_part3_server_wall")
	cc_step_pair(&server, &server_vm, &client, &client_vm, 30)
	run_cc(&client_vm, `
local char = game:GetService("Players").LocalPlayer.Character
local ctrl
for _, c in ipairs(char:GetChildren()) do
    if c:IsA("CharacterController") then ctrl = c end
end
cc.ctrl = ctrl
cc.wall_touched = false
local wall = workspace:FindFirstChild("Wall")
assert(wall, "wall did not replicate before client script")
wall.Touched:Connect(function(other)
    if other == char.RootPart then cc.wall_touched = true end
end)
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(1, 0, 1)))
`, "cc_part3_client_wall")
	cc_step_pair(&server, &server_vm, &client, &client_vm, 150)
	run_cc(&server_vm, `
local root = game:GetService("Players"):GetPlayers()[1].Character.RootPart
cc3.wall_x1 = root.CFrame.Position.X
cc3.wall_z1 = root.CFrame.Position.Z
`, "cc_part3_wall_read1")
	cc_step_pair(&server, &server_vm, &client, &client_vm, 30)
	run_cc(&server_vm, `
local root = game:GetService("Players"):GetPlayers()[1].Character.RootPart
local dx = math.abs(root.CFrame.Position.X - cc3.wall_x1)
local dz = root.CFrame.Position.Z - cc3.wall_z1
assert(dx < 0.05, "wall did not block x, dx=" .. tostring(dx))
assert(dz > 1.5, "z stalled, dz=" .. tostring(dz))
`, "cc_part3_wall_assert")
	run_cc(&client_vm, `
assert(cc.wall_touched, "capsule contact with wall never fired")
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(0, 0, 0)))
for _, p in ipairs(game:GetService("Players").LocalPlayer.Character:GetChildren()) do
    if p:IsA("Part") then p.CFrame = CFrame.new(0, cc.rest_y, 0) end
end
`, "cc_part3_step_prepare")
	run_cc(&server_vm, `
local workspace = game:GetService("Workspace")
workspace:FindFirstChild("Wall"):Destroy()
local step = Instance.new("Part", workspace)
step.Name = "Step"
step.Size = Vector3.new(6, 0.5, 6)
step.CFrame = CFrame.new(5, 4.75, 0)
step.Anchored = true
`, "cc_part3_server_step")
	cc_step_pair(&server, &server_vm, &client, &client_vm, 20)
	run_cc(&server_vm, `
local root = game:GetService("Players"):GetPlayers()[1].Character.RootPart
cc3.step_y0 = root.CFrame.Position.Y
cc3.step_peak = cc3.step_y0
`, "cc_part3_step_base")
	run_cc(&client_vm, `
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(1, 0, 0)))
`, "cc_part3_step_move")
	for _ in 0..<4 {
		cc_step_pair(&server, &server_vm, &client, &client_vm, 20)
		run_cc(&server_vm, `
cc3.step_peak = math.max(cc3.step_peak, game:GetService("Players"):GetPlayers()[1].Character.RootPart.CFrame.Position.Y)
`, "cc_part3_step_peak")
	}
	run_cc(&server_vm, `
local root = game:GetService("Players"):GetPlayers()[1].Character.RootPart
local rise = cc3.step_peak - cc3.step_y0
assert(rise >= 0.3, "no step-up, rise=" .. tostring(rise))
assert(root.CFrame.Position.X > 4, "character never crossed the step x=" .. tostring(root.CFrame.Position.X))
`, "cc_part3_step_assert")
	run_cc(&client_vm, `
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(0, 0, 0)))
for _, p in ipairs(game:GetService("Players").LocalPlayer.Character:GetChildren()) do
    if p:IsA("Part") then p.CFrame = CFrame.new(0, cc.rest_y, 0) end
end
cc.ctrl.MaxSlopeAngle = 45
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(1, 0, 0)))
`, "cc_part3_slope_prepare")
	run_cc(&server_vm, `
local workspace = game:GetService("Workspace")
local old = workspace:FindFirstChild("Step")
if old then old:Destroy() end
old = workspace:FindFirstChild("Ramp")
if old then old:Destroy() end
local ramp = Instance.new("Part", workspace)
ramp.Name = "Ramp"
ramp.Size = Vector3.new(6, 1, 6)
ramp.CFrame = CFrame.new(16, 5, 0) * CFrame.Angles(0, 0, math.rad(60))
ramp.Anchored = true
`, "cc_part3_server_ramp")
	cc_step_pair(&server, &server_vm, &client, &client_vm, 20)
	run_cc(&server_vm, `
local root = game:GetService("Players"):GetPlayers()[1].Character.RootPart
cc3.slope_y0 = root.CFrame.Position.Y
cc3.slope_peak = cc3.slope_y0
`, "cc_part3_slope_base")
	cc_step_pair(&server, &server_vm, &client, &client_vm, 60)
	run_cc(&server_vm, `
local root = game:GetService("Players"):GetPlayers()[1].Character.RootPart
cc3.slope_x1 = root.CFrame.Position.X
`, "cc_part3_slope_read1")
	cc_step_pair(&server, &server_vm, &client, &client_vm, 30)
	run_cc(&server_vm, `
local root = game:GetService("Players"):GetPlayers()[1].Character.RootPart
cc3.slope_peak = math.max(cc3.slope_peak, root.CFrame.Position.Y)
local dx = math.abs(root.CFrame.Position.X - cc3.slope_x1)
assert(cc3.slope_peak - cc3.slope_y0 < 0.8, "slope was climbed, rise=" .. tostring(cc3.slope_peak - cc3.slope_y0))
assert(dx < 0.05, "slope did not stop the character dx=" .. tostring(dx))`, "cc_part3_slope_assert")

	// PART 4: a slope within MaxSlopeAngle is climbed. Regression for characters
	// that could walk down slopes but were stopped dead at the base of any ramp.
	run_cc(&client_vm, `
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(0, 0, 0)))
for _, p in ipairs(game:GetService("Players").LocalPlayer.Character:GetChildren()) do
    if p:IsA("Part") then p.CFrame = CFrame.new(0, cc.rest_y, 0) end
end
cc.ctrl.MaxSlopeAngle = 45
`, "cc_part4_prepare")
	run_cc(&server_vm, `
local workspace = game:GetService("Workspace")
local old = workspace:FindFirstChild("Ramp")
if old then old:Destroy() end
local ramp = Instance.new("Part", workspace)
ramp.Name = "Ramp"
ramp.Anchored = true
ramp.Size = Vector3.new(16, 1, 10)
ramp.CFrame = CFrame.new(13, 4, 0) * CFrame.Angles(0, 0, math.rad(20))
`, "cc_part4_server_ramp")
	cc_step_pair(&server, &server_vm, &client, &client_vm, 20)
	run_cc(&server_vm, `
local root = game:GetService("Players"):GetPlayers()[1].Character.RootPart
cc4 = cc4 or {}
cc4.y0 = root.CFrame.Position.Y
cc4.peak = cc4.y0
cc4.x0 = root.CFrame.Position.X
`, "cc_part4_base")
	run_cc(&client_vm, `
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(1, 0, 0)))
`, "cc_part4_move")
	for _ in 0..<60 {
		cc_step_pair(&server, &server_vm, &client, &client_vm, 5)
		run_cc(&server_vm, `
local root = game:GetService("Players"):GetPlayers()[1].Character.RootPart
cc4.peak = math.max(cc4.peak, root.CFrame.Position.Y)
`, "cc_part4_peak")
	}
	run_cc(&server_vm, `
local root = game:GetService("Players"):GetPlayers()[1].Character.RootPart
local rise = cc4.peak - cc4.y0
assert(rise > 1.5, "walkable slope was not climbed, rise=" .. tostring(rise))
assert(root.CFrame.Position.X > cc4.x0 + 6, "character stalled before the ramp, x=" .. tostring(root.CFrame.Position.X))
`, "cc_part4_assert")
	run_cc(&client_vm, `
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(0, 0, 0)))
`, "cc_part4_release")
	cc_step_pair(&server, &server_vm, &client, &client_vm, 40)

	// PART 5: Humanoid wrapper (health, state mirror, WalkTo, death freeze).
	run_cc(&client_vm, `
cc5 = cc5 or {}
local char = game:GetService("Players").LocalPlayer.Character
for _, p in ipairs(char:GetChildren()) do
    if p:IsA("Part") then p.CFrame = CFrame.new(0, cc.rest_y, 0) end
end
cc5.hum = char:FindFirstChildOfClass("Humanoid")
assert(cc5.hum, "character has no Humanoid")
assert(cc5.hum.MaxHealth == 100, "maxHealth=" .. tostring(cc5.hum.MaxHealth))
assert(cc5.hum.Health == 100, "health=" .. tostring(cc5.hum.Health))
assert(cc5.hum.HumanoidStateType == "Idle", "initial state " .. tostring(cc5.hum.HumanoidStateType))
assert(cc5.hum:GetState() == "Idle", "getState " .. tostring(cc5.hum:GetState()))
cc5.hit = nil
cc5.hum.HealthChanged:Connect(function(v) cc5.hit = v end)
cc5.hum:TakeDamage(25)
assert(cc5.hum.Health == 75, "health after damage " .. tostring(cc5.hum.Health))
assert(cc5.hit == 75, "HealthChanged fired with " .. tostring(cc5.hit))
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(1, 0, 0)))
`, "cc_part5_humanoid_probe")
	cc_step_pair(&server, &server_vm, &client, &client_vm, 40)
	run_cc(&client_vm, `
assert(cc5.hum.HumanoidStateType == "Running", "moving state " .. tostring(cc5.hum.HumanoidStateType))
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(0, 0, 0)))
`, "cc_part5_state_running")
	cc_step_pair(&server, &server_vm, &client, &client_vm, 30)
	run_cc(&client_vm, `
assert(cc5.hum.HumanoidStateType == "Idle", "stopped state " .. tostring(cc5.hum.HumanoidStateType))
for _, p in ipairs(game:GetService("Players").LocalPlayer.Character:GetChildren()) do
    if p:IsA("Part") then p.CFrame = CFrame.new(0, cc.rest_y, 0) end
end
cc5.hum:WalkTo(Vector3.new(6, cc.rest_y, 0))
`, "cc_part5_walkto_start")
	cc_step_pair(&server, &server_vm, &client, &client_vm, 150)
	run_cc(&server_vm, `
local root = game:GetService("Players"):GetPlayers()[1].Character.RootPart
local dx = math.abs(root.CFrame.Position.X - 6)
local dz = math.abs(root.CFrame.Position.Z - 0)
cc5 = cc5 or {}
cc5.walk_x = root.CFrame.Position.X
cc5.walk_z = root.CFrame.Position.Z
assert(root.CFrame.Position.X > 4, "walkto never moved x=" .. tostring(root.CFrame.Position.X))
assert(dx < 1.5, "walkto did not arrive dx=" .. tostring(dx))
assert(dz < 1.5, "walkto drifted dz=" .. tostring(dz))
`, "cc_part5_walkto_arrive")
	cc_step_pair(&server, &server_vm, &client, &client_vm, 30)
	run_cc(&server_vm, `
local root = game:GetService("Players"):GetPlayers()[1].Character.RootPart
local dx = root.CFrame.Position.X - cc5.walk_x
local dz = root.CFrame.Position.Z - cc5.walk_z
assert(math.abs(dx) + math.abs(dz) < 0.5, "walkto kept moving after arrival dx=" .. tostring(dx) .. " dz=" .. tostring(dz))
`, "cc_part5_walkto_stopped")
	run_cc(&client_vm, `
cc5.frozen_x = game:GetService("Players").LocalPlayer.Character.RootPart.CFrame.Position.X
cc5.frozen_y = game:GetService("Players").LocalPlayer.Character.RootPart.CFrame.Position.Y
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(1, 0, 0)))
cc5.hum:TakeDamage(75)
`, "cc_part5_death_damage")
	cc_step_pair(&server, &server_vm, &client, &client_vm, 10)
	run_cc(&client_vm, `
assert(cc5.hum.Health == 0, "health after kill " .. tostring(cc5.hum.Health))
assert(cc5.hum:GetState() == "Dead", "state after kill " .. tostring(cc5.hum:GetState()))
assert(cc5.hum.HumanoidStateType == "Dead", "type after kill " .. tostring(cc5.hum.HumanoidStateType))
`, "cc_part5_dead_state")
	cc_step_pair(&server, &server_vm, &client, &client_vm, 60)
	run_cc(&client_vm, `
local root = game:GetService("Players").LocalPlayer.Character.RootPart
local dx = math.abs(root.CFrame.Position.X - cc5.frozen_x)
local dy = math.abs(root.CFrame.Position.Y - cc5.frozen_y)
assert(dx + dy < 0.05, "death did not freeze position dx=" .. tostring(dx) .. " dy=" .. tostring(dy))
`, "cc_part5_death_frozen")

	run_cc(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "cc_part2_client_stop")
	cc_step_pair(&server, &server_vm, &client, &client_vm, 30)
	run_cc(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "cc_part2_server_stop")
	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("CHARACTER_CONTROLLER_SMOKE_PASSED")
}