#+build !js
package services

import "core:encoding/base64"
import "core:fmt"
import "core:net"
import "core:strings"

WS_HANDSHAKE_MAGIC :: "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
WS_MAX_MESSAGE :: 4 * 1024 * 1024
WS_MAX_HANDSHAKE :: 16 * 1024
WS_OP_CONTINUATION :: 0x0
WS_OP_TEXT :: 0x1
WS_OP_BINARY :: 0x2
WS_OP_CLOSE :: 0x8
WS_OP_PING :: 0x9
WS_OP_PONG :: 0xA

replication_ws_listen :: proc(host: ^Replication_Transport_Host, address: string, port: u16) {
	endpoint := net.Endpoint {
		address = net.IP4_Any,
		port    = int(port),
	}
	if address != "" && address != "0.0.0.0" {
		if resolved, err := net.resolve_ip4(address); err == nil {
			endpoint.address = resolved.address
		} else {
			fmt.eprintf("[WebSocket] could not resolve bind address %s\n", address)
			return
		}
	}
	socket, err := net.listen_tcp(endpoint)
	if err != nil {
		fmt.eprintf("[WebSocket] could not listen on tcp %d: %v\n", port, err)
		return
	}
	net.set_blocking(socket, false)
	host.ws_listener = new(net.TCP_Socket)
	host.ws_listener^ = socket
	fmt.printf("[WebSocket] listening on tcp %d\n", port)
}


replication_ws_pump :: proc(host: ^Replication_Transport_Host) {
	replication_ws_reap(host)
	if host.ws_listener != nil {
		for {
			client, _, err := net.accept_tcp(host.ws_listener^)
			if err != nil {
				if err != .Would_Block {
					fmt.eprintf("[WebSocket] accept failed: %v\n", err)
				}
				break
			}
			net.set_blocking(client, false)
			conn := new(Replication_Ws_Connection)
			conn.socket = client
			peer := new(Replication_Transport_Peer)
			peer.kind = .WebSocket
			peer.ws = conn
			conn.peer = peer
			append(&host.ws_connections, conn)
		}
	}
	for conn in host.ws_connections {
		if conn.closing {continue}
		replication_ws_read(host, conn)
	}
}


replication_ws_reap :: proc(host: ^Replication_Transport_Host) {
	for index := len(host.ws_connections) - 1; index >= 0; index -= 1 {
		conn := host.ws_connections[index]
		if !conn.closing || !conn.disconnect_fired {continue}
		net.close(conn.socket)
		free(conn.peer)
		delete(conn.read_buffer)
		delete(conn.write_buffer)
		free(conn)
		ordered_remove(&host.ws_connections, index)
	}
}

replication_ws_read :: proc(host: ^Replication_Transport_Host, conn: ^Replication_Ws_Connection) {
	buffer: [8192]u8
	for {
		count, err := net.recv_tcp(conn.socket, buffer[:])
		if count > 0 {append(&conn.read_buffer, ..buffer[:count])}
		if err != nil {
			if err == .Would_Block {return}
			replication_ws_begin_close(host, conn)
			return
		}
		if count == 0 {
			replication_ws_begin_close(host, conn)
			return
		}
		if count < len(buffer) {break}
	}
	if !conn.handshake_done {
		replication_ws_try_handshake(host, conn)
		return
	}
	replication_ws_process_frames(host, conn)
}

replication_ws_try_handshake :: proc(
	host: ^Replication_Transport_Host,
	conn: ^Replication_Ws_Connection,
) {
	text := string(conn.read_buffer[:])
	header_end := strings.index(text, "\r\n\r\n")
	if header_end < 0 {
		if len(conn.read_buffer) > WS_MAX_HANDSHAKE {
			fmt.eprintln("[WebSocket] closing a connection whose handshake never completed")
			replication_ws_begin_close(host, conn)
		}
		return
	}
	key := replication_ws_header_value(text, "sec-websocket-key")
	if key == "" {
		fmt.eprintln("[WebSocket] closing a connection with no Sec-WebSocket-Key")
		replication_ws_begin_close(host, conn)
		return
	}
	accept_input := strings.concatenate({key, WS_HANDSHAKE_MAGIC})
	digest := ws_sha1(transmute([]u8)accept_input)
	encoded := base64.encode(digest[:])
	response := strings.concatenate(
		{
			"HTTP/1.1 101 Switching Protocols\r\n",
			"Upgrade: websocket\r\n",
			"Connection: Upgrade\r\n",
			"Sec-WebSocket-Accept: ",
			encoded,
			"\r\n\r\n",
		},
	)
	append(&conn.write_buffer, ..transmute([]u8)response)
	delete(accept_input)
	delete(encoded)
	delete(response)

	remaining := conn.read_buffer[header_end + 4:]
	tail := make([]u8, len(remaining))
	copy(tail, remaining)
	clear(&conn.read_buffer)
	append(&conn.read_buffer, ..tail)
	delete(tail)
	conn.handshake_done = true
	append(
		&host.pending,
		Replication_Transport_Event {
			type = .CONNECT,
			peer = conn.peer,
			channel = Replication_Transport_Channel_Reliable,
		},
	)


}

replication_ws_header_value :: proc(headers: string, lower_name: string) -> string {
	text := headers
	for line in strings.split_lines_iterator(&text) {
		colon := strings.index_byte(line, ':')
		if colon < 0 {continue}
		name := strings.trim_space(line[:colon])
		if !strings.equal_fold(name, lower_name) {continue}
		return strings.trim_space(line[colon + 1:])
	}
	return ""
}

replication_ws_begin_close :: proc(
	host: ^Replication_Transport_Host,
	conn: ^Replication_Ws_Connection,
) {
	if conn.closing {return}
	conn.closing = true
	replication_ws_enqueue(conn, WS_OP_CLOSE, nil)
	replication_ws_flush_connection(conn)
	if !conn.disconnect_fired {
		conn.disconnect_fired = true
		append(
			&host.pending,
			Replication_Transport_Event {
				type = .DISCONNECT,
				peer = conn.peer,
				channel = Replication_Transport_Channel_Reliable,
			},
		)
	}
}

Ws_Frame_Status :: enum {
	Full,
	Need_More,
	Error,
}


replication_ws_process_frames :: proc(
	host: ^Replication_Transport_Host,
	conn: ^Replication_Ws_Connection,
) {
	for {
		opcode, fin, payload, total, status := replication_ws_parse_frame(conn.read_buffer[:])
		switch status {
		case .Need_More:
			return
		case .Error:
			fmt.eprintln("[WebSocket] closing a connection that sent a malformed frame")
			replication_ws_begin_close(host, conn)
			return
		case .Full:
		}

		switch opcode {
		case WS_OP_CLOSE:
			replication_ws_consume(conn, total)
			replication_ws_begin_close(host, conn)
			return
		case WS_OP_PING:
			replication_ws_enqueue(conn, WS_OP_PONG, payload)
		case WS_OP_PONG:

		case WS_OP_TEXT, WS_OP_BINARY, WS_OP_CONTINUATION:
			if opcode != WS_OP_CONTINUATION {conn.fragment_opcode = opcode}
			append(&conn.fragment, ..payload)
			if fin {
				replication_ws_deliver(host, conn, conn.fragment[:])
				clear(&conn.fragment)
			}
		case:
			replication_ws_consume(conn, total)
			fmt.eprintln("[WebSocket] closing a connection that sent an unknown opcode")
			replication_ws_begin_close(host, conn)
			return
		}
		replication_ws_consume(conn, total)
	}
}

replication_ws_consume :: proc(conn: ^Replication_Ws_Connection, total: int) {
	remaining := len(conn.read_buffer) - total
	copy(conn.read_buffer[:], conn.read_buffer[total:])
	resize(&conn.read_buffer, remaining)
}

replication_ws_deliver :: proc(
	host: ^Replication_Transport_Host,
	conn: ^Replication_Ws_Connection,
	data: []u8,
) {
	clone := make([]u8, len(data))
	copy(clone, data)
	append(
		&host.pending,
		Replication_Transport_Event {
			type = .RECEIVE,
			peer = conn.peer,
			channel = Replication_Transport_Channel_Reliable,
			data = clone,
		},
	)
}

replication_ws_parse_frame :: proc(
	data: []u8,
) -> (
	opcode: u8,
	fin: bool,
	payload: []u8,
	total: int,
	status: Ws_Frame_Status,
) {
	if len(data) < 2 {return 0, false, nil, 0, .Need_More}
	b0 := data[0]
	b1 := data[1]
	fin = (b0 & 0x80) != 0
	opcode = b0 & 0x0F
	masked := (b1 & 0x80) != 0
	length := u64(b1 & 0x7F)
	offset := 2

	switch length {
	case 126:
		if len(data) < offset + 2 {return 0, false, nil, 0, .Need_More}
		length = u64(data[offset]) << 8 | u64(data[offset + 1])
		offset += 2
	case 127:
		if len(data) < offset + 8 {return 0, false, nil, 0, .Need_More}
		length = 0
		for i in 0 ..< 8 {length = (length << 8) | u64(data[offset + i])}
		offset += 8
	}
	if length > WS_MAX_MESSAGE {return 0, false, nil, 0, .Error}

	mask: [4]u8
	if masked {
		if len(data) < offset + 4 {return 0, false, nil, 0, .Need_More}
		copy(mask[:], data[offset:offset + 4])
		offset += 4
	}
	if u64(len(data) - offset) < length {return 0, false, nil, 0, .Need_More}

	payload = data[offset:offset + int(length)]
	if masked {
		for i in 0 ..< len(payload) {payload[i] ~= mask[i % 4]}
	}
	total = offset + int(length)
	return opcode, fin, payload, total, .Full
}


replication_ws_enqueue :: proc(conn: ^Replication_Ws_Connection, opcode: u8, payload: []u8) {
	append(&conn.write_buffer, 0x80 | opcode)
	length := len(payload)
	switch {
	case length < 126:
		append(&conn.write_buffer, u8(length))
	case length <= 0xFFFF:
		append(&conn.write_buffer, 126, u8(length >> 8), u8(length))
	case:
		append(&conn.write_buffer, 127)
		for i := 7; i >= 0; i -= 1 {
			append(&conn.write_buffer, u8(u64(length) >> (8 * u32(i))))
		}
	}
	append(&conn.write_buffer, ..payload)
}

replication_ws_send :: proc(peer: ^Replication_Transport_Peer, data: []u8) -> bool {
	if peer == nil || peer.ws == nil {return false}
	if peer.ws.closing {return false}
	replication_ws_enqueue(peer.ws, WS_OP_BINARY, data)
	return true
}

replication_ws_close :: proc(peer: ^Replication_Transport_Peer) {
	if peer == nil || peer.ws == nil {return}
	if peer.ws.closing {return}
	peer.ws.closing = true
	replication_ws_enqueue(peer.ws, WS_OP_CLOSE, nil)
	replication_ws_flush_connection(peer.ws)
}

replication_ws_flush :: proc(host: ^Replication_Transport_Host) {
	if host == nil {return}
	for conn in host.ws_connections {
		if conn.closing {continue}
		replication_ws_flush_connection(conn)
	}
}

replication_ws_flush_connection :: proc(conn: ^Replication_Ws_Connection) {
	if len(conn.write_buffer) == 0 {return}
	sent := 0
	for sent < len(conn.write_buffer) {
		count, err := net.send_tcp(conn.socket, conn.write_buffer[sent:])
		if err != nil {


			if err != .Would_Block {break}
			break
		}
		if count == 0 {break}
		sent += count
	}
	if sent > 0 {
		remaining := len(conn.write_buffer) - sent
		copy(conn.write_buffer[:], conn.write_buffer[sent:])
		resize(&conn.write_buffer, remaining)
	}
}

replication_ws_shutdown :: proc(host: ^Replication_Transport_Host) {
	if host == nil {return}
	if host.ws_listener != nil {
		net.close(host.ws_listener^)
		free(host.ws_listener)
		host.ws_listener = nil
	}
	for conn in host.ws_connections {
		net.close(conn.socket)
		free(conn.peer)
		delete(conn.read_buffer)
		delete(conn.write_buffer)
		delete(conn.fragment)
		free(conn)
	}
	delete(host.ws_connections)
	host.ws_connections = nil
}
