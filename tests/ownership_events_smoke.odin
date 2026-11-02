package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run_own_events :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("ownership events smoke failed")
	}
}

own_events_step :: proc(
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

	run_own_events(
		&server_vm,
		`
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39239))
local floor = Instance.new("Part", workspace)
floor.Name = "Floor"
floor.Size = vector.create(200, 1, 200)
floor.Anchored = true
local crate = Instance.new("Part", workspace)
crate.Name = "Crate"
crate.Anchored = false
crate.Size = vector.create(2, 2, 2)
crate.CFrame = CFrame.new(20, 5, 0)
-- Pinned to the server so the sweep and the connecting client cannot grab it.
crate:SetNetworkOwner()
local group = Instance.new("Model", workspace)
group.Name = "Group"
local a = Instance.new("Part", group)
a.Name = "A"
a.Anchored = false
a.Size = vector.create(1, 1, 1)
a.CFrame = CFrame.new(3, 5, 0)
a:SetNetworkOwner()
local b = Instance.new("Part", group)
b.Name = "B"
b.Anchored = false
b.Size = vector.create(1, 1, 1)
b.CFrame = CFrame.new(-3, 5, 0)
b:SetNetworkOwner()
local crate = workspace:FindFirstChild("Crate")
serve_crate_events = 0
serve_crate_owner = "none"
crate.OwnershipChanged:Connect(function(owner)
	serve_crate_events += 1
	serve_crate_owner = owner
end)
serve_group_events = 0
workspace:FindFirstChild("Group"):FindFirstChild("A").OwnershipChanged:Connect(function(owner)
	serve_group_events += 1
end)
`,
		"own_events_server_setup",
	)

	run_own_events(
		&client_vm,
		`
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39239))
`,
		"own_events_client_connect",
	)

	own_events_step(&server, &server_vm, &client, &client_vm, 120)

	run_own_events(
		&client_vm,
		`
client_crate_events = 0
client_crate_owner = "none"
client_group_events = 0
workspace:FindFirstChild("Crate").OwnershipChanged:Connect(function(owner)
	client_crate_events += 1
	client_crate_owner = owner
end)
workspace:FindFirstChild("Group"):FindFirstChild("A").OwnershipChanged:Connect(function(owner)
	client_group_events += 1
end)
`,
		"own_events_client_handlers",
	)


	run_own_events(
		&server_vm,
		`
local crate = workspace:FindFirstChild("Crate")
assert(crate:GetNetworkOwnershipStatus() == Enum.NetworkOwnership.Server, "pinned crate status is Server")
`,
		"own_events_server_status_base",
	)

	run_own_events(
		&client_vm,
		`
local crate = workspace:FindFirstChild("Crate")
assert(crate:GetNetworkOwnershipStatus() == Enum.NetworkOwnership.Server, "client mirror keeps Server status")
`,
		"own_events_client_status_base",
	)


	run_own_events(
		&server_vm,
		`
local player = game.Players:GetPlayers()[1]
workspace:FindFirstChild("Group"):SetNetworkOwner(player)
`,
		"own_events_model_assign",
	)

	own_events_step(&server, &server_vm, &client, &client_vm, 60)

	run_own_events(
		&server_vm,
		`
local group = workspace:FindFirstChild("Group")
assert(group:GetNetworkOwnershipStatus() == Enum.NetworkOwnership.ServerPart, "server sees model-owned parts as ServerPart")
assert(group:FindFirstChild("A"):GetNetworkOwnershipStatus() == Enum.NetworkOwnership.ServerPart)
`,
		"own_events_model_server",
	)

	run_own_events(
		&client_vm,
		`
local group = workspace:FindFirstChild("Group")
local status = group:GetNetworkOwnershipStatus()
assert(status == Enum.NetworkOwnership.ClientPart,
	"client sees model-owned parts as ClientPart once the flag rides kind-10, got " .. tostring(status))
assert(group:FindFirstChild("A"):GetNetworkOwnershipStatus() == Enum.NetworkOwnership.ClientPart)
`,
		"own_events_model_client",
	)

	run_own_events(
		&server_vm,
		`
assert(serve_group_events == 1, "server fires A OwnershipChanged on model assign, got " .. tostring(serve_group_events))
`,
		"own_events_server_group_event",
	)

	run_own_events(
		&client_vm,
		`
assert(client_group_events == 1, "client fires A OwnershipChanged on model assign, got " .. tostring(client_group_events))
`,
		"own_events_client_group_event",
	)


	run_own_events(
		&client_vm,
		`
local local_player = game.Players.LocalPlayer
assert(local_player ~= nil)
workspace:FindFirstChild("Crate"):SetNetworkOwner(local_player)
`,
		"own_events_client_claim",
	)

	own_events_step(&server, &server_vm, &client, &client_vm, 30)

	run_own_events(
		&server_vm,
		`
assert(serve_crate_events == 1, "server fires crate OwnershipChanged on claim, got " .. tostring(serve_crate_events))
assert(serve_crate_owner == game.Players:GetPlayers()[1], "server crate event owner is Player1")
assert(workspace:FindFirstChild("Crate"):GetNetworkOwnershipStatus() == Enum.NetworkOwnership.Server,
	"server sees a client-owned crate as Server")
`,
		"own_events_server_claimed",
	)

	run_own_events(
		&client_vm,
		`
assert(client_crate_events == 1, "client fires crate OwnershipChanged once on claim, got " .. tostring(client_crate_events))
assert(client_crate_owner == game.Players.LocalPlayer, "client crate event owner is LocalPlayer")
assert(workspace:FindFirstChild("Crate"):GetNetworkOwnershipStatus() == Enum.NetworkOwnership.Client,
	"client sees its owned crate as Client")
`,
		"own_events_client_claimed",
	)

	own_events_step(&server, &server_vm, &client, &client_vm, 10)


	run_own_events(
		&server_vm,
		`
crate_start_y = workspace:FindFirstChild("Crate").Position.Y
`,
		"own_events_capture_y0",
	)

	run_own_events(
		&client_vm,
		`
local crate = workspace:FindFirstChild("Crate")
assert(crate:GetNetworkOwnershipStatus() == Enum.NetworkOwnership.Client)
crate.AssemblyLinearVelocity = vector.create(0, 150, 0)
`,
		"own_events_launch",
	)

	own_events_step(&server, &server_vm, &client, &client_vm, 12)

	run_own_events(
		&server_vm,
		`
assert(workspace:FindFirstChild("Crate").Position.Y > crate_start_y + 0.5,
	"server mirrors the client's upward launch")
`,
		"own_events_rise_seen",
	)


	run_own_events(
		&server_vm,
		`
release_start_y = workspace:FindFirstChild("Crate").Position.Y
workspace:FindFirstChild("Crate"):SetNetworkOwner()
`,
		"own_events_server_release",
	)

	own_events_step(&server, &server_vm, &client, &client_vm, 30)

	run_own_events(
		&server_vm,
		`
assert(workspace:FindFirstChild("Crate").Position.Y > release_start_y + 0.1,
	"server keeps upward momentum across the handoff, got " .. tostring(workspace:FindFirstChild("Crate").Position.Y))
`,
		"own_events_momentum_kept",
	)

	run_own_events(
		&server_vm,
		`
assert(serve_crate_events == 2, "server fires crate OwnershipChanged on release, got " .. tostring(serve_crate_events))
assert(serve_crate_owner == nil, "server crate event owner is nil on release")
`,
		"own_events_server_released",
	)

	run_own_events(
		&client_vm,
		`
assert(client_crate_events == 2, "client fires crate OwnershipChanged on release, got " .. tostring(client_crate_events))
assert(client_crate_owner == nil, "client crate event owner is nil on release")
`,
		"own_events_client_released",
	)

	run_own_events(
		&server_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"own_events_server_stop",
	)
	run_own_events(
		&client_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"own_events_client_stop",
	)
	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("OWNERSHIP_EVENTS_SMOKE_PASSED")
}
