#+build !js
package services

import "core:fmt"
import "core:net"
import "core:strings"
import enet "vendor:ENet"

Replication_Transport_Peer_Kind :: enum { ENet, WebSocket }

Replication_Transport_Peer :: struct {
    kind:      Replication_Transport_Peer_Kind,
    enet_peer: ^enet.Peer,
    ws:        ^Replication_Ws_Connection,
}

Replication_Ws_Connection :: struct {
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
    enet_host:       ^enet.Host,
    ws_listener:     ^net.TCP_Socket,
    ws_connections:  [dynamic]^Replication_Ws_Connection,
    enet_peer_index: map[^enet.Peer]^Replication_Transport_Peer,
    client_peer:     Replication_Transport_Peer,
    pending:         [dynamic]Replication_Transport_Event,
    pending_head:    int,
}

Replication_Transport_Event :: struct {
    type:    Replication_Transport_Event_Type,
    peer:    ^Replication_Transport_Peer,
    channel: u8,
    data:    []u8,
}

transport_enet_users: int

transport_init :: proc() -> bool {
    if transport_enet_users == 0 && enet.initialize() != 0 {
        fmt.eprintln("Could not initialize ENet")
        return false
    }
    transport_enet_users += 1
    return true
}

transport_deinit :: proc() {
    if transport_enet_users > 0 {
        transport_enet_users -= 1
        if transport_enet_users == 0 {enet.deinitialize()}
    }
}

transport_time_get :: proc() -> u32 {return enet.time_get()}

transport_host_create_server :: proc(
    address: string, port: u16, max_peers: int, channels: int,
) -> ^Replication_Transport_Host {
    endpoint := enet.Address{port = port}
    if address != "" && address != "0.0.0.0" {
        name := strings.clone_to_cstring(address)
        defer delete(name)
        if enet.address_set_host(&endpoint, name) != 0 {
            fmt.eprintf("Could not resolve server bind address %s\n", address)
            return nil
        }
    }
    host := new(Replication_Transport_Host)
    host.enet_host = enet.host_create(&endpoint, uint(max_peers), uint(channels), 0, 0)
    host.enet_peer_index = make(map[^enet.Peer]^Replication_Transport_Peer)
    if host.enet_host == nil {
        delete(host.enet_peer_index)
        free(host)
        return nil
    }
    replication_ws_listen(host, address, port)
    return host
}

transport_host_create_client :: proc() -> ^Replication_Transport_Host {
    host := new(Replication_Transport_Host)
    host.enet_host = enet.host_create(nil, 1, 2, 0, 0)
    host.enet_peer_index = make(map[^enet.Peer]^Replication_Transport_Peer)
    if host.enet_host == nil {
        delete(host.enet_peer_index)
        free(host)
        return nil
    }
    return host
}

transport_host_connect :: proc(
    host: ^Replication_Transport_Host, address: string, port: u16, channels: int,
) -> ^Replication_Transport_Peer {
    if host == nil || host.enet_host == nil {return nil}
    endpoint := enet.Address{port = port}
    name := strings.clone_to_cstring(address)
    defer delete(name)
    if enet.address_set_host(&endpoint, name) != 0 {
        fmt.eprintf("Could not resolve server address %s\n", address)
        return nil
    }
    remote := enet.host_connect(host.enet_host, &endpoint, uint(channels), 0)
    if remote == nil {return nil}
    host.client_peer = {kind = .ENet, enet_peer = remote}
    return &host.client_peer
}

replication_transport_wrap_enet_peer :: proc(
    host: ^Replication_Transport_Host, peer: ^enet.Peer,
) -> ^Replication_Transport_Peer {
    if existing, ok := host.enet_peer_index[peer]; ok {return existing}
    if host.client_peer.enet_peer == peer {return &host.client_peer}
    wrapper := new(Replication_Transport_Peer)
    wrapper.kind = .ENet
    wrapper.enet_peer = peer
    host.enet_peer_index[peer] = wrapper
    return wrapper
}

transport_take_pending :: proc(host: ^Replication_Transport_Host) -> (Replication_Transport_Event, bool) {
    if host.pending_head >= len(host.pending) {return {}, false}
    event := host.pending[host.pending_head]
    host.pending_head += 1
    if host.pending_head == len(host.pending) {
        clear(&host.pending)
        host.pending_head = 0
    }
    return event, true
}

transport_host_service :: proc(host: ^Replication_Transport_Host) -> (Replication_Transport_Event, bool) {
    if host == nil {return {}, false}
    if out, ok := transport_take_pending(host); ok {return out, true}
    event: enet.Event
    if host.enet_host != nil && enet.host_service(host.enet_host, &event, 0) > 0 {
        out := Replication_Transport_Event{channel = event.channelID}
        switch event.type {
        case .CONNECT:
            out.type = .CONNECT
            out.peer = replication_transport_wrap_enet_peer(host, event.peer)
        case .DISCONNECT:
            out.type = .DISCONNECT
            out.peer = replication_transport_wrap_enet_peer(host, event.peer)
        case .RECEIVE:
            out.type = .RECEIVE
            out.peer = replication_transport_wrap_enet_peer(host, event.peer)
            if event.packet != nil {
                out.data = make([]u8, int(event.packet.dataLength))
                copy(out.data, event.packet.data[:int(event.packet.dataLength)])
                enet.packet_destroy(event.packet)
            }
        case .NONE:
        }
        return out, true
    }
    replication_ws_pump(host)
    return transport_take_pending(host)
}

transport_host_flush :: proc(host: ^Replication_Transport_Host) {
    if host == nil {return}
    replication_ws_flush(host)
    if host.enet_host != nil {enet.host_flush(host.enet_host)}
}

transport_host_destroy :: proc(host: ^Replication_Transport_Host) {
    if host == nil {return}
    replication_ws_shutdown(host)
    for index := host.pending_head; index < len(host.pending); index += 1 {
        transport_event_dispose(&host.pending[index])
    }
    delete(host.pending)
    for _, wrapper in host.enet_peer_index {free(wrapper)}
    delete(host.enet_peer_index)
    if host.enet_host != nil {enet.host_destroy(host.enet_host)}
    free(host)
}

transport_peer_send :: proc(
    peer: ^Replication_Transport_Peer, channel: u8, data: []u8, reliable: bool,
) -> bool {
    if peer == nil {return false}
    switch peer.kind {
    case .ENet:
        if peer.enet_peer == nil {return false}
        flags: enet.PacketFlags
        if reliable {flags += {.RELIABLE}} else {flags += {.UNRELIABLE_FRAGMENT}}
        packet := enet.packet_create(raw_data(data), uint(len(data)), flags)
        if packet == nil {return false}
        if enet.peer_send(peer.enet_peer, channel, packet) != 0 {
            enet.packet_destroy(packet)
            return false
        }
        return true
    case .WebSocket:
        return replication_ws_send(peer, data)
    }
    return false
}

transport_peer_disconnect :: proc(peer: ^Replication_Transport_Peer) {
    if peer == nil {return}
    switch peer.kind {
    case .ENet:
        if peer.enet_peer != nil {enet.peer_disconnect(peer.enet_peer, 0)}
    case .WebSocket:
        replication_ws_close(peer)
    }
}

transport_peer_disconnect_now :: proc(peer: ^Replication_Transport_Peer) {
    if peer == nil {return}
    switch peer.kind {
    case .ENet:
        if peer.enet_peer != nil {enet.peer_disconnect_now(peer.enet_peer, 0)}
    case .WebSocket:
        replication_ws_close(peer)
    }
}

transport_peer_reset :: proc(peer: ^Replication_Transport_Peer) {
    if peer == nil {return}
    switch peer.kind {
    case .ENet:
        if peer.enet_peer != nil {enet.peer_reset(peer.enet_peer)}
    case .WebSocket:
        replication_ws_close(peer)
    }
}

transport_peer_disconnected :: proc(peer: ^Replication_Transport_Peer) -> bool {
    if peer == nil {return true}
    switch peer.kind {
    case .ENet:
        return peer.enet_peer == nil || peer.enet_peer.state == .DISCONNECTED
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
