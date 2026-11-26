package main

import services "../src/engine/services"
import "core:fmt"

main :: proc() {
	service: services.ReplicatorService
	peer: services.Replication_Transport_Peer
	unrelated_peer: services.Replication_Transport_Peer
	service.mode = .Client
	service.remote = &peer

	assert(
		!services.remote_can_send_to_peer(&service, &peer, 1),
		"unhandshaken client cannot target server",
	)
	assert(
		!services.remote_send_fire(&service, &peer, 1, nil),
		"unhandshaken client reliable event refused",
	)
	assert(
		!services.remote_send_invoke_request(&service, &peer, 1, 2, nil),
		"unhandshaken client invoke refused",
	)

	service.handshake_complete = true
	assert(
		services.remote_can_send_to_peer(&service, &peer, 1),
		"client can target its authenticated server",
	)
	assert(
		!services.remote_can_send_to_peer(&service, &unrelated_peer, 1),
		"client cannot target unrelated peer",
	)
	assert(!services.remote_can_send_to_peer(&service, &peer, 0), "zero entity ID refused")

	service.mode = .Server
	assert(
		!services.remote_can_send_to_peer(&service, &peer, 1),
		"server cannot send to unknown peer",
	)
	assert(
		!services.remote_send_fire(&service, &peer, 1, nil),
		"server does not send reliable event to unknown peer",
	)
	assert(
		!services.remote_send_invoke_request(&service, &peer, 1, 2, nil),
		"server does not send invoke to unknown peer",
	)
	fmt.println("SECURITY_REMOTE_GATE_SMOKE_PASSED")
}
