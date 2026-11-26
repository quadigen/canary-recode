package main

import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)
	valid := [6]u8{0x82, 0x80, 0, 0, 0, 0}
	opcode, fin, payload, total, status := services.replication_ws_parse_frame(valid[:])
	assert(status == .Full && opcode == services.WS_OP_BINARY && fin)
	assert(len(payload) == 0 && total == 6)

	unmasked := [2]u8{0x82, 0}
	_, _, _, _, status = services.replication_ws_parse_frame(unmasked[:])
	assert(status == .Error, "server must reject unmasked client frames")

	reserved := [6]u8{0xC2, 0x80, 0, 0, 0, 0}
	_, _, _, _, status = services.replication_ws_parse_frame(reserved[:])
	assert(status == .Error, "server must reject reserved WebSocket flags")

	fragmented_ping := [6]u8{0x09, 0x80, 0, 0, 0, 0}
	_, _, _, _, status = services.replication_ws_parse_frame(fragmented_ping[:])
	assert(status == .Error, "control frames must not be fragmented")

	oversized_ping := [4]u8{0x89, 0xFE, 0, 126}
	_, _, _, _, status = services.replication_ws_parse_frame(oversized_ping[:])
	assert(status == .Error, "control frames must be at most 125 bytes")

	assert(services.replication_ws_fragment_fits(0, services.WS_MAX_MESSAGE))
	assert(services.replication_ws_fragment_fits(services.WS_MAX_MESSAGE - 1, 1))
	assert(!services.replication_ws_fragment_fits(services.WS_MAX_MESSAGE - 1, 2))
	assert(!services.replication_ws_fragment_fits(services.WS_MAX_MESSAGE + 1, 0))

	peer: services.Replication_Transport_Peer
	network: services.ReplicatorService
	network.mode = .Server
	append(
		&network.peers,
		services.Replication_Peer {
			peer = &peer,
			handshake_complete = true,
			known = make(map[u32]u64),
		},
	)
	defer {
		delete(network.peers[0].known)
		delete(network.peers)
	}

	ack := [9]u8{'K', 'R', 'P', 13, 4, 0, 0, 0, 0}
	for _ in 0 ..< services.REPLICATION_MAX_CLIENT_PACKETS_PER_SECOND + 20 {
		services.replication_receive(&network, nil, &peer, ack[:])
	}
	assert(
		network.peers[0].receive_rate_count == services.REPLICATION_MAX_CLIENT_PACKETS_PER_SECOND,
	)
	assert(network.rejected_packets == 20, "untrusted ACK packets must be rate limited")
	network.clock = 1.1
	services.replication_receive(&network, nil, &peer, ack[:])
	assert(network.peers[0].receive_rate_count == 1, "packet budget should reset")
	assert(network.rejected_packets == 20)
	fmt.println("SECURITY_NETWORK_WS_SMOKE_PASSED")
}
