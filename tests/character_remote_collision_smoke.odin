package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run_block_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("character remote collision smoke failed")
	}
}

block_step :: proc(
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


	run_block_script(
		&server_vm,
		`
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39236))
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
-- Pin the crate to the server so automatic ownership never hands it to the
-- connecting client, leaving it as a remote/static obstacle.
crate:SetNetworkOwner()
`,
		"block_server_setup",
	)

	run_block_script(
		&client_vm,
		`
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39236))
`,
		"block_client_connect",
	)


	block_step(&server, &server_vm, &client, &client_vm, 180)

	run_block_script(
		&client_vm,
		`
local crate = workspace:FindFirstChild("Crate")
assert(crate ~= nil, "locked crate must replicate to the client")
assert(crate:GetNetworkOwner() == nil, "locked crate must stay server-owned")
`,
		"block_client_locked",
	)


	run_block_script(
		&client_vm,
		`
game:GetService("CharacterService"):SetMoveDirection(Vector3.new(1, 0, 0))
`,
		"block_client_walk",
	)

	block_step(&server, &server_vm, &client, &client_vm, 300)

	run_block_script(
		&client_vm,
		`
game:GetService("CharacterService"):SetMoveDirection(Vector3.new(0, 0, 0))
`,
		"block_client_stop",
	)

	run_block_script(
		&client_vm,
		`
local crate = workspace:FindFirstChild("Crate")
local root = game.Players.LocalPlayer.Character.RootPart
local rx = root.CFrame.Position.X
local ry = root.CFrame.Position.Y
assert(rx > 3, "character must have reached the crate, x=" .. tostring(rx))
-- The crate's near face is at x=9 and the capsule radius is 0.825, so a
-- correctly stopped character rests around x=8.175. Penetrating the crate
-- pushes x past 9, so require the capsule to stay short of the face.
assert(rx < 8.9, "character passed through the crate, x=" .. tostring(rx))
-- Standing on the floor the root rests at y=3.0; the crate top is at y=2.5 and
-- mounting it would lift the root to y=5.0. A root below 3.5 is on the floor.
assert(ry < 3.5, "character was lifted onto the crate, y=" .. tostring(ry))
`,
		"block_client_blocked",
	)

	run_block_script(
		&server_vm,
		`
local crate = workspace:FindFirstChild("Crate")
local x = crate.CFrame.Position.X
assert(x >= 9.5 and x < 10.5, "server-owned crate must not have moved, x=" .. tostring(x))
`,
		"block_server_intact",
	)

	run_block_script(
		&server_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"block_server_stop",
	)
	run_block_script(
		&client_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"block_client_stop",
	)
	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("CHARACTER_REMOTE_COLLISION_SMOKE_PASSED")
}
