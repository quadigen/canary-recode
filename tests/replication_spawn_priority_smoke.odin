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
		panic("replication spawn priority smoke failed")
	}
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
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)

	// A map intentionally much larger than one snapshot. The player needs to
	// receive its character and the Spawn platform before this bulk data.
	run_script(&server_vm, `
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39223))
local spawn = Instance.new("Part", workspace)
spawn.Name = "Spawn"
spawn.Size = Vector3.new(500, 1, 500)
spawn.CFrame = CFrame.new(0, 4, 0)
spawn.Anchored = true
for index = 1, 1200 do
    local part = Instance.new("Part", workspace)
    part.Name = "MapPart" .. tostring(index)
    part.CFrame = CFrame.new(index * 3, 0, 0)
    part.Anchored = true
end
`, "priority_server_start")
	run_script(&client_vm, `
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39223))
`, "priority_client_start")

	// This is deliberately far earlier than a full 1,200-part map transfer.
	step_pair(&server, &server_vm, &client, &client_vm, 8)
	run_script(&client_vm, `
local player = game:GetService("Players").LocalPlayer
assert(player and player.Character and player.Character.RootPart,
    "local character was queued behind the map")
assert(workspace:FindFirstChild("Spawn"), "spawn platform was queued behind the map")
assert(game:GetService("ReplicatorService"):GetStats().sceneReady,
    "character simulation was enabled before the spawn lane completed")
`, "priority_client_arrival")

	step_pair(&server, &server_vm, &client, &client_vm, 180)
	run_script(&client_vm, `
local y = game:GetService("Players").LocalPlayer.Character.RootPart.Position.Y
assert(y > 5, "character fell through the streamed map, y=" .. tostring(y))
`, "priority_client_grounded")

	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "priority_client_stop")
	step_pair(&server, &server_vm, &client, &client_vm, 30)
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "priority_server_stop")
	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("REPLICATION_SPAWN_PRIORITY_SMOKE_PASSED")
}
