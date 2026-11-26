package main

import kineffi "../src/engine/bindings"
import "core:fmt"
import "core:strings"
import "core:time"

DEFAULT_SEND_RATE :: i32(4 * 1024 * 1024)
TEST_SEND_RATE :: i32(2 * 1024 * 1024)

main :: proc() {
	assert(kineffi.Kine_Gns_Init())
	defer kineffi.Kine_Gns_Kill()
	ip := strings.clone_to_cstring("127.0.0.1")
	defer delete(ip)
	server := kineffi.Kine_Gns_CreateServer(ip, 39859, 2)
	client := kineffi.Kine_Gns_CreateClient()
	assert(server != nil && client != nil)
	defer kineffi.Kine_Gns_Destroy(server)
	defer kineffi.Kine_Gns_Destroy(client)

	assert(kineffi.Kine_Gns_GetSendRate(server) == DEFAULT_SEND_RATE)
	assert(kineffi.Kine_Gns_GetSendRate(client) == DEFAULT_SEND_RATE)
	assert(!kineffi.Kine_Gns_SetSendRate(client, 0))
	assert(!kineffi.Kine_Gns_SetSendRate(client, 16 * 1024 - 1))
	assert(!kineffi.Kine_Gns_SetSendRate(client, 64 * 1024 * 1024 + 1))
	assert(kineffi.Kine_Gns_GetSendRate(client) == DEFAULT_SEND_RATE)


	assert(kineffi.Kine_Gns_SetSendRate(server, TEST_SEND_RATE))
	assert(kineffi.Kine_Gns_SetSendRate(client, TEST_SEND_RATE))
	assert(kineffi.Kine_Gns_GetSendRate(server) == TEST_SEND_RATE)
	assert(kineffi.Kine_Gns_GetSendRate(client) == TEST_SEND_RATE)
	peer := kineffi.Kine_Gns_Connect(client, ip, 39859)
	assert(peer != 0)

	started := time.tick_now()
	client_connected, server_connected, received := false, false, false
	server_peer: u32
	sent := false
	payload := [?]u8{'r', 'a', 't', 'e'}

	for time.tick_since(started) < 4 * time.Second && !received {
		event: kineffi.KineGnsEvent
		for kineffi.Kine_Gns_Poll(server, &event) {
			if event.type == 1 {
				server_connected = true
				server_peer = event.peer
			}
			if event.type == 3 {
				assert(event.data_size == len(payload))
				assert(event.data != nil)
				for i in 0 ..< len(payload) {assert(event.data[i] == payload[i])}
				received = true
			}
		}
		for kineffi.Kine_Gns_Poll(client, &event) {
			if event.type == 1 {client_connected = true}
		}
		if server_connected && client_connected && !sent {

			assert(kineffi.Kine_Gns_SetSendRate(server, DEFAULT_SEND_RATE))
			assert(kineffi.Kine_Gns_SetSendRate(client, DEFAULT_SEND_RATE))
			assert(kineffi.Kine_Gns_GetSendRate(server) == DEFAULT_SEND_RATE)
			assert(kineffi.Kine_Gns_GetSendRate(client) == DEFAULT_SEND_RATE)
			assert(kineffi.Kine_Gns_Send(client, peer, 1, &payload[0], len(payload), true, false))
			sent = true
		}
		time.sleep(2 * time.Millisecond)
	}

	assert(client_connected && server_connected && received)
	kineffi.Kine_Gns_Close(client, peer, false)
	fmt.println("REPLICATION_SEND_RATE_NATIVE_SMOKE_PASSED")
}
