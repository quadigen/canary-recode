package services

import classes "../classes"
import vm "../vm"
import "core:compress/lz4"
import "core:fmt"

REPLICATION_SCRIPT_SOURCE_MAX :: 16 * 1024 * 1024
REPLICATION_SCRIPT_SOURCE_HEADER :: 16
REPLICATION_SCRIPT_SOURCE_COMPRESS_MIN :: 512

Replication_Script_Send :: struct {
	id:         u32,
	revision:   u64,
	offset:     int,
	compressed: [dynamic]u8,
}

Replication_Script_Receive :: struct {
	id:        u32,
	raw_size:  int,
	wire_size: int,
	bytes:     [dynamic]u8,
}

replication_clear_script_send :: proc(transfer: ^Replication_Script_Send) {
	delete(transfer.compressed)
	transfer^ = {}
}

replication_clear_script_receive :: proc(transfer: ^Replication_Script_Receive) {
	delete(transfer.bytes)
	transfer^ = {}
}

replication_peer_script :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	object: ^classes.Object,
) -> ^classes.Script_Common {
	if (connection.client_capabilities &
		   service.server_capabilities &
		   Replication_Capability_Script_Source) ==
	   0 {
		return nil
	}
	return classes.Script_Common_Of(object)
}

// Reliable chunks share the ordinary property budget. A peer transfers one
// script at a time and tracks completed revisions independently of property ACKs.
replication_send_script_source :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	item: ^Replication_Entity,
	script: ^classes.Script_Common,
) -> bool {
	revision := script.source_revision + 1
	if connection.script_sources[item.id] == revision {return true}
	if len(script.source) == 0 &&
	   revision == 1 &&
	   item.id not_in connection.script_sources {return true}
	transfer := &connection.script_send
	if len(script.source) > REPLICATION_SCRIPT_SOURCE_MAX {
		fmt.eprintf(
			"[Replication] Script source exceeds %d bytes: %s\n",
			REPLICATION_SCRIPT_SOURCE_MAX,
			item.object.name,
		)
		connection.script_sources[item.id] = revision
		if transfer.id == item.id {replication_clear_script_send(transfer)}
		return true
	}
	if transfer.id != 0 && transfer.id != item.id {return false}
	budget :=
		min(
			replication_remaining_budget(service, connection, Replication_Kind_Script_Source) - 5,
			int(Replication_Max_Frame_Payload),
		) -
		REPLICATION_SCRIPT_SOURCE_HEADER
	if budget < 1 {return false}

	source := transmute([]u8)script.source
	if transfer.id != item.id || transfer.revision != revision {
		replication_clear_script_send(transfer)
		transfer.id = item.id
		transfer.revision = revision
		if len(source) >= REPLICATION_SCRIPT_SOURCE_COMPRESS_MIN {
			err := lz4.compress_block(&transfer.compressed, source)
			if err != nil || len(transfer.compressed) >= len(source) {
				delete(transfer.compressed)
				transfer.compressed = nil
			}
		}
	}
	wire := source
	if len(transfer.compressed) > 0 {wire = transfer.compressed[:]}
	end := transfer.offset + min(len(wire) - transfer.offset, budget)
	payload := make([dynamic]u8, 0, REPLICATION_SCRIPT_SOURCE_HEADER + end - transfer.offset)
	defer delete(payload)
	replication_put_u32(&payload, item.id)
	replication_put_u32(&payload, u32(len(source)))
	replication_put_u32(&payload, u32(len(wire)))
	replication_put_u32(&payload, u32(transfer.offset))
	append(&payload, ..wire[transfer.offset:end])
	if !replication_send(
		service,
		connection.peer,
		Replication_Kind_Script_Source,
		payload[:],
		true,
	) {
		return false
	}
	transfer.offset = end
	if end < len(wire) {return false}
	connection.script_sources[item.id] = revision
	replication_clear_script_send(transfer)
	return true
}

replication_receive_script_source :: proc(
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
			   Replication_Capability_Script_Source) ==
		   0 {
		return
	}
	id := replication_read_u32(reader)
	raw_size := int(replication_read_u32(reader))
	wire_size := int(replication_read_u32(reader))
	offset := int(replication_read_u32(reader))
	if !reader.valid ||
	   raw_size < 0 ||
	   raw_size > REPLICATION_SCRIPT_SOURCE_MAX ||
	   wire_size < 0 ||
	   wire_size > raw_size ||
	   (wire_size == 0 && raw_size != 0) ||
	   offset < 0 ||
	   offset > wire_size {
		reader.valid = false
		return
	}
	chunk := reader.data[reader.offset:]
	object := replication_entity_object(service, id)
	script := classes.Script_Common_Of(object)
	if script == nil ||
	   object.destroyed ||
	   len(chunk) > wire_size - offset ||
	   (len(chunk) == 0 && wire_size != 0) {
		reader.valid = false
		return
	}
	transfer := &service.script_receive
	if offset == 0 {
		replication_clear_script_receive(transfer)
		transfer.id = id
		transfer.raw_size = raw_size
		transfer.wire_size = wire_size
	}
	if transfer.id != id ||
	   transfer.raw_size != raw_size ||
	   transfer.wire_size != wire_size ||
	   len(transfer.bytes) != offset {
		reader.valid = false
		return
	}
	append(&transfer.bytes, ..chunk)
	reader.offset = len(reader.data)
	if len(transfer.bytes) != wire_size {return}
	defer replication_clear_script_receive(transfer)

	if raw_size == wire_size {
		classes.Script_Common_Set_Source(L, script, string(transfer.bytes[:]))
		return
	}
	source := make([]u8, raw_size)
	defer delete(source)
	written, err := lz4.decompress_block(source, transfer.bytes[:])
	if err != nil || written != raw_size {
		reader.valid = false
		return
	}
	classes.Script_Common_Set_Source(L, script, string(source))
}
