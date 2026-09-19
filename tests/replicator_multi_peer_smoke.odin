package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("multi peer replication failed")
	}
}

main :: proc() {
	server_vm := vm.New()
	first_vm := vm.New()
	second_vm := vm.New()
	server: engine_runtime.Environment
	first: engine_runtime.Environment
	second: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&first, &first_vm)
	engine_runtime.Environment_Init(&second, &second_vm)

	run_script(&server_vm, `
local r = game:GetService("ReplicatorService")
joined = 0
left = 0
game:GetService("Players").PlayerAdded:Connect(function(player) joined += 1 end)
game:GetService("Players").PlayerRemoving:Connect(function(player) left += 1 end)
assert(r:StartServer("127.0.0.1", 39184))
local common = Instance.new("Part")
common.Name = "Common"
common.Parent = game:GetService("Workspace")
local private = Instance.new("Part")
private.Name = "Private"
private.ReplicationMode = Enum.ReplicationMode.Manual
private.Parent = game:GetService("Workspace")
`, "multi_server_setup")

	run_script(&first_vm, `
local r = game:GetService("ReplicatorService")
assert(r:ConnectClient("127.0.0.1", 39184))
r:OnEvent("targeted", function(data) targeted = data end)
`, "multi_first_setup")

	for _ in 0..<100 {
		engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&first, &first_vm, 1.0 / 60.0)
	}

	run_script(&second_vm, `
local r = game:GetService("ReplicatorService")
assert(r:ConnectClient("127.0.0.1", 39184))
r:OnEvent("targeted", function(data) targeted = data end)
`, "multi_second_setup")

	for _ in 0..<100 {
		engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&first, &first_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&second, &second_vm, 1.0 / 60.0)
	}

	run_script(&first_vm, `
assert(game:GetService("Players").LocalPlayer.UserId == 1)
assert(game:GetService("Workspace"):FindFirstChild("Common"))
assert(game:GetService("Workspace"):FindFirstChild("Private") == nil)
`, "multi_first_snapshot")

	run_script(&second_vm, `
assert(game:GetService("Players").LocalPlayer.UserId == 2)
assert(game:GetService("Workspace"):FindFirstChild("Common"))
assert(game:GetService("Workspace"):FindFirstChild("Private") == nil)
`, "multi_second_snapshot")

	run_script(&server_vm, `
local players = game:GetService("Players"):GetPlayers()
assert(#players == 2)
assert(joined == 2)
local r = game:GetService("ReplicatorService")
assert(r:SendEventTo(players[1], "targeted", "first"))
assert(r:ReplicateTo(game:GetService("Workspace"):FindFirstChild("Private"), players[2]))
`, "multi_target")

	for _ in 0..<45 {
		engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&first, &first_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&second, &second_vm, 1.0 / 60.0)
	}

	run_script(&first_vm, `
assert(targeted == "first")
assert(game:GetService("Workspace"):FindFirstChild("Private") == nil)
game:GetService("ReplicatorService"):Stop()
`, "multi_first_verify")

	run_script(&second_vm, `
assert(targeted == nil)
assert(game:GetService("Workspace"):FindFirstChild("Private"))
game:GetService("ReplicatorService"):Stop()
`, "multi_second_verify")

	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "multi_server_stop")
	run_script(&server_vm, `assert(left == 2)`, "multi_server_players_removed")
	vm.Close(&server_vm)
	vm.Close(&first_vm)
	vm.Close(&second_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&first)
	engine_runtime.Environment_Destroy(&second)
	fmt.println("REPLICATOR_MULTI_PEER_SMOKE_PASSED")
}
