package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("replicator loopback failed")
	}
}

step_network :: proc(environment: ^engine_runtime.Environment, script_vm: ^vm.VM) {
	descriptor := services.Find_Service(&environment.services, "ReplicatorService")
	services.Replication_Step(cast(^services.ReplicatorService)descriptor.object, script_vm.L, 1.0 / 60.0)
}

main :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)

	run_script(&server_vm, `
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:StartServer("127.0.0.1", 39183))
local emulator = r:CreateNetworkEmulator({ latency = 0.5, loss = 1 })
assert(emulator:Send("later", true, 10))
assert(#emulator:Drain(10.49) == 0)
assert(emulator:Drain(10.5)[1] == "later")
assert(emulator:Send("lost", false, 10) == false)
local part = Instance.new("Part")
part.Name = "ReplicatedPart"
part.CFrame = CFrame.new(4, 5, 6)
part.Size = Vector3.new(2, 3, 4)
part.Color = Color3.new(0.25, 0.5, 0.75)
part.Transparency = 0.4
part.CanQuery = false
part.Parent = game:GetService("Workspace")
local hidden = Instance.new("Part")
hidden.Name = "ManualPart"
hidden.ReplicationMode = Enum.ReplicationMode.Manual
hidden.Parent = game:GetService("Workspace")
local score = Instance.new("NumberValue")
score.Name = "Score"
score.Value = 17
score.Parent = game:GetService("ReplicatedStorage")
local grouped = Instance.new("Part")
grouped.Name = "GroupedPart"
grouped.ReplicationGroup = "Team"
grouped.Parent = game:GetService("Workspace")
local owned = Instance.new("Part")
owned.Name = "OwnedPart"
owned.ReplicationMode = Enum.ReplicationMode.OwnerOnly
owned.Parent = game:GetService("Workspace")
r.EventReceived:Connect(function(name, data)
    if name == "client-test" then received = data end
end)
r:OnEvent("structured", function(data)
    structured = data
end)
`, "replicator_server_setup")

	run_script(&client_vm, `
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:ConnectClient("127.0.0.1", 39183))
r.EventReceived:Connect(function(name, data)
    if name == "server-test" then received = data end
    if name == "targeted" then targeted = data end
end)
`, "replicator_client_setup")

	for _ in 0..<180 {
		engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&client, &client_vm, 1.0 / 60.0)
	}

	run_script(&client_vm, `
local r = game:GetService("ReplicatorService")
assert(r.Connected, "client packets " .. tostring(r:GetStats().packetsReceived) .. " malformed " .. tostring(r:GetStats().malformedPackets) .. " player " .. tostring(game:GetService("Players").LocalPlayer))
assert(game:GetService("Players").LocalPlayer)
local part = game:GetService("Workspace"):FindFirstChild("ReplicatedPart")
assert(part and part.ClassName == "Part")
assert(game:GetService("Workspace"):FindFirstChild("ManualPart") == nil)
assert(game:GetService("Workspace"):FindFirstChild("GroupedPart") == nil)
assert(game:GetService("Workspace"):FindFirstChild("OwnedPart") == nil)
assert(game:GetService("ReplicatedStorage"):FindFirstChild("Score").Value == 17)
assert(part.CFrame.Position == Vector3.new(4, 5, 6))
assert(part.Size == Vector3.new(2, 3, 4))
assert(part.CanQuery == false)
assert(math.abs(part.Transparency - 0.4) < 1e-4)
assert(r:SendEvent("client-test", "hello"))
assert(r:SendEvent("structured", { count = 4, point = Vector3.new(1, 2, 3), tint = Color3.new(0.1, 0.2, 0.3), frame = CFrame.new(2, 3, 4), list = { 10, 20 }, nested = { ok = true } }))
`, "replicator_client_verify")

	for _ in 0..<20 {
		engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&client, &client_vm, 1.0 / 60.0)
	}

	run_script(&server_vm, `
assert(received == "hello")
assert(structured.count == 4 and structured.point == Vector3.new(1, 2, 3))
assert(structured.tint == Color3.new(0.1, 0.2, 0.3))
assert(structured.frame == CFrame.new(2, 3, 4))
assert(structured.list[1] == 10 and structured.list[2] == 20)
assert(structured.nested.ok)
local players = game:GetService("Players"):GetPlayers()
assert(#players == 1 and players[1].UserId > 0)
assert(game:GetService("ReplicatorService"):SendEventTo(players[1], "targeted", { value = 42 }))
assert(game:GetService("ReplicatorService"):ReplicateTo(game:GetService("Workspace"):FindFirstChild("ManualPart"), players[1]))
assert(game:GetService("ReplicatorService"):AddPlayerToGroup(players[1], "Team"))
assert(game:GetService("ReplicatorService"):IsPlayerInGroup(players[1], "Team"))
local owned = game:GetService("Workspace"):FindFirstChild("OwnedPart")
assert(owned and owned.NetworkId > 0, "owned part unavailable")
assert(game:GetService("ReplicatorService"):AssignOwnership(owned, players[1]))
owned.Anchored = false
assert(game:GetService("ReplicatorService"):SendEvent("server-test", "world"))
local workspace = game:GetService("Workspace")
local folder = Instance.new("Folder")
folder.Name = "NetworkFolder"
folder.Parent = workspace
local part = workspace:FindFirstChild("ReplicatedPart")
part.Name = "MovedPart"
part.CFrame = CFrame.new(8, 9, 10)
part.Parent = folder
game:GetService("ReplicatedStorage"):FindFirstChild("Score").Value = 23
`, "replicator_server_event")

	for _ in 0..<60 {
		step_network(&server, &server_vm)
		step_network(&client, &client_vm)
	}

	run_script(&client_vm, `
assert(received == "world")
assert(targeted and targeted.value == 42)
local folder = game:GetService("Workspace"):FindFirstChild("NetworkFolder")
assert(folder)
local part = folder:FindFirstChild("MovedPart")
assert(part and part.CFrame.Position == Vector3.new(8, 9, 10))
assert(game:GetService("ReplicatedStorage"):FindFirstChild("Score").Value == 23)
assert(game:GetService("Workspace"):FindFirstChild("ManualPart"))
assert(game:GetService("Workspace"):FindFirstChild("GroupedPart"))
assert(game:GetService("Workspace"):FindFirstChild("OwnedPart"))
assert(game:GetService("Players").LocalPlayer.UserId > 0)
`, "replicator_client_event")

	run_script(&client_vm, `
game:GetService("Workspace"):FindFirstChild("OwnedPart").CFrame = CFrame.new(2, 0, 0)
`, "replicator_client_owned_motion")

	for _ in 0..<30 {
		step_network(&client, &client_vm)
		step_network(&server, &server_vm)
	}

	run_script(&server_vm, `
local r = game:GetService("ReplicatorService")
assert(r:GetStats().ownedStatesAccepted > 0)
assert(math.abs(game:GetService("Workspace"):FindFirstChild("OwnedPart").CFrame.Position.X - 2) < 0.1)
`, "replicator_server_owned_motion")

	run_script(&client_vm, `
game:GetService("Workspace"):FindFirstChild("OwnedPart").CFrame = CFrame.new(10000, 0, 0)
`, "replicator_client_invalid_motion")

	for _ in 0..<35 {
		step_network(&client, &client_vm)
		step_network(&server, &server_vm)
	}

	run_script(&server_vm, `
assert(game:GetService("ReplicatorService"):GetStats().ownedStatesRejected > 0)
assert(math.abs(game:GetService("Workspace"):FindFirstChild("OwnedPart").CFrame.Position.X - 2) < 0.1)
`, "replicator_server_reject_motion")

	run_script(&server_vm, `
local r = game:GetService("ReplicatorService")
local player = game:GetService("Players"):GetPlayers()[1]
local workspace = game:GetService("Workspace")
assert(r:StopReplicatingTo(workspace:FindFirstChild("ManualPart"), player))
assert(r:RemovePlayerFromGroup(player, "Team"))
assert(r:AssignOwnership(workspace:FindFirstChild("OwnedPart"), nil))
assert(r:Unregister(workspace:FindFirstChild("NetworkFolder"):FindFirstChild("MovedPart")))
`, "replicator_server_visibility")

	for _ in 0..<40 {
		engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&client, &client_vm, 1.0 / 60.0)
	}

	run_script(&client_vm, `
assert(game:GetService("Workspace"):FindFirstChild("ManualPart") == nil)
assert(game:GetService("Workspace"):FindFirstChild("GroupedPart") == nil)
assert(game:GetService("Workspace"):FindFirstChild("OwnedPart") == nil)
assert(game:GetService("Workspace"):FindFirstChild("NetworkFolder"):FindFirstChild("MovedPart") == nil)
game:GetService("ReplicatorService"):Stop()
assert(game:GetService("Workspace"):FindFirstChild("NetworkFolder") == nil)
assert(game:GetService("ReplicatedStorage"):FindFirstChild("Score") == nil)
assert(game:GetService("Players").LocalPlayer == nil)
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39183))
`, "replicator_client_visibility")

	for _ in 0..<100 {
		step_network(&server, &server_vm)
		step_network(&client, &client_vm)
	}

	run_script(&client_vm, `
assert(game:GetService("ReplicatorService").Connected)
assert(game:GetService("ReplicatedStorage"):FindFirstChild("Score").Value == 23)
local count = 0
for _, child in game:GetService("Workspace"):GetChildren() do
    if child.Name == "NetworkFolder" then count += 1 end
end
assert(count == 1)
game:GetService("ReplicatorService"):Stop()
`, "replicator_client_reconnect")
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "replicator_server_stop")
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
	fmt.println("REPLICATOR_LOOPBACK_SMOKE_PASSED")
}
