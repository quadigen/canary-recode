package services

import vm "../vm"
import "core:compress/lz4"

REPLICATION_JOIN_BATCH_MAX :: 12 * 1024

replication_join_batch_kind :: proc(kind: u8) -> bool {
	return kind == 5 || kind == 7 || kind == 8 || kind == Replication_Kind_Metadata
}

replication_flush_join_batch :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
) -> bool {
	batch := &connection.join_batch
	if len(batch^) == 0 {return true}
	compressed: [dynamic]u8
	defer delete(compressed)
	wire := batch^[:]
	if len(wire) >= 1024 {
		if err := lz4.compress_block(&compressed, wire);
		   err == nil && len(compressed) < len(wire) {
			wire = compressed[:]
		}
	}
	packet := make([dynamic]u8, 0, 9 + len(wire))
	defer delete(packet)
	append(&packet, 'K', 'R', 'P', u8(Replication_Protocol_Version), Replication_Kind_Join_Batch)
	replication_put_u32(&packet, u32(len(batch^)))
	append(&packet, ..wire)
	if !transport_peer_send(
		connection.peer,
		Replication_Transport_Channel_Reliable,
		packet[:],
		true,
	) {
		return false
	}
	service.packets_sent += 1
	service.bytes_sent += u64(len(packet))
	service.diag_kind_counts[Replication_Kind_Join_Batch] += 1
	service.diag_kind_bytes[Replication_Kind_Join_Batch] += u64(len(packet) - 5)
	clear(batch)
	return true
}

replication_receive_join_batch :: proc(
	service: ^ReplicatorService,
	L: ^vm.State,
	peer: ^Replication_Transport_Peer,
	reader: ^Replication_Reader,
) {
	if service.mode != .Client ||
	   peer != service.remote ||
	   !service.handshake_complete ||
	   (service.client_capabilities &
			   service.server_capabilities &
			   Replication_Capability_Join_Batch) ==
		   0 {
		reader.valid = false
		return
	}
	size := int(replication_read_u32(reader))
	wire := reader.data[reader.offset:]
	if !reader.valid ||
	   size < 9 ||
	   size > REPLICATION_JOIN_BATCH_MAX ||
	   len(wire) == 0 ||
	   len(wire) > size {
		reader.valid = false
		return
	}
	decoded: []u8
	defer delete(decoded)
	if len(wire) != size {
		decoded = make([]u8, size)
		written, err := lz4.decompress_block(decoded, wire)
		if err != nil || written != size {reader.valid = false; return}
		wire = decoded
	}

	// Validate the whole envelope before handing frames to the ordinary
	// decoder. Only join data can be nested, never another envelope.
	frames: [dynamic][]u8
	defer delete(frames)
	inner := Replication_Reader {
		data  = wire,
		valid = true,
	}
	for inner.offset < len(wire) {
		length := int(replication_read_u32(&inner))
		if !inner.valid || length < 5 || length > len(wire) - inner.offset {
			reader.valid = false
			return
		}
		frame := wire[inner.offset:inner.offset + length]
		if frame[0] != 'K' ||
		   frame[1] != 'R' ||
		   frame[2] != 'P' ||
		   u32(frame[3]) < Replication_Minimum_Framing_Version ||
		   !replication_join_batch_kind(frame[4]) {
			reader.valid = false
			return
		}
		append(&frames, frame)
		inner.offset += length
	}
	reader.offset = len(reader.data)
	for frame in frames {replication_receive(service, L, peer, frame)}
}
