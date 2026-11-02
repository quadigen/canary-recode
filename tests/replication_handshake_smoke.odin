package main

import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:math"

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
	services.Replication_Step(service_of(environment), script_vm.L, 1.0 / 60.0)
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


	assert(
		len(server_service.peers) == 1,
		fmt.tprintf("the server should hold exactly one peer, got %d", len(server_service.peers)),
	)
	peer := server_service.peers[0]
	assert(peer.handshake_complete, "the server never completed the handshake with a valid client")
	assert(
		client_service.handshake_complete,
		"the client never completed the handshake with a valid server",
	)
	assert(
		client_service.handshake_status == services.Replication_Handshake_Ok,
		"the client reported a non-OK handshake status",
	)
	assert(peer.player != nil, "an authenticated peer must own a player object")
	assert(
		server_service.version_mismatches == 0,
		"a matching client must not be counted as a version mismatch",
	)
	assert(server_service.auth_failures == 0, "a tokenless client must not be an auth failure")


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

	assert(
		peer.client_capabilities != 0,
		"the server did not record the client's advertised capabilities",
	)
	assert(
		client_service.server_capabilities != 0,
		"the client did not record the server's advertised capabilities",
	)


	assert(peer.server_nonce != 0, "the server issued no nonce")
	assert(server_service.server_nonce == 0, "a server must not hold a single shared nonce")
	assert(
		client_service.server_nonce == peer.server_nonce,
		"the client did not adopt the server nonce",
	)

	run_script(
		&client_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"handshake_happy_client_stop",
	)
	run_script(
		&server_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"handshake_happy_server_stop",
	)
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
}


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

	settle(&server, &server_vm, &client, &client_vm, 300)

	client_service := service_of(&client)
	assert(client_service.time_sync_sequence >= 2, "the client sent too few time sync samples")


	assert(
		math.abs(f64(client_service.time_offset)) < 1.0,
		fmt.tprintf("time offset estimate drifted to %f seconds", client_service.time_offset),
	)

	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "timesync_client_stop")
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "timesync_server_stop")
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
}


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


	for peer in server_service.peers {
		assert(peer.player == nil, "a refused client was still given a player object")
	}

	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "auth_client_stop")
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "auth_server_stop")
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
}


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

	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "auth_ok_client_stop")
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "auth_ok_server_stop")
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
}


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


	settle(&server, &server_vm, &client, &client_vm, 30)
	malformed_before := server_service.malformed_packets
	rejected_before := server_service.rejected_packets
	_ = client_service


	frame: [dynamic]u8
	defer delete(frame)
	for kind in ([?]u8{200, 6, 0, 255}) {
		clear(&frame)
		append(&frame, 'K', 'R', 'P', u8(services.Replication_Protocol_Version), kind)
		append(&frame, 1, 2, 3, 4)


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


	clear(&frame)
	append(&frame, 'K', 'R', 'P', 1, 7)
	append(&frame, 0, 0, 0, 0)
	services.replication_receive(server_service, server_vm.L, nil, frame[:])
	assert(
		server_service.malformed_packets == malformed_before + 2,
		"an ancient protocol revision was not refused at the framing layer",
	)

	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "reserved_client_stop")
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "reserved_server_stop")
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
}


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


	assert(
		services.replication_schema_hash(server_service) ==
		services.replication_schema_hash(client_service),
		"identical builds produced different schema fingerprints",
	)
	assert(
		client_service.handshake_complete && server_service.schema_mismatches == 0,
		"matching builds were refused",
	)


	bare: ^services.ReplicatorService = new(services.ReplicatorService)
	no_classes := services.replication_schema_hash(bare)
	free(bare)
	assert(
		no_classes != services.replication_schema_hash(server_service),
		"the schema fingerprint did not depend on the registered classes",
	)


	assert(
		services.replication_schema_hash(server_service) ==
		services.replication_schema_hash(server_service),
		"the schema fingerprint is not deterministic",
	)

	server_peer: ^services.Replication_Transport_Peer
	for &peer in server_service.peers {
		peer.handshake_complete = false
		peer.player = nil
		server_peer = peer.peer
	}
	assert(server_peer != nil, "the server has no peer to send a mismatched HELLO to")


	frame: [dynamic]u8
	defer delete(frame)
	append(&frame, 'K', 'R', 'P', u8(services.Replication_Protocol_Version), 1)
	append(&frame, u8(services.Replication_Protocol_Version), 0, 0, 0)
	append(&frame, 0, 0, 0, 0)
	for shift := 0; shift < 64; shift += 8 {append(&frame, 0xFF)}
	append(&frame, 0, 0, 0, 0)
	before := server_service.schema_mismatches
	services.replication_receive(server_service, server_vm.L, server_peer, frame[:])
	assert(
		server_service.schema_mismatches == before + 1,
		"a HELLO with a foreign schema fingerprint was accepted",
	)


	assert(
		server_service.version_mismatches == 0,
		"a schema skew was misreported as a protocol revision skew",
	)
	for peer in server_service.peers {
		if peer.peer == server_peer {
			assert(peer.player == nil, "a build-skewed client was given a player object")
		}
	}


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
	append(&frame2, 1, 0, 0, 0)
	append(&frame2, 0, 0, 0, 0)
	append(&frame2, 7, 0, 0, 0)
	append(&frame2, 30, 0, 0, 0)
	services.replication_receive(client_service, client_vm.L, client_service.remote, frame2[:])
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

	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "schema_client_stop")
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "schema_server_stop")
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
}


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


	frame: [dynamic]u8
	defer delete(frame)
	append(&frame, 'K', 'R', 'P', u8(services.Replication_Protocol_Version), 3)
	append(&frame, u8(services.Replication_Handshake_Schema_Mismatch))
	append(&frame, u8(services.Replication_Protocol_Version), 0, 0, 0)
	append(&frame, 0, 0, 0, 0)
	for shift := 0; shift < 64; shift += 8 {append(&frame, 0xFF)}
	append(&frame, 1, 0, 0, 0)
	append(&frame, 0, 0, 0, 0)
	append(&frame, 7, 0, 0, 0)
	append(&frame, 30, 0, 0, 0)
	services.replication_receive(client_service, client_vm.L, client_service.remote, frame[:])
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
	services.replication_receive(client_service, client_vm.L, client_service.remote, frame[:])
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
	run_script(
		&server_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"reported_schema_server_stop",
	)
	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
}


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


	client_service.handshake_complete = false
	client_service.connected = false
	client_service.handshake_status = 0
	client_service.version_mismatches = 0
	mismatches_before := client_service.version_mismatches

	frame: [dynamic]u8
	defer delete(frame)
	append(&frame, 'K', 'R', 'P', u8(services.Replication_Protocol_Version), 3)


	append(&frame, u8(services.Replication_Handshake_Ok))
	append(&frame, 99, 0, 0, 0)
	append(&frame, 0, 0, 0, 0)


	schema := services.replication_schema_hash(client_service)
	for shift := 0; shift < 64; shift += 8 {append(&frame, u8(schema >> u64(shift)))}
	append(&frame, 1, 0, 0, 0)
	append(&frame, 0, 0, 0, 0)
	append(&frame, 7, 0, 0, 0)
	append(&frame, 30, 0, 0, 0)
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


	server_service := service_of(&server)
	mismatches_server_before := server_service.version_mismatches


	server_peer: ^services.Replication_Transport_Peer
	for &peer in server_service.peers {
		peer.handshake_complete = false
		peer.player = nil
		server_peer = peer.peer
	}
	assert(server_peer != nil, "the server has no peer to send a mismatched HELLO to")
	frame2: [dynamic]u8
	defer delete(frame2)
	append(&frame2, 'K', 'R', 'P', u8(services.Replication_Protocol_Version), 1)
	append(&frame2, 99, 0, 0, 0)
	append(&frame2, 0, 0, 0, 0)
	server_schema := services.replication_schema_hash(server_service)
	for shift := 0; shift < 64; shift += 8 {append(&frame2, u8(server_schema >> u64(shift)))}
	append(&frame2, 0, 0, 0, 0)
	services.replication_receive(server_service, server_vm.L, server_peer, frame2[:])
	assert(
		server_service.version_mismatches == mismatches_server_before + 1,
		"a mismatched HELLO was not refused by the server",
	)
	for peer in server_service.peers {
		if peer.peer == server_peer {
			assert(peer.player == nil, "a mismatched client was given a player object")
		}
	}

	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "version_client_stop")
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
