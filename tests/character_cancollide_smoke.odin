package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("character cancollide smoke failed")
	}
}

step :: proc(server: ^engine_runtime.Environment, server_vm: ^vm.VM, client: ^engine_runtime.Environment, client_vm: ^vm.VM, frames: int) {
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

	// A wide floor so the character always has ground, plus two walls on the
	// walk path: a solid one and a CanCollide-off one. The character must be
	// stopped by the first and must pass straight through the second.
	run_script(&server_vm, `
	assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39211))
	local floor = Instance.new("Part", workspace)
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = vector.create(200, 2, 200)
	floor.CFrame = CFrame.new(0, -1, 0)
	local solid = Instance.new("Part", workspace)
	solid.Name = "Solid"
	solid.Anchored = true
	solid.Size = vector.create(2, 12, 40)
	solid.CFrame = CFrame.new(20, 6, 0)
	local ghost = Instance.new("Part", workspace)
	ghost.Name = "Ghost"
	ghost.Anchored = true
	ghost.Size = vector.create(2, 12, 40)
	ghost.CFrame = CFrame.new(40, 6, 0)
	ghost.CanCollide = false
	`, "cancollide_server_setup")

	run_script(&client_vm, `
	assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39211))
	`, "cancollide_client_connect")

	step(&server, &server_vm, &client, &client_vm, 180)

	// Walk forward far enough to reach and pass the ghost, given the solid wall
	// in between is what actually stops the character.
	run_script(&client_vm, `
	assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(1, 0, 0)))
	`, "cancollide_walk_forward")

	step(&server, &server_vm, &client, &client_vm, 360)

	run_script(&server_vm, `
	local root = game:GetService("Players"):GetPlayers()[1].Character.RootPart
	local x = root.CFrame.Position.X
	-- Blocked by the solid wall well before the ghost at x=40.
	assert(x < 20, "expected the solid CanCollide wall to stop the character, x=" .. tostring(x))
	assert(x > 15, "expected the character to be pressed against the wall, x=" .. tostring(x))

	-- With the solid wall removed the character must now pass through the
	-- CanCollide-off ghost instead of being stopped by it.
	workspace:FindFirstChild("Solid"):Destroy()
	`, "cancollide_solid_blocked")

	step(&server, &server_vm, &client, &client_vm, 480)

	run_script(&server_vm, `
	local root = game:GetService("Players"):GetPlayers()[1].Character.RootPart
	local x = root.CFrame.Position.X
	assert(x > 45, "expected the character to pass through the CanCollide-off part, x=" .. tostring(x))
	`, "cancollide_passes_through_ghost")

	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "cancollide_server_stop")
	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "cancollide_client_stop")
	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("CHARACTER_CANCOLLIDE_SMOKE_PASSED")
}