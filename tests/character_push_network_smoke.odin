package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run_push_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("character push network smoke failed")
	}
}

push_step :: proc(
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


	run_push_script(
		&server_vm,
		`
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39235))
local floor = Instance.new("Part", workspace)
floor.Name = "Spawn"
floor.Size = vector.create(200, 1, 200)
floor.CFrame = CFrame.new(0, 0, 0)
floor.Anchored = true
local crate = Instance.new("Part", workspace)
crate.Name = "Crate"
crate.Anchored = false
crate.Size = vector.create(2, 2, 2)
crate.CFrame = CFrame.new(10, 1.5, 0)
`,
		"push_server_setup",
	)

	run_push_script(
		&client_vm,
		`
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39235))
`,
		"push_client_connect",
	)


	push_step(&server, &server_vm, &client, &client_vm, 180)

	run_push_script(
		&client_vm,
		`
local local_player = game.Players.LocalPlayer
assert(local_player ~= nil and local_player.Character ~= nil)
local crate = workspace:FindFirstChild("Crate")
assert(crate ~= nil, "crate must replicate to the client")
assert(crate:GetNetworkOwner() == local_player, "nearby crate should be auto-owned by the local player")
`,
		"push_client_auto_owned",
	)


	run_push_script(
		&client_vm,
		`
game:GetService("CharacterService"):SetMoveDirection(Vector3.new(1, 0, 0))
`,
		"push_client_walk",
	)

	push_step(&server, &server_vm, &client, &client_vm, 240)

	run_push_script(
		&client_vm,
		`
game:GetService("CharacterService"):SetMoveDirection(Vector3.new(0, 0, 0))
`,
		"push_client_stop",
	)


	run_push_script(
		&server_vm,
		`
local crate = workspace:FindFirstChild("Crate")
local owner = crate:GetNetworkOwner()
local character = game.Players:GetPlayers()[1].Character
local sx = character.RootPart.CFrame.Position.X
local cx = crate.CFrame.Position.X
assert(owner ~= nil, "server must still hold the client owner for the crate")
assert(cx > 12, "server should mirror the pushed crate, x=" .. tostring(cx))
assert(crate.CFrame.Position.Y > 0.9 and crate.CFrame.Position.Y < 2.5, "crate should stay on the floor")
assert(sx > 4, "character must have walked into the crate, x=" .. tostring(sx))
`,
		"push_server_mirrored",
	)

	run_push_script(
		&client_vm,
		`
local crate = workspace:FindFirstChild("Crate")
local root = game.Players.LocalPlayer.Character.RootPart
assert(crate.CFrame.Position.X > 12, "client observed the pushed crate")
-- A character standing on the floor rests at y=3.0; mounting the crate (top at
-- y=2.5) would lift the root to y=5.0, so below 3.5 means it stayed grounded.
assert(root.CFrame.Position.Y < 3.5, "character must not be lifted onto the crate, y=" .. tostring(root.CFrame.Position.Y))
`,
		"push_client_state",
	)

	run_push_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "push_server_stop")
	run_push_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "push_client_stop")
	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("CHARACTER_PUSH_NETWORK_SMOKE_PASSED")
}
