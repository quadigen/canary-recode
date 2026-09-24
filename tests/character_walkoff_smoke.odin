package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_walkoff_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("character walkoff smoke failed")
	}
}

walkoff_step :: proc(server: ^engine_runtime.Environment, server_vm: ^vm.VM, client: ^engine_runtime.Environment, client_vm: ^vm.VM, frames: int) {
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

	run_walkoff_script(&server_vm, `
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39200))
local base = Instance.new("Part", workspace)
base.Name = "Base"
base.Anchored = true
base.Size = vector.create(200, 2, 200)
base.CFrame = CFrame.new(0, -1, 0)
local platform = Instance.new("Part", workspace)
platform.Name = "Spawn"
platform.Anchored = true
platform.Size = vector.create(4, 1, 4)
platform.CFrame = CFrame.new(0, 10, 0)
`, "walkoff_server_setup")

	run_walkoff_script(&client_vm, `
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39200))
`, "walkoff_client_connect")

	walkoff_step(&server, &server_vm, &client, &client_vm, 180)

	run_walkoff_script(&server_vm, `
local root = game:GetService("Players"):GetPlayers()[1].Character.RootPart
assert(root.CFrame.Position.Y > 11, "expected to rest on elevated platform, y=" .. tostring(root.CFrame.Position.Y))
`, "walkoff_on_platform")

	run_walkoff_script(&client_vm, `
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(1, 0, 0)))
`, "walkoff_walk_forward")

	walkoff_step(&server, &server_vm, &client, &client_vm, 240)

	run_walkoff_script(&server_vm, `
local root = game:GetService("Players"):GetPlayers()[1].Character.RootPart
local y = root.CFrame.Position.Y
local x = root.CFrame.Position.X
assert(y < 8, "expected to fall off the platform, y=" .. tostring(y) .. " x=" .. tostring(x))
assert(x > 3, "expected to have walked off the platform x=" .. tostring(x))
`, "walkoff_fell_off")

	run_walkoff_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "walkoff_server_stop")
	run_walkoff_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "walkoff_client_stop")
	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("CHARACTER_WALKOFF_SMOKE_PASSED")
}