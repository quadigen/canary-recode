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
		panic("replication ack suppression smoke failed")
	}
}

step_network :: proc(environment: ^engine_runtime.Environment, script_vm: ^vm.VM) {
	descriptor := services.Find_Service(&environment.services, "ReplicatorService")
	services.Replication_Step(cast(^services.ReplicatorService)descriptor.object, script_vm.L, 1.0 / 60.0)
}

// Steps both environments together for `count` frames.
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
-- CanQuery rides the extra property channel, so it also exercises suppression
-- for the asset/schema batch and not just the transform.
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:StartServer("127.0.0.1", 39213))
local part = Instance.new("Part")
part.Name = "StationaryPart"
part.CFrame = CFrame.new(0, 0, 0)
part.Size = Vector3.new(4, 1, 4)
part.CanQuery = false
part.Parent = game:GetService("Workspace")
local value = Instance.new("NumberValue")
value.Name = "Score"
value.Value = 5
value.Parent = game:GetService("ReplicatedStorage")
`,
		"ack_suppression_server_setup",
	)

	run_script(
		&client_vm,
		`
local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", { "CanQuery" }))
assert(r:ConnectClient("127.0.0.1", 39213))
`,
		"ack_suppression_client_setup",
	)

	// Let the initial snapshot land and the first acknowledgements get back to
	// the server. Until the server has a confirmed token for an entity it is
	// obliged to keep re-sending, so this window is expected to be busy.
	settle(&server, &server_vm, &client, &client_vm, 150)

	run_script(
		&client_vm,
		`
local part = game:GetService("Workspace"):FindFirstChild("StationaryPart")
assert(part, "stationary part should have replicated")
assert(math.abs(part.CFrame.Position.X) < 0.01, "unexpected initial x " .. tostring(part.CFrame.Position.X))
assert(part.Size == Vector3.new(4, 1, 4), "size should have replicated")
assert(part.CanQuery == false, "schema property should have replicated")
assert(game:GetService("ReplicatedStorage"):FindFirstChild("Score").Value == 5)
`,
		"ack_suppression_client_content",
	)

	// Measure a steady-state window where nothing on the server changes. If
	// suppression is working, this should be a trickle of acks and spawns for
	// newly relevant entities rather than a full snapshot every frame.
	descriptor := services.Find_Service(&server.services, "ReplicatorService")
	service := cast(^services.ReplicatorService)descriptor.object
	kind_before := service.diag_kind_counts
	subtype_before := service.diag_subtype_counts
	run_script(
		&server_vm,
		`
idle_bytes_before = game:GetService("ReplicatorService"):GetStats().bytesSent
idle_packets_before = game:GetService("ReplicatorService"):GetStats().packetsSent
idle_skipped_before = game:GetService("ReplicatorService"):GetStats().unchangedStatesSkipped
`,
		"ack_suppression_idle_before",
	)
	settle(&server, &server_vm, &client, &client_vm, 120)
	fmt.eprintln("")
	run_script(
		&server_vm,
		`
local stats = game:GetService("ReplicatorService"):GetStats()
idle_bytes = stats.bytesSent - idle_bytes_before
idle_packets = stats.packetsSent - idle_packets_before
idle_skipped = stats.unchangedStatesSkipped - idle_skipped_before

-- The content-token exchange has to be flowing in both directions, otherwise
-- the server can never safely suppress anything.
assert(stats.acksReceived > 0, "server received no acknowledgements")
assert(idle_skipped > 0, "nothing was suppressed while the scene was static")

-- A static scene must not cost a full snapshot per frame. 120 frames at 60Hz
-- with 2 entities would be well over 100 packets if suppression were broken.
assert(idle_packets < 60, "idle window sent " .. tostring(idle_packets) .. " packets, suppression is not engaging")`,
		"ack_suppression_idle_after",
	)
	// The remaining idle traffic is character input acknowledgement, which is
	// deduplicated per input sequence and unrelated to content suppression. The
	// assertion that matters is that the two content channels went completely
	// quiet. Kinds 5 and 6 multiplex frame types behind a leading subtype byte:
	// subtype 1 is part state, subtype 2 is a property.
	state_packets :=
		service.diag_subtype_counts[1][5] - subtype_before[1][5] +
		service.diag_subtype_counts[1][6] -
		subtype_before[1][6]
	property_packets :=
		service.diag_subtype_counts[2][5] - subtype_before[2][5] +
		service.diag_subtype_counts[2][6] -
		subtype_before[2][6]
	spawn_packets := service.diag_kind_counts[7] - kind_before[7]
	assert(
		state_packets == 0,
		fmt.tprintf("static scene still sent %d part state packets", state_packets),
	)
	assert(
		property_packets == 0,
		fmt.tprintf("static scene still sent %d property packets", property_packets),
	)
	assert(
		spawn_packets == 0,
		fmt.tprintf("static scene still sent %d spawn packets", spawn_packets),
	)

	// Now change real content and confirm it still flows. A suppressed channel
	// that never wakes up is just as broken as one that never sleeps.
	moved_before := service.diag_subtype_counts[1][5] + service.diag_subtype_counts[1][6]
	run_script(
		&server_vm,
		`
game:GetService("Workspace"):FindFirstChild("StationaryPart").CFrame = CFrame.new(40, 0, 0)
game:GetService("ReplicatedStorage"):FindFirstChild("Score").Value = 9
`,
		"ack_suppression_server_change",
	)
	settle(&server, &server_vm, &client, &client_vm, 90)
	assert(
		service.diag_subtype_counts[1][5] + service.diag_subtype_counts[1][6] > moved_before,
		"a moved part produced no transform updates at all",
	)
	run_script(
		&client_vm,
		`
local part = game:GetService("Workspace"):FindFirstChild("StationaryPart")
assert(math.abs(part.CFrame.Position.X - 40) < 0.5, "moved part should follow, got " .. tostring(part.CFrame.Position.X))
assert(game:GetService("ReplicatedStorage"):FindFirstChild("Score").Value == 9, "changed value should replicate")
`,
		"ack_suppression_client_change",
	)

	// And a second idle window after the change, to prove the new content is
	// acknowledged and the channels settle back down.
	kind_before = service.diag_kind_counts
	subtype_before = service.diag_subtype_counts
	run_script(
		&server_vm,
		`
settled_bytes_before = game:GetService("ReplicatorService"):GetStats().bytesSent
settled_packets_before = game:GetService("ReplicatorService"):GetStats().packetsSent
`,
		"ack_suppression_settled_before",
	)
	settle(&server, &server_vm, &client, &client_vm, 120)
	resettled_state :=
		service.diag_subtype_counts[1][5] - subtype_before[1][5] +
		service.diag_subtype_counts[1][6] -
		subtype_before[1][6]
	resettled_property :=
		service.diag_subtype_counts[2][5] - subtype_before[2][5] +
		service.diag_subtype_counts[2][6] -
		subtype_before[2][6]
	assert(
		resettled_state == 0,
		fmt.tprintf("transform channel sent %d packets after re-settling", resettled_state),
	)
	assert(
		resettled_property == 0,
		fmt.tprintf("property channel sent %d packets after re-settling", resettled_property),
	)
	run_script(
		&server_vm,
		`
local stats = game:GetService("ReplicatorService"):GetStats()
assert(stats.malformedPackets == 0, "no snapshot should be malformed")
`,
		"ack_suppression_settled_after",
	)

	run_script(
		&client_vm,
		`
local stats = game:GetService("ReplicatorService"):GetStats()
assert(stats.acksSent > 0, "client sent no acknowledgements")
assert(stats.statesApplied > 0, "client applied no transform state")
assert(stats.malformedPackets == 0)
game:GetService("ReplicatorService"):Stop()
`,
		"ack_suppression_client_stats",
	)
	run_script(
		&server_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"ack_suppression_server_stop",
	)

	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
	fmt.println("REPLICATION_ACK_SUPPRESSION_SMOKE_PASSED")
}
