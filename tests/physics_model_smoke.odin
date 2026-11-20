package main

import kineffi "../src/engine/bindings"
import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {fmt.eprintln(name, err); panic("physics model smoke failed")}
}

step_pair :: proc(
	server: ^engine_runtime.Environment,
	server_vm: ^vm.VM,
	client: ^engine_runtime.Environment,
	client_vm: ^vm.VM,
	frames: int,
) {
	for _ in 0 ..< frames {
		engine_runtime.Environment_Render_Step(server, server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(client, client_vm, 1.0 / 60.0)
	}
}

main :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server, client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)
	run_script(
		&server_vm,
		`
local r = game:GetService("ReplicatorService")
game:GetService("CharacterService").CharacterAutoLoads = false
assert(r:StartServer("127.0.0.1", 39362))
local model = Instance.new("PhysicsModel", workspace)
model.Name = "Ship"
assert(model:IsA("Model") and model.ServerAuthoritative)
model.GravityScale = 0
model.AerodynamicsEnabled = false
model.DragMultiplier = 0.5
model.LiftMultiplier = 1.7
model.NetworkUpdateRate = 20
model.InterpolationDelay = 0.05
model.MaxExtrapolationTime = 0.15
local part = Instance.new("Part", model)
part.Name = "Hull"
part.Size = Vector3.new(4, 2, 3)
part.CFrame = CFrame.new(0, 50, 0)
part.Anchored = false
model.PrimaryPart = part
local clone = model:Clone()
assert(clone:IsA("PhysicsModel") and clone.GravityScale == 0 and clone.PrimaryPart == clone.Hull)
assert(clone.NetworkUpdateRate == 20 and not clone.AerodynamicsEnabled)
clone:Destroy()
`,
		"server_setup",
	)
	// Round-trip the model without going through network replication.
	source_workspace := services.Ensure_Service(&server.services, "Workspace")
	ship := classes.Find_First_Child(source_workspace, "Ship")
	save_error := serializer.Serialize_To_File(
		&server.classes,
		server_vm.L,
		ship,
		"build/physics-model-smoke.kine",
	)
	assert(serializer.Error_Is_None(save_error))
	serializer.Error_Delete(&save_error)
	loaded, load_error := serializer.Deserialize_From_File(
		&server.classes,
		server_vm.L,
		nil,
		"build/physics-model-smoke.kine",
	)
	assert(loaded != nil && serializer.Error_Is_None(load_error))
	serializer.Error_Delete(&load_error)
	assert(classes.Is_A(loaded, "PhysicsModel"))
	loaded_model := cast(^classes.PhysicsModel)loaded
	assert(
		loaded_model.gravity_scale == 0 &&
		loaded_model.network_update_rate == 20 &&
		!loaded_model.aerodynamics_enabled,
	)
	assert(loaded_model.primary_part == classes.Find_First_Child(loaded, "Hull"))
	classes.Destroy_Hierarchy(loaded)
	run_script(
		&client_vm,
		`assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1",39362))`,
		"client_connect",
	)
	step_pair(&server, &server_vm, &client, &client_vm, 120)
	run_script(
		&client_vm,
		`
local m = workspace:FindFirstChild("Ship")
assert(m and m:IsA("PhysicsModel") and m.PrimaryPart == m.Hull)
assert(m.GravityScale == 0 and m.ServerAuthoritative and not m.AerodynamicsEnabled)
assert(math.abs(m.DragMultiplier - 0.5) < 0.001 and math.abs(m.LiftMultiplier - 1.7) < 0.001)
assert(m.NetworkUpdateRate == 20 and m.ReplicateVelocity)
assert(math.abs(m.Hull.Position.Y - 50) < 0.1)
assert(not pcall(function() m.Hull:SetNetworkOwner(game.Players.LocalPlayer) end))
`,
		"client_settings",
	)
	run_script(
		&server_vm,
		`
local p = workspace.Ship.Hull
assert(not pcall(function() p:SetNetworkOwner(game.Players:GetPlayers()[1]) end))
p.AssemblyLinearVelocity = Vector3.new(12, 0, 0)
p.AssemblyAngularVelocity = Vector3.new(0, 2, 0)
`,
		"server_motion",
	)
	step_pair(&server, &server_vm, &client, &client_vm, 120)
	run_script(
		&client_vm,
		`
local p = workspace.Ship.Hull
assert(p.Position.X > 10 and math.abs(p.Position.Y - 50) < 0.1, tostring(p.Position))
assert(p.AssemblyLinearVelocity.X > 1 and p.AssemblyAngularVelocity.Y > 0.1)

`,
		"client_motion",
	)
	client_rep := cast(^services.ReplicatorService)services.Ensure_Service(
		&client.services,
		"ReplicatorService",
	)
	samples_found := false
	for entity in client_rep.entity_list {
		if entity.object != nil && entity.object.name == "Hull" {
			samples_found = true
			assert(len(entity.samples) > 0)
			sample := entity.samples[len(entity.samples) - 1]
			assert(
				sample.has_velocity &&
				sample.linear_velocity.x > 1 &&
				sample.angular_velocity.y > 0.1,
			)
		}
	}
	assert(samples_found)
	run_script(&server_vm, `workspace.Ship.GravityScale = 0.5`, "gravity_change")
	step_pair(&server, &server_vm, &client, &client_vm, 20)
	run_script(
		&client_vm,
		`assert(workspace.Ship.GravityScale == 0.5 and workspace.Ship.Hull.Position.Y < 50)`,
		"client_gravity",
	)
	physics := cast(^services.Physics)services.Ensure_Service(&client.services, "Physics")
	found := false
	for body in physics.bodies {
		if body.object != nil && body.object.name == "Hull" {
			found = true
			part := cast(^classes.Part)body.object
			position: kineffi.JPH_RVec3
			rotation: kineffi.JPH_Quat
			kineffi.JPH_BodyInterface_GetPositionAndRotation(
				physics.system.body_interface,
				body.body_id,
				&position,
				&rotation,
			)
			assert(body.remote && abs(position.x - part.position.x) < 0.01)
		}
	}
	assert(found)
	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "stop_client")
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "stop_server")
	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("PHYSICS_MODEL_SMOKE_PASSED")
}
