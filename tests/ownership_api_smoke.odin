package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_own :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("ownership api smoke failed")
	}
}

own_step :: proc(server: ^engine_runtime.Environment, server_vm: ^vm.VM, client: ^engine_runtime.Environment, client_vm: ^vm.VM, frames: int) {
	for _ in 0..<frames {
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

	run_own(&server_vm, `
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39233))
local base = Instance.new("Part", workspace)
base.Name = "Base"
base.Anchored = true
base.Size = vector.create(100, 2, 100)
base.CFrame = CFrame.new(0, -1, 0)
local platform = Instance.new("Part", workspace)
platform.Name = "Platform"
platform.Anchored = true
platform.Size = vector.create(4, 1, 4)
platform.CFrame = CFrame.new(0, 10, 0)
local crate = Instance.new("Part", workspace)
crate.Name = "Crate"
crate.Anchored = false
crate.Size = vector.create(1, 1, 1)
crate.CFrame = CFrame.new(0, 3, 0)
`, "own_server_setup")

	run_own(&client_vm, `
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39233))
`, "own_client_connect")

	own_step(&server, &server_vm, &client, &client_vm, 90)

	// Initially nothing is owned: the crate belongs to the server.
	run_own(&server_vm, `
local crate = workspace:FindFirstChild("Crate")
local platform = workspace:FindFirstChild("Platform")
assert(crate ~= nil, "crate should exist")
assert(crate:GetNetworkOwner() == nil, "crate should start server-owned")
assert(platform:GetNetworkOwner() == nil, "anchored platform has no owner")
`, "own_initial")

	// The client requests ownership of the crate.
	run_own(&client_vm, `
local local_player = game.Players.LocalPlayer
assert(local_player ~= nil, "player should have a character owner id")
local ok, err = pcall(function()
	workspace:FindFirstChild("Crate"):SetNetworkOwner(local_player)
end)
assert(ok, "SetNetworkOwner failed: " .. tostring(err))
assert(workspace:FindFirstChild("Crate"):GetNetworkOwner() == local_player, "optimistic owner should be the local player")
`, "own_client_claim")

	own_step(&server, &server_vm, &client, &client_vm, 10)

	// The server accepted the request and broadcasts it back.
	run_own(&server_vm, `
local owner = workspace:FindFirstChild("Crate"):GetNetworkOwner()
assert(owner ~= nil and owner == game.Players:GetPlayers()[1], "server should assign the crate to Player1")
`, "own_server_assigned")

	run_own(&client_vm, `
assert(workspace:FindFirstChild("Crate"):GetNetworkOwner() == game.Players.LocalPlayer, "client owner after broadcast")
`, "own_client_broadcast")

	// The owner moves the crate; the server mirrors it.
	run_own(&client_vm, `
local crate = workspace:FindFirstChild("Crate")
crate.CFrame = crate.CFrame + Vector3.new(6, 0, 0)
`, "own_client_move")

	own_step(&server, &server_vm, &client, &client_vm, 40)

	run_own(&server_vm, `
local x = workspace:FindFirstChild("Crate").CFrame.Position.X
assert(x > 5.5, "server should mirror the client-owned crate position x=" .. tostring(x))
`, "own_server_mirrored")

	// Anchored parts reject explicit ownership changes (Roblox behavior).
	run_own(&server_vm, `
local ok, err = pcall(function()
	workspace:FindFirstChild("Platform"):SetNetworkOwner(game.Players:GetPlayers()[1])
end)
assert(not ok, "anchored parts must reject SetNetworkOwner")
`, "own_anchored_rejected")

	// Giving the crate back to the server removes the client owner.
	run_own(&server_vm, `
workspace:FindFirstChild("Crate"):SetNetworkOwner()
assert(workspace:FindFirstChild("Crate"):GetNetworkOwner() == nil, "crate should be server-owned again")
`, "own_server_release")

	own_step(&server, &server_vm, &client, &client_vm, 10)

	run_own(&client_vm, `
assert(workspace:FindFirstChild("Crate"):GetNetworkOwner() == nil, "released crate visible to client")
`, "own_client_released")

	run_own(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "own_server_stop")
	run_own(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "own_client_stop")
	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("OWNERSHIP_API_SMOKE_PASSED")
}