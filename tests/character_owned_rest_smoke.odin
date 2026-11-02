package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run_owned_rest_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("character owned rest smoke failed")
	}
}

owned_rest_step :: proc(
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
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)


	run_owned_rest_script(
		&server_vm,
		`
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39237))
local floor = Instance.new("Part", workspace)
floor.Name = "Spawn"
floor.Size = vector.create(200, 1, 200)
floor.CFrame = CFrame.new(0, 0, 0)
floor.Anchored = true
`,
		"owned_rest_server_setup",
	)

	run_owned_rest_script(
		&client_vm,
		`
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39237))
`,
		"owned_rest_client_connect",
	)


	owned_rest_step(&server, &server_vm, &client, &client_vm, 180)


	run_owned_rest_script(
		&server_vm,
		`
local part = Instance.new("Part", workspace)
part.Name = "Meteor"
part.Anchored = false
part.CanCollide = true
part.Size = vector.create(3, 3, 3)
part.CFrame = CFrame.new(0, 60, 0)
`,
		"owned_rest_spawn_meteor",
	)


	owned_rest_step(&server, &server_vm, &client, &client_vm, 180)

	run_owned_rest_script(
		&client_vm,
		`
local local_player = game.Players.LocalPlayer
assert(local_player ~= nil and local_player.Character ~= nil)
local meteor = workspace:FindFirstChild("Meteor")
assert(meteor ~= nil, "meteor must replicate to the client")
assert(meteor:GetNetworkOwner() == local_player, "nearby meteor should be auto-owned by the local player")
assert(meteor.CFrame.Position.Y > 5.5, "meteor should be resting on the character, not the floor, y=" .. tostring(meteor.CFrame.Position.Y))
`,
		"owned_rest_client_resting",
	)
	run_owned_rest_script(
		&server_vm,
		`
local meteor = workspace:FindFirstChild("Meteor")
assert(meteor ~= nil, "meteor must exist on the server")
assert(meteor:GetNetworkOwner() ~= nil, "server must still hold the client owner for the meteor")
assert(meteor.CFrame.Position.Y > 5.5, "server should mirror the resting meteor, y=" .. tostring(meteor.CFrame.Position.Y))
`,
		"owned_rest_server_resting",
	)


	run_owned_rest_script(
		&client_vm,
		`
game:GetService("CharacterService"):SetMoveDirection(Vector3.new(1, 0, 0))
`,
		"owned_rest_client_walk",
	)

	owned_rest_step(&server, &server_vm, &client, &client_vm, 180)

	run_owned_rest_script(
		&client_vm,
		`
local local_player = game.Players.LocalPlayer
local meteor = workspace:FindFirstChild("Meteor")
local root = local_player.Character.RootPart
assert(meteor:GetNetworkOwner() == local_player, "meteor must still be client-owned after walking")
assert(meteor.CFrame.Position.Y < 3.5, "client-owned meteor should fall once the character leaves, y=" .. tostring(meteor.CFrame.Position.Y))
assert(root.CFrame.Position.X > 5, "character must have walked away, x=" .. tostring(root.CFrame.Position.X))
`,
		"owned_rest_client_fell",
	)
	run_owned_rest_script(
		&server_vm,
		`
local meteor = workspace:FindFirstChild("Meteor")
assert(meteor:GetNetworkOwner() ~= nil, "server must still hold the client owner for the meteor")
assert(meteor.CFrame.Position.Y < 3.5, "server should mirror the fallen meteor, y=" .. tostring(meteor.CFrame.Position.Y))
`,
		"owned_rest_server_mirrored",
	)

	run_owned_rest_script(
		&server_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"owned_rest_server_stop",
	)
	run_owned_rest_script(
		&client_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"owned_rest_client_stop",
	)
	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("CHARACTER_OWNED_REST_SMOKE_PASSED")
}
