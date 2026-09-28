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
		panic("replication load control smoke failed")
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

	// A deliberately tiny budget against a large static scene. Every snapshot
	// wants more bytes than the connection is allowed, so the budget refuses
	// packets on essentially every tick.
	run_script(
		&server_vm,
		`
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
r.BandwidthBudget = 1024
r.RelevancyDistance = 100000
assert(r.BandwidthBudget == 1024, "budget setter should apply, got " .. tostring(r.BandwidthBudget))
assert(r:StartServer("127.0.0.1", 39217))
for index = 1, 40 do
    local part = Instance.new("Part")
    part.Name = "LoadPart" .. tostring(index)
    part.CFrame = CFrame.new(index * 3, 0, 0)
    part.Anchored = true
    part.Parent = game:GetService("Workspace")
end
`,
		"load_control_server_setup",
	)

	run_script(
		&client_vm,
		`
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:ConnectClient("127.0.0.1", 39217))
`,
		"load_control_client_setup",
	)

	settle(&server, &server_vm, &client, &client_vm, 30)

	// Under sustained overload the controller must shrink its footprint. The
	// previous implementation responded to drops by widening the budget and
	// raising the snapshot rate, which is a positive feedback loop.
	run_script(
		&server_vm,
		`
local r = game:GetService("ReplicatorService")
local stats = r:GetStats()
assert(stats.bandwidthDrops > 0, "the tiny budget should have refused packets")
assert(
    stats.adaptiveScale < 1,
    "load controller did not back off under sustained overload, scale=" .. tostring(stats.adaptiveScale)
)
assert(
    stats.effectiveBandwidthBudget <= 1024,
    "effective budget grew above the configured value: " .. tostring(stats.effectiveBandwidthBudget)
)
assert(
    stats.effectiveSnapshotRate <= 20,
    "snapshot rate was raised under overload: " .. tostring(stats.effectiveSnapshotRate)
)
`,
		"load_control_backoff",
	)

	run_script(
		&server_vm,
		`
scale_after_backoff = game:GetService("ReplicatorService"):GetStats().adaptiveScale
`,
		"load_control_scale_snapshot",
	)

	// Keep the pressure on and confirm the scale keeps falling rather than
	// oscillating back up, which is what the old inverted logic did.
	settle(&server, &server_vm, &client, &client_vm, 240)
	run_script(
		&server_vm,
		`
local r = game:GetService("ReplicatorService")
local stats = r:GetStats()
assert(
    stats.adaptiveScale <= scale_after_backoff + 1e-6,
    "scale climbed back up while still overloaded: " .. tostring(scale_after_backoff) .. " -> " .. tostring(stats.adaptiveScale)
)
assert(stats.adaptiveScale >= 0.25, "scale fell below the configured floor: " .. tostring(stats.adaptiveScale))
-- Still replicating, just more slowly. A controller that starves the link
-- outright would be no better than the runaway it replaced.
assert(stats.effectiveSnapshotRate >= 5, "degraded rate fell below the floor")
`,
		"load_control_sustained",
	)

	// Release the pressure: the scene stops changing, suppression takes over,
	// and the link becomes unpressured, so the scale must recover.
	run_script(
		&server_vm,
		`
local workspace = game:GetService("Workspace")
for _, child in workspace:GetChildren() do
    if child:IsA("Part") then child:Destroy() end
end
`,
		"load_control_release",
	)
	settle(&server, &server_vm, &client, &client_vm, 400)
	run_script(
		&server_vm,
		`
local stats = game:GetService("ReplicatorService"):GetStats()
assert(
    stats.adaptiveScale > 0.9,
    "load controller did not recover once the link was free: " .. tostring(stats.adaptiveScale)
)
assert(stats.effectiveBandwidthBudget == 1024, "budget should be back at the configured value")
`,
		"load_control_recovery",
	)

	run_script(
		&client_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"load_control_client_stop",
	)
	run_script(
		&server_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"load_control_server_stop",
	)

	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
	fmt.println("REPLICATION_LOAD_CONTROL_SMOKE_PASSED")
}
