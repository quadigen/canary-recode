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
		panic("replication authority smoke failed")
	}
}

step_network :: proc(environment: ^engine_runtime.Environment, script_vm: ^vm.VM) {
	descriptor := services.Find_Service(&environment.services, "ReplicatorService")
	services.Replication_Step(cast(^services.ReplicatorService)descriptor.object, script_vm.L, 1.0 / 60.0)
}

settle :: proc(
	server: ^engine_runtime.Environment,
	server_vm: ^vm.VM,
	client: ^engine_runtime.Environment,
	client_vm: ^vm.VM,
	count: int,
) {
	for _ in 0 ..< count {
		step_network(server, server_vm)
		step_network(client, client_vm)
	}
}

main :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)

	run_script(
		&server_vm,
		`
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:StartServer("127.0.0.1", 39219))
local part = Instance.new("Part")
part.Name = "OwnedPart"
part.Size = Vector3.new(2, 2, 2)
part.Anchored = true
part.Parent = game:GetService("Workspace")
`,
		"authority_server_setup",
	)

	run_script(
		&client_vm,
		`
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:ConnectClient("127.0.0.1", 39219))
`,
		"authority_client_setup",
	)

	settle(&server, &server_vm, &client, &client_vm, 60)

	run_script(
		&server_vm,
		`
local r = game:GetService("ReplicatorService")
local player = game:GetService("Players"):GetPlayers()[1]
local part = game:GetService("Workspace"):FindFirstChild("OwnedPart")
assert(r:ReplicateTo(part, player))
assert(r:AssignOwnership(part, player))
part.Anchored = false
`,
		"authority_server_grant",
	)

	settle(&server, &server_vm, &client, &client_vm, 30)

	// A small, plausible move must still be accepted. Tightening the authority
	// checks is only legitimate if honest clients keep working.
	run_script(
		&client_vm,
		`
local part = game:GetService("Workspace"):FindFirstChild("OwnedPart")
assert(part, "owned part should have replicated")
part.CFrame = CFrame.new(4, 0, 0)
`,
		"authority_client_legit",
	)
	settle(&server, &server_vm, &client, &client_vm, 20)
	run_script(
		&server_vm,
		`
local stats = game:GetService("ReplicatorService"):GetStats()
assert(stats.ownedStatesAccepted > 0, "a small legitimate move was rejected")
local x = game:GetService("Workspace"):FindFirstChild("OwnedPart").CFrame.Position.X
assert(math.abs(x - 4) < 1, "legitimate move did not take effect, x=" .. tostring(x))
`,
		"authority_server_legit",
	)

	// The accumulation attack: every single jump stays under the per-packet
	// tolerance, so a validator that only looks at one packet at a time waves
	// all of them through and the part ends up arbitrarily far away.
	//
	// 60 jumps of 100 studs over one simulated second is 6000 studs, six times
	// the configured sustained-speed limit, so the two outcomes are far apart.
	jump_script := `
local part = game:GetService("Workspace"):FindFirstChild("OwnedPart")
local base = part.CFrame.Position.X
part.CFrame = CFrame.new(base + 100, 0, 0)
`
	for _ in 0 ..< 60 {
		run_script(&client_vm, jump_script, "authority_client_steady_jump")
		settle(&server, &server_vm, &client, &client_vm, 1)
	}

	run_script(
		&server_vm,
		`
local stats = game:GetService("ReplicatorService"):GetStats()
assert(stats.ownedStatesRejected > 0, "sustained teleporting was never rejected")
local x = game:GetService("Workspace"):FindFirstChild("OwnedPart").CFrame.Position.X
-- Unbounded this would be 6000 studs. The one-second travel window allows
-- roughly owned_max_speed, so the part must land far short of that.
assert(
    x < 2000,
    "sustained-speed bound did not engage, part reached x=" .. tostring(x)
)
`,
		"authority_server_sustained",
	)

	// A single oversized jump is still refused outright.
	run_script(
		&client_vm,
		`
local part = game:GetService("Workspace"):FindFirstChild("OwnedPart")
part.CFrame = CFrame.new(90000, 0, 0)
`,
		"authority_client_wild",
	)
	settle(&server, &server_vm, &client, &client_vm, 25)
	run_script(
		&server_vm,
		`
local r = game:GetService("ReplicatorService")
local x = game:GetService("Workspace"):FindFirstChild("OwnedPart").CFrame.Position.X
assert(x < 2000, "an oversized single jump was accepted, x=" .. tostring(x))
assert(r:GetStats().ownedStatesRejected > 0)
`,
		"authority_server_wild",
	)

	run_script(
		&client_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"authority_client_stop",
	)
	run_script(
		&server_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"authority_server_stop",
	)

	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
	fmt.println("REPLICATION_AUTHORITY_SMOKE_PASSED")
}
