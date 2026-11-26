#+build !js
package services

import kineffi "../bindings"
import "core:fmt"
import "core:net"
import "core:strings"

Replication_Transport_Peer_Kind :: enum {
	SteamNetworkingSockets,
	WebSocket,
}

Replication_Transport_Peer :: struct {
	kind:     Replication_Transport_Peer_Kind,
	gns_host: kineffi.KineGnsHost,
	gns_peer: u32,
	ws:       ^Replication_Ws_Connection,
}

Replication_Ws_Connection :: struct {
	host:             ^Replication_Transport_Host,
	connected_at_ms:  u32,
	socket:           net.TCP_Socket,
	handshake_done:   bool,
	closing:          bool,
	disconnect_fired: bool,
	read_buffer:      [dynamic]u8,
	write_buffer:     [dynamic]u8,
	write_offset:     int,
	fragment:         [dynamic]u8,
	fragment_opcode:  u8,
	peer:             ^Replication_Transport_Peer,
}

Replication_Transport_Host :: struct {
	gns_host:          kineffi.KineGnsHost,
	ws_listener:       ^net.TCP_Socket,
	ws_connections:    [dynamic]^Replication_Ws_Connection,
	gns_peer_index:    map[u32]^Replication_Transport_Peer,
	retired_gns_peers: [dynamic]^Replication_Transport_Peer,
	client_peer:       Replication_Transport_Peer,
	pending:           [dynamic]Replication_Transport_Event,
	pending_head:      int,
}

Replication_Transport_Event :: struct {
	type:    Replication_Transport_Event_Type,
	peer:    ^Replication_Transport_Peer,
	channel: u8,
	data:    []u8,
}

transport_init :: proc() -> bool {
	if !kineffi.Kine_Gns_Init() {
		fmt.eprintln("Could not initialize SteamNetworkingSockets")
		return false
	}
	return true
}

transport_deinit :: proc() {kineffi.Kine_Gns_Kill()}

transport_time_get :: proc() -> u32 {return kineffi.Kine_Gns_TimeMs()}


transport_resolve_ipv4 :: proc(address: string) -> (string, bool) {
	if address == "" || address == "0.0.0.0" {
		return "0.0.0.0", true
	}
	endpoint, err := net.resolve_ip4(address)
	if err != nil {return "", false}
	return net.address_to_string(endpoint.address), true
}

transport_host_create_server :: proc(
	address: string,
	port: u16,
	max_peers: int,
	channels: int,
) -> ^Replication_Transport_Host {
	if channels <= 0 || max_peers <= 0 {return nil}
	bind_address, ok := transport_resolve_ipv4(address)
	if !ok {
		fmt.eprintf("Could not resolve server bind address %s\n", address)
		return nil
	}
	name := strings.clone_to_cstring(bind_address)
	defer delete(name)
	host := new(Replication_Transport_Host)
	host.gns_host = kineffi.Kine_Gns_CreateServer(name, port, i32(max_peers))
	host.gns_peer_index = make(map[u32]^Replication_Transport_Peer)
	if host.gns_host == nil {
		delete(host.gns_peer_index)
		free(host)
		return nil
	}
	replication_ws_listen(host, address, port)
	return host
}

transport_host_create_client :: proc() -> ^Replication_Transport_Host {
	host := new(Replication_Transport_Host)
	host.gns_host = kineffi.Kine_Gns_CreateClient()
	host.gns_peer_index = make(map[u32]^Replication_Transport_Peer)
	if host.gns_host == nil {
		delete(host.gns_peer_index)
		free(host)
		return nil
	}
	return host
}

transport_host_connect :: proc(
	host: ^Replication_Transport_Host,
	address: string,
	port: u16,
	channels: int,
) -> ^Replication_Transport_Peer {
	if host == nil || host.gns_host == nil || channels <= 0 {return nil}
	remote_address, ok := transport_resolve_ipv4(address)
	if !ok {
		fmt.eprintf("Could not resolve server address %s\n", address)
		return nil
	}
	name := strings.clone_to_cstring(remote_address)
	defer delete(name)
	remote := kineffi.Kine_Gns_Connect(host.gns_host, name, port)
	if remote == 0 {return nil}
	host.client_peer = {
		kind     = .SteamNetworkingSockets,
		gns_host = host.gns_host,
		gns_peer = remote,
	}
	return &host.client_peer
}

replication_transport_wrap_gns_peer :: proc(
	host: ^Replication_Transport_Host,
	peer: u32,
) -> ^Replication_Transport_Peer {
	if peer != 0 && host.client_peer.gns_peer == peer {return &host.client_peer}
	if existing, ok := host.gns_peer_index[peer]; ok {return existing}
	wrapper := new(Replication_Transport_Peer)
	wrapper.kind = .SteamNetworkingSockets
	wrapper.gns_host = host.gns_host
	wrapper.gns_peer = peer
	host.gns_peer_index[peer] = wrapper
	return wrapper
}

transport_take_pending :: proc(
	host: ^Replication_Transport_Host,
) -> (
	Replication_Transport_Event,
	bool,
) {
	if host.pending_head >= len(host.pending) {return {}, false}
	event := host.pending[host.pending_head]
	host.pending_head += 1
	if host.pending_head == len(host.pending) {
		clear(&host.pending)
		host.pending_head = 0
	}
	return event, true
}

transport_host_service :: proc(
	host: ^Replication_Transport_Host,
) -> (
	Replication_Transport_Event,
	bool,
) {
	if host == nil {return {}, false}


	for retired in host.retired_gns_peers {free(retired)}
	clear(&host.retired_gns_peers)
	if out, ok := transport_take_pending(host); ok {return out, true}

	event: kineffi.KineGnsEvent
	if host.gns_host != nil && kineffi.Kine_Gns_Poll(host.gns_host, &event) {
		out := Replication_Transport_Event {
			peer    = replication_transport_wrap_gns_peer(host, event.peer),
			channel = event.channel,
		}
		switch event.type {
		case 1:
			out.type = .CONNECT
		case 2:
			out.type = .DISCONNECT
			if event.peer != host.client_peer.gns_peer {
				delete_key(&host.gns_peer_index, event.peer)
				append(&host.retired_gns_peers, out.peer)
			}
		case 3:
			out.type = .RECEIVE
			if event.data_size > 0 && event.data != nil {
				out.data = make([]u8, int(event.data_size))
				copy(out.data, event.data[:int(event.data_size)])
			}
		case:
			return {}, false
		}
		return out, true
	}

	replication_ws_pump(host)
	return transport_take_pending(host)
}

transport_host_flush :: proc(host: ^Replication_Transport_Host) {
	if host == nil {return}
	replication_ws_flush(host)
	if host.gns_host != nil {kineffi.Kine_Gns_Flush(host.gns_host)}
}

transport_host_set_send_rate :: proc(
	host: ^Replication_Transport_Host,
	bytes_per_second: u32,
) -> bool {
	if host == nil ||
	   host.gns_host == nil ||
	   bytes_per_second > 64 * 1024 * 1024 ||
	   bytes_per_second < 16 * 1024 {
		return false
	}
	return kineffi.Kine_Gns_SetSendRate(host.gns_host, i32(bytes_per_second))
}

transport_host_destroy :: proc(host: ^Replication_Transport_Host) {
	if host == nil {return}
	replication_ws_shutdown(host)
	for index := host.pending_head; index < len(host.pending); index += 1 {
		transport_event_dispose(&host.pending[index])
	}
	delete(host.pending)
	for _, wrapper in host.gns_peer_index {free(wrapper)}
	delete(host.gns_peer_index)
	for retired in host.retired_gns_peers {free(retired)}
	delete(host.retired_gns_peers)
	if host.gns_host != nil {kineffi.Kine_Gns_Destroy(host.gns_host)}
	free(host)
}

transport_peer_send :: proc(
	peer: ^Replication_Transport_Peer,
	channel: u8,
	data: []u8,
	reliable: bool,
	unsequenced: bool = false,
) -> bool {
	if peer == nil {return false}
	switch peer.kind {
	case .SteamNetworkingSockets:
		if peer.gns_host == nil || peer.gns_peer == 0 {return false}
		if len(data) > 512 * 1024 - 1 {return false}
		return kineffi.Kine_Gns_Send(
			peer.gns_host,
			peer.gns_peer,
			channel,
			cast([^]u8)raw_data(data),
			u32(len(data)),
			reliable,
			unsequenced,
		)
	case .WebSocket:
		if unsequenced && (peer.ws == nil || len(peer.ws.write_buffer) > 16 * 1024) {return false}
		return replication_ws_send(peer, data)
	}
	return false
}

transport_peer_disconnect :: proc(peer: ^Replication_Transport_Peer) {
	if peer == nil {return}
	switch peer.kind {
	case .SteamNetworkingSockets:
		if peer.gns_host != nil && peer.gns_peer != 0 {
			kineffi.Kine_Gns_Close(peer.gns_host, peer.gns_peer, false)
		}
	case .WebSocket:
		replication_ws_close(peer)
	}
}

transport_peer_disconnect_now :: proc(peer: ^Replication_Transport_Peer) {
	if peer == nil {return}
	switch peer.kind {
	case .SteamNetworkingSockets:
		if peer.gns_host != nil && peer.gns_peer != 0 {
			kineffi.Kine_Gns_Close(peer.gns_host, peer.gns_peer, true)
		}
	case .WebSocket:
		replication_ws_close(peer)
	}
}

transport_peer_reset :: proc(peer: ^Replication_Transport_Peer) {
	if peer == nil {return}
	switch peer.kind {
	case .SteamNetworkingSockets:
		if peer.gns_host != nil && peer.gns_peer != 0 {
			kineffi.Kine_Gns_Close(peer.gns_host, peer.gns_peer, true)
		}
	case .WebSocket:
		replication_ws_close(peer)
	}
}

transport_peer_disconnected :: proc(peer: ^Replication_Transport_Peer) -> bool {
	if peer == nil {return true}
	switch peer.kind {
	case .SteamNetworkingSockets:
		return(
			peer.gns_host == nil ||
			peer.gns_peer == 0 ||
			!kineffi.Kine_Gns_IsActive(peer.gns_host, peer.gns_peer) \
		)
	case .WebSocket:
		return peer.ws == nil || peer.ws.closing
	}
	return true
}

transport_event_dispose :: proc(event: ^Replication_Transport_Event) {
	if event == nil {return}
	delete(event.data)
	event.data = nil
}
