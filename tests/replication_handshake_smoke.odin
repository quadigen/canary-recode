package main

import "core:fmt"
import "core:math"
import enet "vendor:ENet"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("replication handshake smoke failed")
	}
}

service_of :: proc(environment: ^engine_runtime.Environment) -> ^services.ReplicatorService {
	descriptor := services.Find_Service(&environment.services, "ReplicatorService")
	return cast(^services.ReplicatorService)descriptor.object
}

step_network :: proc(environment: ^engine_runtime.Environment, script_vm: ^vm.VM) {
	services.Replication_Step(
		service_of(environment),
		script_vm.L,
		1.0 / 60.0,
	)
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

// ---------------------------------------------------------------------------
// 1. A correct client completes the handshake and is admitted.
// ---------------------------------------------------------------------------
happy_path :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)

	run_script(
		&server_vm,
		`assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39241))`,
		"handshake_server_start",
	)
	run_script(
		&client_vm,
		`assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39241))`,
		"handshake_client_start",
	)
	settle(&server, &server_vm, &client, &client_vm, 120)

	server_service := service_of(&server)
	client_service := service_of(&client)
	// The server tracks admission per peer because one bad client must not
	// describe the health of the whole server, whereas the client only ever has
	// one connection and so can carry the flag on the service itself.
	assert(
		len(server_service.peers) == 1,
		fmt.tprintf("the server should hold exactly one peer, got %d", len(server_service.peers)),
	)
	peer := server_service.peers[0]
	assert(
		peer.handshake_complete,
		"the server never completed the handshake with a valid client",
	)
	assert(
		client_service.handshake_complete,
		"the client never completed the handshake with a valid server",
	)
	assert(
		client_service.handshake_status == services.Replication_Handshake_Ok,
		"the client reported a non-OK handshake status",
	)
	assert(
		peer.player != nil,
		"an authenticated peer must own a player object",
	)
	assert(
		server_service.version_mismatches == 0,
		"a matching client must not be counted as a version mismatch",
	)
	assert(server_service.auth_failures == 0, "a tokenless client must not be an auth failure")
	// A matched pair must agree on the replicated class surface, because a
	// disagreement is refused outright and the client simply never joins. Both
	// ends are asked independently rather than trusting that the connection
	// succeeded, so a hash that is wrong in the same way on both sides still
	// fails here instead of hiding behind a successful handshake.
	assert(
		server_service.schema_mismatches == 0,
		"a matching client was refused for a class surface difference",
	)
	assert(
		client_service.schema_mismatches == 0,
		"a matching client counted a class surface difference of its own",
	)
	assert(
		services.replication_schema_hash(server_service) ==
			services.replication_schema_hash(client_service),
		"a server and client built from the same source disagreed on the replicated class surface",
	)
	// Capabilities are exchanged in both directions, not just assumed locally.
	assert(
		peer.client_capabilities != 0,
		"the server did not record the client's advertised capabilities",
	)
	assert(
		client_service.server_capabilities != 0,
		"the client did not record the server's advertised capabilities",
	)
	// The server issues a nonce that the client must echo, otherwise its time
	// samples cannot be trusted. It is held per peer, not per service, so that a
	// second client connecting cannot invalidate the first one's samples.
	assert(peer.server_nonce != 0, "the server issued no nonce")
	assert(
		server_service.server_nonce == 0,
		"a server must not hold a single shared nonce",
	)
	assert(
		client_service.server_nonce == peer.server_nonce,
		"the client did not adopt the server nonce",
	)

	run_script(
		&client_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"handshake_happy_client_stop",
	)
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "handshake_happy_server_stop")
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
}

// ---------------------------------------------------------------------------
// 2. Time sync converges so the client can age samples on the server timebase.
// ---------------------------------------------------------------------------
time_sync :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)

	run_script(
		&server_vm,
		`assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39242))`,
		"timesync_server_start",
	)
	run_script(
		&client_vm,
		`assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39242))`,
		"timesync_client_start",
	)
	// The sync interval is a second, so this has to run past a few of them.
	settle(&server, &server_vm, &client, &client_vm, 300)

	client_service := service_of(&client)
	assert(
		client_service.time_sync_sequence >= 2,
		"the client sent too few time sync samples",
	)
	// Both processes step the same 1/60 delta, so their clocks track closely and
	// the true offset is near zero. The assertion is that an estimate exists at
	// all and is small, not that it is exactly zero: a non-synchronised client
	// would leave the field at its initial value with no way to tell that apart
	// from a genuinely zero offset, so the sample count above carries the real
	// weight here.
	assert(
		math.abs(f64(client_service.time_offset)) < 1.0,
		fmt.tprintf("time offset estimate drifted to %f seconds", client_service.time_offset),
	)

	run_script(
		&client_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"timesync_client_stop",
	)
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "timesync_server_stop")
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
}

// ---------------------------------------------------------------------------
// 3. A wrong join token is refused and never becomes a player.
// ---------------------------------------------------------------------------
auth_rejection :: proc() {
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
assert(r:SetJoinToken("correct-horse"))
assert(r:StartServer("127.0.0.1", 39243))
`,
		"auth_server_start",
	)
	run_script(
		&client_vm,
		`
local r = game:GetService("ReplicatorService")
assert(r:SetJoinToken("battery-staple"))
assert(r:ConnectClient("127.0.0.1", 39243))
`,
		"auth_client_start",
	)
	settle(&server, &server_vm, &client, &client_vm, 120)

	server_service := service_of(&server)
	client_service := service_of(&client)
	assert(server_service.auth_failures > 0, "a wrong token was not counted as an auth failure")
	assert(
		server_service.handshake_status == services.Replication_Handshake_Ok,
		"the server itself should still be healthy after refusing a client",
	)
	assert(
		!client_service.handshake_complete,
		"a client with a bad token must not consider itself connected",
	)
	assert(!client_service.connected, "a refused client must not report itself connected")
	// The decisive property: no player object was ever created, so nothing the
	// attacker sent was allowed to reach the simulation.
	for peer in server_service.peers {
		assert(
			peer.player == nil,
			"a refused client was still given a player object",
		)
	}

	run_script(
		&client_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"auth_client_stop",
	)
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "auth_server_stop")
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
}

// ---------------------------------------------------------------------------
// 4. A matching token is admitted, so the check above is not just always-fail.
// ---------------------------------------------------------------------------
auth_accepted :: proc() {
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
assert(r:SetJoinToken("correct-horse"))
assert(r:StartServer("127.0.0.1", 39244))
`,
		"auth_ok_server_start",
	)
	run_script(
		&client_vm,
		`
local r = game:GetService("ReplicatorService")
assert(r:SetJoinToken("correct-horse"))
assert(r:ConnectClient("127.0.0.1", 39244))
`,
		"auth_ok_client_start",
	)
	settle(&server, &server_vm, &client, &client_vm, 120)

	server_service := service_of(&server)
	assert(service_of(&client).handshake_complete, "a client with the right token was refused")
	assert(server_service.auth_failures == 0, "a valid token was counted as an auth failure")
	assert(len(server_service.peers) == 1, "the server should hold exactly one peer")
	assert(server_service.peers[0].player != nil, "an accepted client owns no player")

	run_script(
		&client_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"auth_ok_client_stop",
	)
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "auth_ok_server_stop")
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
}

// ---------------------------------------------------------------------------
// 5. Unknown and reserved kinds are counted as skew, not as corruption.
// ---------------------------------------------------------------------------
reserved_kinds :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)

	run_script(
		&server_vm,
		`assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39245))`,
		"reserved_server_start",
	)
	run_script(
		&client_vm,
		`assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39245))`,
		"reserved_client_start",
	)
	settle(&server, &server_vm, &client, &client_vm, 60)

	server_service := service_of(&server)
	client_service := service_of(&client)
	// Establish a clean baseline so the assertions below cannot be satisfied by
	// leftovers from the handshake.
	settle(&server, &server_vm, &client, &client_vm, 30)
	malformed_before := server_service.malformed_packets
	rejected_before := server_service.rejected_packets
	_ = client_service

	// Frame kinds the dispatcher does not know: one above every currently active
	// kind, one from a gap in the middle, and the zero kind. Each must land in
	// rejected_packets and none may land in malformed_packets.
	frame: [dynamic]u8
	defer delete(frame)
	for kind in ([?]u8{200, 6, 0, 255}) {
		clear(&frame)
		append(&frame, 'K', 'R', 'P', u8(services.Replication_Protocol_Version), kind)
		append(&frame, 1, 2, 3, 4)
		// peer is nil on purpose: an unknown kind must be rejected before any
		// peer-specific handling, and passing nil proves the dispatcher does not
		// touch the connection while routing it.
		services.replication_receive(server_service, server_vm.L, nil, frame[:])
	}
	assert(
		server_service.rejected_packets == rejected_before + 4,
		fmt.tprintf(
			"expected 4 unknown kinds to be rejected, got %d",
			server_service.rejected_packets - rejected_before,
		),
	)
	assert(
		server_service.malformed_packets == malformed_before,
		fmt.tprintf(
			"unknown kinds were charged as corruption: %d malformed",
			server_service.malformed_packets - malformed_before,
		),
	)

	// A frame with a broken header is a different failure and must still be
	// counted as malformed, otherwise a genuinely corrupt stream would hide.
	clear(&frame)
	append(&frame, 'X', 'R', 'P', 6, 7)
	append(&frame, 0, 0, 0, 0)
	services.replication_receive(server_service, server_vm.L, nil, frame[:])
	assert(
		server_service.malformed_packets == malformed_before + 1,
		"a bad magic header was not counted as malformed",
	)
	assert(
		server_service.rejected_packets == rejected_before + 4,
		"a bad header was also charged to the skew counter",
	)

	// A frame claiming an unsupported revision is refused at the framing layer
	// before dispatch, rather than being parsed with the wrong layout.
	clear(&frame)
	append(&frame, 'K', 'R', 'P', 1, 7)
	append(&frame, 0, 0, 0, 0)
	services.replication_receive(server_service, server_vm.L, nil, frame[:])
	assert(
		server_service.malformed_packets == malformed_before + 2,
		"an ancient protocol revision was not refused at the framing layer",
	)

	run_script(
		&client_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"reserved_client_stop",
	)
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "reserved_server_stop")
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
}

// ---------------------------------------------------------------------------
// 6. Two builds that agree on the protocol revision but replicate a different
//    property surface are refused, because otherwise they would agree on every
//    frame and silently disagree on every value.
// ---------------------------------------------------------------------------
schema_mismatch :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)

	run_script(
		&server_vm,
		`assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39247))`,
		"schema_server_start",
	)
	run_script(
		&client_vm,
		`assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39247))`,
		"schema_client_start",
	)
	settle(&server, &server_vm, &client, &client_vm, 120)

	server_service := service_of(&server)
	client_service := service_of(&client)

	// The real builds are identical, so the fingerprints must match and the
	// session must have been established. Without this the mismatch assertions
	// below could be satisfied by a hash that is simply always different.
	assert(
		services.replication_schema_hash(server_service) ==
			services.replication_schema_hash(client_service),
		"identical builds produced different schema fingerprints",
	)
	assert(
		client_service.handshake_complete && server_service.schema_mismatches == 0,
		"matching builds were refused",
	)
	// A fingerprint that is constant would pass everything above and catch
	// nothing, so it has to be a real function of the class surface. A service
	// with no class registry at all stands in for a build that registers nothing,
	// which is the cheapest way to move the input without editing the registry.
	bare: ^services.ReplicatorService = new(services.ReplicatorService)
	no_classes := services.replication_schema_hash(bare)
	free(bare)
	assert(
		no_classes != services.replication_schema_hash(server_service),
		"the schema fingerprint did not depend on the registered classes",
	)
	// And it has to be stable, or two peers of the same build could disagree and
	// refuse each other at random.
	assert(
		services.replication_schema_hash(server_service) ==
			services.replication_schema_hash(server_service),
		"the schema fingerprint is not deterministic",
	)

	server_peer: ^enet.Peer
	for &peer in server_service.peers {
		peer.handshake_complete = false
		peer.player = nil
		server_peer = peer.peer
	}
	assert(server_peer != nil, "the server has no peer to send a mismatched HELLO to")

	// Same protocol revision, matching capabilities, but a fingerprint from a
	// build with a different replicated property surface.
	frame: [dynamic]u8
	defer delete(frame)
	append(&frame, 'K', 'R', 'P', u8(services.Replication_Protocol_Version), 1)
	append(&frame, u8(services.Replication_Protocol_Version), 0, 0, 0) // version, correct
	append(&frame, 0, 0, 0, 0) // capabilities
	for shift := 0; shift < 64; shift += 8 {append(&frame, 0xFF)}
	append(&frame, 0, 0, 0, 0) // token length
	before := server_service.schema_mismatches
	services.replication_receive(server_service, server_vm.L, server_peer, frame[:])
	assert(
		server_service.schema_mismatches == before + 1,
		"a HELLO with a foreign schema fingerprint was accepted",
	)
	// Counted separately from a revision mismatch, because the two are fixed by
	// different things and a server operator needs to know which one happened.
	assert(
		server_service.version_mismatches == 0,
		"a schema skew was misreported as a protocol revision skew",
	)
	for peer in server_service.peers {
		if peer.peer == server_peer {
			assert(
				peer.player == nil,
				"a build-skewed client was given a player object",
			)
		}
	}

	// The reverse direction: a server whose fingerprint disagrees with a client
	// that has already been told the session is fine. The client has to refuse it
	// itself, because it is the side that would misapply the state.
	client_service.handshake_complete = false
	client_service.connected = false
	client_service.handshake_status = 0
	client_service.schema_mismatches = 0
	frame2: [dynamic]u8
	defer delete(frame2)
	append(&frame2, 'K', 'R', 'P', u8(services.Replication_Protocol_Version), 3)
	append(&frame2, u8(services.Replication_Handshake_Ok))
	append(&frame2, u8(services.Replication_Protocol_Version), 0, 0, 0)
	append(&frame2, 0, 0, 0, 0)
	for shift := 0; shift < 64; shift += 8 {append(&frame2, 0xFF)}
	append(&frame2, 1, 0, 0, 0) // user id
	append(&frame2, 0, 0, 0, 0) // name length
	append(&frame2, 7, 0, 0, 0) // nonce
	append(&frame2, 30, 0, 0, 0) // snapshot rate
	services.replication_receive(
		client_service,
		client_vm.L,
		client_service.remote,
		frame2[:],
	)
	assert(
		client_service.schema_mismatches == 1,
		"a client adopted a session with a server that replicates a different surface",
	)
	assert(
		client_service.handshake_status == services.Replication_Handshake_Schema_Mismatch,
		"the client did not report a schema mismatch",
	)
	assert(
		!client_service.handshake_complete && !client_service.connected,
		"a schema-skewed client considered itself connected",
	)

	run_script(
		&client_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"schema_client_stop",
	)
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "schema_server_stop")
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
}

// ---------------------------------------------------------------------------
// 7. A client counts a schema mismatch the server reported, not just one it
//    found for itself. The server compares hashes before it authenticates, so
//    on a real skewed pair the client sees the rejection status rather than
//    reaching its own comparison. Both ends have to agree on the count, and a
//    rejection for some other reason must not inflate it.
// ---------------------------------------------------------------------------
server_reported_schema_mismatch :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)

	run_script(
		&server_vm,
		`assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39260))`,
		"reported_schema_server_start",
	)
	run_script(
		&client_vm,
		`assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39260))`,
		"reported_schema_client_start",
	)
	settle(&server, &server_vm, &client, &client_vm, 120)

	client_service := service_of(&client)
	assert(client_service.handshake_complete, "the baseline pair never connected")
	assert(
		client_service.schema_mismatches == 0,
		"a matched pair reported a schema mismatch out of nowhere",
	)

	// A WELCOME carrying the rejection status the server would send on skew.
	frame: [dynamic]u8
	defer delete(frame)
	append(&frame, 'K', 'R', 'P', u8(services.Replication_Protocol_Version), 3)
	append(&frame, u8(services.Replication_Handshake_Schema_Mismatch))
	append(&frame, u8(services.Replication_Protocol_Version), 0, 0, 0)
	append(&frame, 0, 0, 0, 0)
	for shift := 0; shift < 64; shift += 8 {append(&frame, 0xFF)}
	append(&frame, 1, 0, 0, 0) // user id
	append(&frame, 0, 0, 0, 0) // name length
	append(&frame, 7, 0, 0, 0) // nonce
	append(&frame, 30, 0, 0, 0) // snapshot rate
	services.replication_receive(
		client_service,
		client_vm.L,
		client_service.remote,
		frame[:],
	)
	assert(
		client_service.schema_mismatches == 1,
		fmt.tprintf(
			"a client that was told it has a different class surface did not count it: %d",
			client_service.schema_mismatches,
		),
	)
	assert(
		client_service.handshake_status == services.Replication_Handshake_Schema_Mismatch,
		"the client did not surface the server's schema rejection status",
	)
	assert(
		client_service.handshake_rejections == 1,
		"the rejection was not counted as a rejection",
	)

	// An auth rejection must stay out of the schema counter. Same payload
	// shape, different status.
	clear(&frame)
	append(&frame, 'K', 'R', 'P', u8(services.Replication_Protocol_Version), 3)
	append(&frame, u8(services.Replication_Handshake_Auth_Rejected))
	append(&frame, u8(services.Replication_Protocol_Version), 0, 0, 0)
	append(&frame, 0, 0, 0, 0)
	for shift := 0; shift < 64; shift += 8 {append(&frame, 0xFF)}
	append(&frame, 1, 0, 0, 0)
	append(&frame, 0, 0, 0, 0)
	append(&frame, 7, 0, 0, 0)
	append(&frame, 30, 0, 0, 0)
	services.replication_receive(
		client_service,
		client_vm.L,
		client_service.remote,
		frame[:],
	)
	assert(
		client_service.schema_mismatches == 1,
		"an auth rejection was counted as a schema mismatch",
	)
	assert(
		client_service.handshake_rejections == 2,
		"the auth rejection was not counted as a rejection",
	)

	run_script(
		&client_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"reported_schema_client_stop",
	)
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "reported_schema_server_stop")
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
}

// ---------------------------------------------------------------------------
// 8. A server speaking a different protocol revision is refused, not adopted.
// ---------------------------------------------------------------------------
version_mismatch :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)

	run_script(
		&server_vm,
		`assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39246))`,
		"version_server_start",
	)
	run_script(
		&client_vm,
		`assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39246))`,
		"version_client_start",
	)
	settle(&server, &server_vm, &client, &client_vm, 120)

	client_service := service_of(&client)
	assert(client_service.remote != nil, "the client never reached the server")

	// Drive the WELCOME branch directly with a revision this build does not
	// speak. Going through a real socket would mean shipping a second client
	// build, and the thing worth testing is the decision, not the transport.
	// The client's handshake state is rewound first so the refusal is judged
	// against a client that believes it has not connected yet.
	client_service.handshake_complete = false
	client_service.connected = false
	client_service.handshake_status = 0
	client_service.version_mismatches = 0
	mismatches_before := client_service.version_mismatches

	frame: [dynamic]u8
	defer delete(frame)
	append(&frame, 'K', 'R', 'P', u8(services.Replication_Protocol_Version), 3)
	// status = OK, so the only thing wrong is the revision below. A client that
	// adopted it would connect and then misparse every subsequent frame.
	append(&frame, u8(services.Replication_Handshake_Ok))
	append(&frame, 99, 0, 0, 0) // server version
	append(&frame, 0, 0, 0, 0) // capabilities
	// The schema fingerprint has to match too, otherwise the client would refuse
	// for the wrong reason and this would only prove the newer check works.
	schema := services.replication_schema_hash(client_service)
	for shift := 0; shift < 64; shift += 8 {append(&frame, u8(schema >> u64(shift)))}
	append(&frame, 1, 0, 0, 0) // user id
	append(&frame, 0, 0, 0, 0) // name length
	append(&frame, 7, 0, 0, 0) // nonce
	append(&frame, 30, 0, 0, 0) // snapshot rate
	services.replication_receive(client_service, client_vm.L, client_service.remote, frame[:])

	assert(
		client_service.version_mismatches == mismatches_before + 1,
		"a server on a different revision was not counted as a mismatch",
	)
	assert(
		client_service.handshake_status == services.Replication_Handshake_Version_Mismatch,
		fmt.tprintf(
			"handshake status should report a mismatch, got %d",
			client_service.handshake_status,
		),
	)
	assert(
		!client_service.handshake_complete && !client_service.connected,
		"a client adopted a session with a server it cannot speak to",
	)

	// The revision is checked before authentication and before any player
	// object exists, so a mismatched peer never gets as far as the simulation.
	// The server peer is rewound to its pre-handshake state for the same reason
	// as the client above: a second HELLO on a live session is answered with
	// "already complete" and would never reach the version check.
	server_service := service_of(&server)
	mismatches_server_before := server_service.version_mismatches
	// The client and the server are separate ENet hosts, so the client's peer
	// pointer is not the one the server knows. Use the server's own.
	server_peer: ^enet.Peer
	for &peer in server_service.peers {
		peer.handshake_complete = false
		peer.player = nil
		server_peer = peer.peer
	}
	assert(server_peer != nil, "the server has no peer to send a mismatched HELLO to")
	frame2: [dynamic]u8
	defer delete(frame2)
	append(&frame2, 'K', 'R', 'P', u8(services.Replication_Protocol_Version), 1)
	append(&frame2, 99, 0, 0, 0) // version
	append(&frame2, 0, 0, 0, 0) // capabilities
	server_schema := services.replication_schema_hash(server_service)
	for shift := 0; shift < 64; shift += 8 {append(&frame2, u8(server_schema >> u64(shift)))}
	append(&frame2, 0, 0, 0, 0) // token length
	services.replication_receive(server_service, server_vm.L, server_peer, frame2[:])
	assert(
		server_service.version_mismatches == mismatches_server_before + 1,
		"a mismatched HELLO was not refused by the server",
	)
	for peer in server_service.peers {
		if peer.peer == server_peer {
			assert(
				peer.player == nil,
				"a mismatched client was given a player object",
			)
		}
	}

	run_script(
		&client_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"version_client_stop",
	)
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "version_server_stop")
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
}

main :: proc() {
	happy_path()
	time_sync()
	auth_rejection()
	auth_accepted()
	reserved_kinds()
	schema_mismatch()
	server_reported_schema_mismatch()
	version_mismatch()
	fmt.println("REPLICATION_HANDSHAKE_SMOKE_PASSED")
}
