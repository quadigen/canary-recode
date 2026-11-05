package main


import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

DT :: f32(1.0 / 70.0)
FRAMES :: 500
ADVANCE_RAMP :: `
_G.walker += 1
workspace.Ramp.CFrame = CFrame.new(_G.walker, 0, 0)
`

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("replication cadence smoke failed")
	}
}

step_network :: proc(environment: ^engine_runtime.Environment, script_vm: ^vm.VM) {
	descriptor := services.Find_Service(&environment.services, "ReplicatorService")
	services.Replication_Step(cast(^services.ReplicatorService)descriptor.object, script_vm.L, DT)
}

service_of :: proc(environment: ^engine_runtime.Environment) -> ^services.ReplicatorService {
	descriptor := services.Find_Service(&environment.services, "ReplicatorService")
	return cast(^services.ReplicatorService)descriptor.object
}

ramp_x :: proc(environment: ^engine_runtime.Environment) -> f64 {
	service := service_of(environment)
	for entity in service.entity_list {
		if entity.object == nil || entity.object.destroyed {continue}
		part := cast(^classes.Part)entity.object
		if part.name != "Ramp" {continue}
		return f64(part.cframe.x)
	}
	return -1
}

cadence_case :: proc(fixed_clock: bool) {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)
	client_service := service_of(&client)
	if !fixed_clock {
		client_service.client_capabilities &= ~services.Replication_Capability_Snapshot_Clock
	}

	run_script(
		&server_vm,
		`
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
r.RelevancyDistance = 100000
assert(r:StartServer("127.0.0.1", 39320))
local part = Instance.new("Part")
part.Name = "Ramp"
part.Anchored = true
part.CFrame = CFrame.new(0, 0, 0)
part.Parent = game:GetService("Workspace")
_G.walker = 0
`,
		"cadence_server_setup",
	)
	run_script(
		&client_vm,
		`
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:ConnectClient("127.0.0.1", 39320))
`,
		"cadence_client_setup",
	)


	for _ in 0 ..< 60 {
		step_network(&server, &server_vm)
		step_network(&client, &client_vm)
	}
	assert(client_service.handshake_complete, "the client never completed the handshake")

	states_before := client_service.states_applied
	for _ in 0 ..< FRAMES {
		run_script(&server_vm, ADVANCE_RAMP, "cadence_ramp")
		step_network(&server, &server_vm)
		client_service.ack_elapsed = 1
		step_network(&client, &client_vm)
	}
	states_after := client_service.states_applied

	server_service := service_of(&server)
	rate := f64(server_service.snapshot_rate)


	target := f64(server_service.clock) * rate
	assert(
		abs(f64(server_service.tick) - target) <= 1.0,
		fmt.tprintf(
			"server tick %d is out of phase with clock %.3f * rate %.1f = %.1f",
			server_service.tick,
			server_service.clock,
			rate,
			target,
		),
	)


	expected_states := f64(FRAMES) / 70.0 * rate
	delta := f64(states_after) - f64(states_before)
	assert(
		delta >= expected_states - 3 && delta <= expected_states + 5,
		fmt.tprintf(
			"client applied %.0f transform frames over the window, expected about %.1f at %.0f Hz",
			delta,
			expected_states,
			rate,
		),
	)


	server_x := ramp_x(&server)
	client_x := ramp_x(&client)
	assert(server_x > 0, "the ramp never moved on the server")
	assert(
		client_x >= server_x - 15 && client_x <= server_x + 5,
		fmt.tprintf(
			"client rendered the ramp at %.1f while the server had it at %.1f",
			client_x,
			server_x,
		),
	)

	peak_x := client_x
	for _ in 0 ..< 55 {
		step_network(&server, &server_vm)
		client_service.ack_elapsed = 1
		step_network(&client, &client_vm)
		peak_x = max(peak_x, ramp_x(&client))
	}
	assert(peak_x <= server_x + 1, fmt.tprintf("a stopped part coasted %.2f studs", peak_x - server_x))

	run_script(&server_vm, `game:GetService("ReplicatorService").SnapshotRate = 10`, "cadence_slow_down")
	for _ in 0 ..< 140 {
		run_script(&server_vm, ADVANCE_RAMP, "cadence_slow_ramp")
		step_network(&server, &server_vm)
		step_network(&client, &client_vm)
	}
	assert(client_service.states_applied - states_after >= 15, "lowering SnapshotRate must not stall state reception")
	assert(ramp_x(&client) > client_x + 100, "the client must keep rendering motion after the rate changes")
	if fixed_clock {
		assert(client_service.snapshot_rate == 10, "the interpolation delay should follow the server cadence")
	}
	assert(client_service.malformed_packets == 0, "the peer must receive the negotiated packet formats")

	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "cadence_client_stop")
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "cadence_server_stop")
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
}

main :: proc() {
	cadence_case(true)
	cadence_case(false)
	fmt.println("REPLICATION_CADENCE_SMOKE_PASSED")
}
