package main

// The handshake measures the offset between the server clock and the local one
// and stores it in time_offset, but nothing consumed it until the interpolation
// render target was rewritten to work in the server's timebase. This covers that
// the offset is measured, that it survives into rendering, and that interpolation
// still behaves when no estimate has arrived yet.

import "core:fmt"
import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("replication timebase smoke failed")
	}
}

step_network :: proc(environment: ^engine_runtime.Environment, script_vm: ^vm.VM) {
	descriptor := services.Find_Service(&environment.services, "ReplicatorService")
	services.Replication_Step(cast(^services.ReplicatorService)descriptor.object, script_vm.L, 1.0 / 60.0)
}

// step_pair drives the server and the client in lockstep so both clocks stay
// aligned; only time_sync drift separates them, which is what the offset is for.
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

service_of :: proc(environment: ^engine_runtime.Environment) -> ^services.ReplicatorService {
	descriptor := services.Find_Service(&environment.services, "ReplicatorService")
	return cast(^services.ReplicatorService)descriptor.object
}

Pair :: struct {
	server:    engine_runtime.Environment,
	client:    engine_runtime.Environment,
	server_vm: vm.VM,
	client_vm: vm.VM,
}

// The ports are baked into the scripts rather than interpolated. Odin's tprintf
// treats "{" as the start of a custom formatting verb, so it would eat the Luau
// table literal in the schema registration, and this toolchain ships no core:str
// to convert the port for plain concatenation.
pair_start :: proc(pair: ^Pair, server_script, client_script: string) {
	pair.server_vm = vm.New()
	pair.client_vm = vm.New()
	engine_runtime.Environment_Init(&pair.server, &pair.server_vm)
	engine_runtime.Environment_Init(&pair.client, &pair.client_vm)
	run_script(&pair.server_vm, server_script, "timebase_server_start")
	run_script(&pair.client_vm, client_script, "timebase_client_start")
	// Past the handshake and past a few one second time sync intervals.
	settle(&pair.server, &pair.server_vm, &pair.client, &pair.client_vm, 400)
}

pair_stop :: proc(pair: ^Pair) {
	run_script(&pair.client_vm, `game:GetService("ReplicatorService"):Stop()`, "timebase_client_stop")
	run_script(&pair.server_vm, `game:GetService("ReplicatorService"):Stop()`, "timebase_server_stop")
	vm.Close(&pair.server_vm)
	vm.Close(&pair.client_vm)
	engine_runtime.Environment_Destroy(&pair.server)
	engine_runtime.Environment_Destroy(&pair.client)
}

// ---------------------------------------------------------------------------
// 1. The offset is measured from real sync samples rather than left at its
//    initial value, and it stays in a plausible range.
// ---------------------------------------------------------------------------
offset_is_measured :: proc() {
	pair: Pair
	pair_start(
		&pair,
		`
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:StartServer("127.0.0.1", 39310))
local part = Instance.new("Part")
part.Name = "Anchored"
part.Anchored = true
part.CFrame = CFrame.new(10, 0, 0)
part.Parent = game:GetService("Workspace")
`,
		`assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39310))`,
	)
	client_service := service_of(&pair.client)
	assert(
		client_service.time_sync_sequence >= 2,
		fmt.tprintf("client sent too few sync samples: %d", client_service.time_sync_sequence),
	)
	// Both processes step the same delta, so the true offset is near zero. A
	// nonzero bound rather than an exact check because a sample is folded in per
	// interval and each fold can be off by the reply's own latency.
	assert(
		abs(f64(client_service.time_offset)) < 0.5,
		fmt.tprintf("offset estimate drifted to %f seconds", client_service.time_offset),
	)
	pair_stop(&pair)
}

// ---------------------------------------------------------------------------
// 2. Teardown drops the estimate. The offset is only meaningful against the
//    peer it was measured from, so a reconnect to a different server would
//    otherwise render against a timebase that no longer applies.
// ---------------------------------------------------------------------------
stop_clears_offset :: proc() {
	pair: Pair
	pair_start(
		&pair,
		`
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:StartServer("127.0.0.1", 39311))
`,
		`assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39311))`,
	)
	client_service := service_of(&pair.client)
	client_service.time_offset = 4.0
	client_service.time_sync_sequence = 9
	run_script(&pair.client_vm, `game:GetService("ReplicatorService"):Stop()`, "timebase_stop_client")
	assert(client_service.time_offset == 0, "stop left a stale time offset behind")
	assert(
		client_service.time_sync_sequence == 0,
		"stop left a stale time sync sequence behind",
	)
	run_script(&pair.server_vm, `game:GetService("ReplicatorService"):Stop()`, "timebase_stop_server")
	vm.Close(&pair.server_vm)
	vm.Close(&pair.client_vm)
	engine_runtime.Environment_Destroy(&pair.server)
	engine_runtime.Environment_Destroy(&pair.client)
}

// ---------------------------------------------------------------------------
// 3. The offset reaches the render target.
//
//    A single teleport converges no matter where the target lands, so it proves
//    nothing about the timebase. Instead the part is walked along X at a steady
//    rate for long enough to fill the sample buffer, and the target is then
//    pushed forward by rewriting the offset the handshake would have produced.
//    Because the samples are a position ramp, a target that moves forward reads
//    a later sample and the rendered X must rise with it. If the offset were
//    ignored, the rendered X would not budge.
// ---------------------------------------------------------------------------
render_uses_server_timebase :: proc() {
	pair: Pair
	pair_start(
		&pair,
		`
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:StartServer("127.0.0.1", 39312))
local part = Instance.new("Part")
part.Name = "Anchored"
part.Anchored = true
part.CFrame = CFrame.new(0, 0, 0)
part.Parent = game:GetService("Workspace")
_G.walker = 0
`,
		`assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39312))`,
	)
	client_service := service_of(&pair.client)
	assert(client_service.handshake_complete, "the client never completed the handshake")

	// Step the pair while advancing the part by a fixed amount per server step,
	// keeping the server and client clocks in lockstep.
	for _ in 0 ..< 180 {
		run_script(
			&pair.server_vm,
			`
_G.walker += 1
game:GetService("Workspace"):FindFirstChild("Anchored").CFrame = CFrame.new(_G.walker, 0, 0)
`,
			"timebase_ramp",
		)
		step_network(&pair.server, &pair.server_vm)
		step_network(&pair.client, &pair.client_vm)
	}

	// The offset is a full second, which is twenty ticks of target. A smaller
	// shift is not usable here: once the target leaves the sample window the
	// client dead reckons, and its forward extrapolation plus the smoothing
	// blend both move the rendered position the same way, which would hide a
	// rewind. Twenty ticks overwhelms that.
	before := client_render_x(&pair)
	client_service.time_offset = 1.0
	after := client_render_x(&pair)
	assert(
		after > before + 0.5,
		fmt.tprintf(
			"advancing the timebase by 1s did not move the render target: %f then %f",
			before,
			after,
		),
	)
	// A negative offset must walk the target back into the buffered past rather
	// than past the newest sample, so the rendered position retreats.
	client_service.time_offset = -1.0
	back := client_render_x(&pair)
	assert(
		back < after - 0.5,
		fmt.tprintf(
			"rewinding the timebase by 1s did not move the render target: %f then %f",
			after,
			back,
		),
	)
	pair_stop(&pair)
}

// client_render_x steps the client once and reads the rendered position straight
// out of the replicated Part, which is what the interpolation pass writes to.
client_render_x :: proc(pair: ^Pair) -> f64 {
	step_network(&pair.client, &pair.client_vm)
	descriptor := services.Find_Service(&pair.client.services, "ReplicatorService")
	service := cast(^services.ReplicatorService)descriptor.object
	for entity in service.entity_list {
		if entity.object == nil {continue}
		part := cast(^classes.Part)entity.object
		if part.name != "Anchored" {continue}
		return f64(part.cframe.x)
	}
	return 0
}

// ---------------------------------------------------------------------------
// 4. A client that joins a server which has already been running.
//
//    This is the case a playtest hits and a unit test built on a fresh pair does
//    not. The server's snapshot tick is well ahead of the client's clock, and
//    until the first time sync reply lands the offset is still zero. A render
//    target anchored to the client's own clock is then far behind the sample
//    window, so interpolation clamps to the oldest buffered sample and the part
//    renders at a stale position until the estimate arrives. Anchoring the
//    target to the newest sample instead makes the join correct immediately.
// ---------------------------------------------------------------------------
joins_a_running_server :: proc() {
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
assert(r:StartServer("127.0.0.1", 39314))
local part = Instance.new("Part")
part.Name = "Anchored"
part.Anchored = true
part.CFrame = CFrame.new(0, 0, 0)
part.Parent = game:GetService("Workspace")
_G.walker = 0
`,
		"running_server_start",
	)

	// Let the server's tick counter run well ahead of anything the client will
	// count, which is what a server that has been up for a while looks like.
	for _ in 0 ..< 600 {step_network(&server, &server_vm)}

	run_script(
		&client_vm,
		`assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39314))`,
		"running_client_start",
	)
	// Deliberately fewer frames than the handshake needs, so this asserts the
	// join is right before any offset estimate could have been folded in.
	for _ in 0 ..< 40 {
		step_network(&server, &server_vm)
		step_network(&client, &client_vm)
	}
	// Now move the part, after the client is connected, and keep moving it. A
	// static part cannot expose a stale render target, because every sample the
	// client holds for it says the same thing; a moving one makes "clamped to the
	// oldest sample" a visibly wrong position.
	client_service := service_of(&client)
	assert(client_service.handshake_complete, "the client never completed the handshake")
	assert(
		!client_service.time_offset_measured,
		"this case was supposed to run before any offset was measured",
	)

	for step in 0 ..< 240 {
		run_script(
			&server_vm,
			`
_G.walker += 1
game:GetService("Workspace"):FindFirstChild("Anchored").CFrame = CFrame.new(_G.walker, 0, 0)
`,
			"running_server_ramp",
		)
		step_network(&server, &server_vm)
		step_network(&client, &client_vm)
	}

	// The part has walked 240 studs. A client clamped to its oldest buffered
	// sample is roughly 32 snapshots behind, which is 32 studs on a ramp this
	// steep, so the tolerance only has to absorb interpolation and smoothing.
	run_script(
		&client_vm,
		`
local x = game:GetService("Workspace"):FindFirstChild("Anchored").CFrame.Position.X
assert(
    x > 200,
    "a client that joined a running server rendered a stale position, got " .. tostring(x)
)
`,
		"running_client_converged",
	)

	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "running_client_stop")
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "running_server_stop")
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
}

main :: proc() {
	offset_is_measured()
	stop_clears_offset()
	render_uses_server_timebase()
	joins_a_running_server()
	fmt.println("REPLICATION_TIMEBASE_SMOKE_PASSED")
}
