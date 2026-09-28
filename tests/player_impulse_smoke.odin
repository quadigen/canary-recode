// Player:ApplyImpulse is Roblox's legacy way to shove a character around. It had
// no implementation, so the call did nothing.
//
// It cannot work the way Part:ApplyImpulse does. A living character is a
// kinematic capsule that the character controller sweeps and teleports, so the
// solver never integrates it and Jolt has no body to add an impulse to. The
// impulse is therefore turned into character velocity: the horizontal component
// becomes knockback the tick carries and damps, the vertical component joins the
// jump velocity.
//
// It is called from the client that owns the character, because that is the peer
// simulating it -- the server does not tick a client-authoritative character, so
// a server-side call would set a velocity nothing reads.
package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(name)
		fmt.eprintln(err)
		delete(err)
		panic("player impulse smoke test failed")
	}
}

step_pair :: proc(
	server: ^engine_runtime.Environment,
	server_vm: ^vm.VM,
	client: ^engine_runtime.Environment,
	client_vm: ^vm.VM,
	frames: int,
) {
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

	run_script(&server_vm, `
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39216))
spawn = Instance.new("Part", workspace)
spawn.Name = "Spawn"
spawn.Size = vector.create(20, 1, 20)
spawn.CFrame = CFrame.new(0, 60, 0)
spawn.Anchored = true
floor = Instance.new("Part", workspace)
floor.Name = "Floor"
floor.Size = vector.create(600, 1, 600)
floor.CFrame = CFrame.new(0, 0, 0)
floor.Anchored = true
`, "impulse_server_start")
	run_script(&client_vm, `
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39216))
`, "impulse_client_start")
	step_pair(&server, &server_vm, &client, &client_vm, 300)

	// A player with no character has nothing to push, and the call says so instead
	// of silently doing nothing.
	run_script(&server_vm, `
player = game:GetService("Players"):GetPlayers()[1]
assert(player, "no player joined")
`, "impulse_no_character")

	// Roblox's Player:ApplyImpulse returns nothing, so the call is made bare and
	// its effect is what gets checked.
	run_script(&client_vm, `
local player = game:GetService("Players").LocalPlayer
assert(player and player.Character, "the client has no character")
local root = player.Character.RootPart
assert(root, "the client character has no HumanoidRootPart")
start_x = root.CFrame.X
player:ApplyImpulse(Vector3.new(400, 0, 0))
`, "impulse_apply")
	step_pair(&server, &server_vm, &client, &client_vm, 20)
	run_script(&client_vm, `
local root = game:GetService("Players").LocalPlayer.Character.RootPart
assert(
    root.CFrame.X > start_x + 0.5,
    "the impulse did not move the character: " .. root.CFrame.X .. " from " .. start_x
)
`, "impulse_moved")

	// The push is damped, so it does not carry the character across the map
	// forever, and a vertical impulse is accepted too.
	run_script(&client_vm, `
before_y = game:GetService("Players").LocalPlayer.Character.RootPart.CFrame.Y
game:GetService("Players").LocalPlayer:ApplyImpulse(Vector3.new(0, 400, 0))
`, "impulse_vertical")
	step_pair(&server, &server_vm, &client, &client_vm, 4)
	run_script(&client_vm, `
local root = game:GetService("Players").LocalPlayer.Character.RootPart
assert(root.CFrame.Y > before_y, "a vertical impulse did not lift the character")
`, "impulse_lifted")

	// And the knockback decays rather than accumulating forever.
	run_script(&client_vm, `
fast_x = game:GetService("Players").LocalPlayer.Character.RootPart.CFrame.X
`, "impulse_drain_start")
	step_pair(&server, &server_vm, &client, &client_vm, 90)
	run_script(&client_vm, `
local root = game:GetService("Players").LocalPlayer.Character.RootPart
assert(root.CFrame.X < fast_x + 40, "knockback never decayed")
`, "impulse_damped")

	// The replication transport owns a thread, so it has to be stopped on both
	// sides before the VMs are closed. Closing a client VM that still has a live
	// connection faults, which is why every socket smoke test here stops the
	// replicator first.
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "impulse_server_stop")
	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "impulse_client_stop")
	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("PLAYER_IMPULSE_SMOKE_PASSED")
}