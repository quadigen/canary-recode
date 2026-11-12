#+build js
package services

import "core:fmt"
import "core:strings"

foreign import "kinemium_net"

@(default_calling_convention = "c")
foreign kinemium_net {
    host_net_connect :: proc(url: cstring) -> i32 ---
    host_net_state :: proc(handle: i32) -> i32 ---
    host_net_send :: proc(handle: i32, data: [^]u8, len: i32) -> i32 ---
    host_net_message_size :: proc(handle: i32) -> i32 ---
    host_net_receive :: proc(handle: i32, out: [^]u8, cap: i32) -> i32 ---
    host_net_close :: proc(handle: i32) ---
    host_net_now_ms :: proc() -> f64 ---
}

Replication_Transport_Peer :: struct {
    handle: i32,
}

Replication_Transport_Host :: struct {
    handle:       i32,
    client_peer:  Replication_Transport_Peer,
    connected:    bool,
    disconnected: bool,
    pending:      [dynamic]Replication_Transport_Event,
}

Replication_Transport_Event :: struct {
    type:    Replication_Transport_Event_Type,
    peer:    ^Replication_Transport_Peer,
    channel: u8,
    data:    []u8,
}

transport_init :: proc() -> bool {return true}
transport_deinit :: proc() {}
transport_time_get :: proc() -> u32 {return u32(host_net_now_ms())}

transport_host_create_server :: proc(
    address: string, port: u16, max_peers: int, channels: int,
) -> ^Replication_Transport_Host {
    fmt.eprintln("[Replication] the browser build cannot host a server")
    return nil
}

transport_host_create_client :: proc() -> ^Replication_Transport_Host {
    host := new(Replication_Transport_Host)
    host.handle = -1
    return host
}

transport_host_connect :: proc(
    host: ^Replication_Transport_Host, address: string, port: u16, channels: int,
) -> ^Replication_Transport_Peer {
    if host == nil {return nil}
    c_url: cstring
    switch {
    case strings.contains(address, "://"):
        c_url = fmt.ctprintf("%s", address)
    case port != 0:
        c_url = fmt.ctprintf("ws://%s:%d", address, port)
    case:
        c_url = fmt.ctprintf("ws://%s", address)
    }
    handle := host_net_connect(c_url)
    if handle < 0 {
        fmt.eprintf("[Replication] could not open a WebSocket to %s\n", c_url)
        return nil
    }
    host.handle = handle
    host.connected = false
    host.disconnected = false
    host.client_peer = Replication_Transport_Peer{handle = handle}
    return &host.client_peer
}

// Each poll pulls at most one message. No temporary multi-message queue or
// O(N) ordered_remove is needed, and the browser controls its own receive queue.
transport_host_service :: proc(host: ^Replication_Transport_Host) -> (Replication_Transport_Event, bool) {
    if host == nil || host.handle < 0 {return {}, false}
    state := host_net_state(host.handle)
    switch state {
    case 1:
        if !host.connected {
            host.connected = true
            return Replication_Transport_Event {
                type = .CONNECT, peer = &host.client_peer,
                channel = Replication_Transport_Channel_Reliable,
            }, true
        }
        size := host_net_message_size(host.handle)
        if size <= 0 {return {}, false}
        if size > i32(Replication_Max_Frame_Payload) + 5 {
            host_net_close(host.handle)
            return {}, false
        }
        data := make([]u8, int(size))
        got := host_net_receive(host.handle, raw_data(data), size)
        if got <= 0 {
            delete(data)
            return {}, false
        }
        if got != size {
            exact := make([]u8, int(got))
            copy(exact, data[:int(got)])
            delete(data)
            data = exact
        }
        return Replication_Transport_Event {
            type = .RECEIVE, peer = &host.client_peer,
            channel = Replication_Transport_Channel_Reliable, data = data,
        }, true
    case 2:
        if !host.disconnected {
            host.disconnected = true
            host.connected = false
            return Replication_Transport_Event {
                type = .DISCONNECT, peer = &host.client_peer,
                channel = Replication_Transport_Channel_Reliable,
            }, true
        }
    }
    return {}, false
}

transport_host_flush :: proc(host: ^Replication_Transport_Host) {}

transport_host_destroy :: proc(host: ^Replication_Transport_Host) {
    if host == nil {return}
    if host.handle >= 0 {host_net_close(host.handle)}
    for &event in host.pending {transport_event_dispose(&event)}
    delete(host.pending)
    free(host)
}

transport_peer_send :: proc(
    peer: ^Replication_Transport_Peer, channel: u8, data: []u8, reliable: bool,
) -> bool {
    if peer == nil || len(data) > int(Replication_Max_Frame_Payload) + 5 {return false}
    return host_net_send(peer.handle, raw_data(data), i32(len(data))) == 1
}

transport_peer_disconnect :: proc(peer: ^Replication_Transport_Peer) {
    if peer != nil {host_net_close(peer.handle)}
}
transport_peer_disconnect_now :: proc(peer: ^Replication_Transport_Peer) {
    if peer != nil {host_net_close(peer.handle)}
}
transport_peer_reset :: proc(peer: ^Replication_Transport_Peer) {
    if peer != nil {host_net_close(peer.handle)}
}
transport_peer_disconnected :: proc(peer: ^Replication_Transport_Peer) -> bool {
    return peer == nil || host_net_state(peer.handle) == 2
}
transport_event_dispose :: proc(event: ^Replication_Transport_Event) {
    if event == nil {return}
    delete(event.data)
    event.data = nil
}
