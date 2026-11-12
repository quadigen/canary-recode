package services

import classes "../classes"
import serializer "../serializer"
import vm "../vm"
import "core:fmt"
import "core:strings"

REPLICATION_METADATA_MAX :: 16 * 1024 * 1024
REPLICATION_METADATA_HEADER :: 16
REPLICATION_METADATA_PLAYER :: u64(0)
REPLICATION_METADATA_PLAYER_GUI :: u64(1) << 32
REPLICATION_METADATA_ROOT_BASE :: REPLICATION_METADATA_PLAYER_GUI + 1
REPLICATION_METADATA_REMOTE_PLAYER_BASE :: u64(2) << 32
REPLICATION_METADATA_DATAMODEL :: REPLICATION_METADATA_REMOTE_PLAYER_BASE - 1

Replication_Metadata_Send :: struct {
	key, revision: u64,
	offset:        int,
	bytes:         [dynamic]u8,
}

Replication_Metadata_Receive :: struct {
	key:   u64,
	total: int,
	bytes: [dynamic]u8,
}

replication_clear_metadata_send :: proc(transfer: ^Replication_Metadata_Send) {
	delete(transfer.bytes)
	transfer^ = {}
}

replication_clear_metadata_receive :: proc(transfer: ^Replication_Metadata_Receive) {
	delete(transfer.bytes)
	transfer^ = {}
}

replication_encode_metadata :: proc(
	L: ^vm.State,
	registry: ^classes.Registry,
	object: ^classes.Object,
) -> (
	bytes: [dynamic]u8,
	ok: bool,
) {
	replication_put_u32(&bytes, 0)
	count: u32
	for attribute in object.attributes {
		offset := len(bytes)
		replication_put_string(&bytes, attribute.name)
		vm.PushRegistryReference(L, attribute.value_ref)
		written := serializer.Append_Replicated_Value(&bytes, L, registry)
		vm.Pop(L)
		if !written {
			resize(&bytes, offset)
			continue
		}
		if len(bytes) > REPLICATION_METADATA_MAX {return bytes, false}
		count += 1
	}
	for index in 0 ..< 4 {bytes[index] = u8(count >> u32(index * 8))}
	replication_put_u32(&bytes, u32(len(object.tags)))
	for tag in object.tags {
		replication_put_string(&bytes, tag)
		if len(bytes) > REPLICATION_METADATA_MAX {return bytes, false}
	}
	return bytes, len(bytes) <= REPLICATION_METADATA_MAX
}

// Reliable chunks share the snapshot budget and become visible only when the
// whole revision has arrived. Finish a revision even if the object changes
// while it is in flight, then send the new revision on a subsequent tick.
replication_send_metadata :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	key: u64,
	object: ^classes.Object,
	initial := false,
) -> bool {
	if (connection.client_capabilities &
		   service.server_capabilities &
		   Replication_Capability_Metadata) ==
	   0 {
		return true
	}
	transfer := &connection.metadata_send
	if object == nil || object.destroyed {
		if transfer.key == key {replication_clear_metadata_send(transfer)}
		delete_key(&connection.metadata_revisions, key)
		return true
	}
	sent_revision, sent := connection.metadata_revisions[key]
	if sent_revision == object.metadata_revision || (initial && sent) {return true}
	if !sent && len(object.attributes) == 0 && len(object.tags) == 0 {
		return true
	}
	if len(transfer.bytes) != 0 && transfer.key != key {return false}
	budget :=
		min(
			replication_remaining_budget(service, connection, Replication_Kind_Metadata) - 5,
			int(Replication_Max_Frame_Payload),
		) -
		REPLICATION_METADATA_HEADER
	if budget <= 0 {return false}
	if len(transfer.bytes) == 0 {
		registry := service.signal_registry
		bytes, ok := replication_encode_metadata(registry.vm_state.L, registry, object)
		if !ok {
			delete(bytes)
			fmt.eprintf(
				"[Replication] metadata exceeds %d bytes for %s\n",
				REPLICATION_METADATA_MAX,
				object.name,
			)
			connection.metadata_revisions[key] = object.metadata_revision
			return true
		}
		transfer^ = {
			key      = key,
			revision = object.metadata_revision,
			bytes    = bytes,
		}
	}
	end := min(transfer.offset + budget, len(transfer.bytes))
	payload := make([dynamic]u8, 0, REPLICATION_METADATA_HEADER + end - transfer.offset)
	defer delete(payload)
	replication_put_u64(&payload, key)
	replication_put_u32(&payload, u32(len(transfer.bytes)))
	replication_put_u32(&payload, u32(transfer.offset))
	append(&payload, ..transfer.bytes[transfer.offset:end])
	if !replication_send(
		service,
		connection.peer,
		Replication_Kind_Metadata,
		payload[:],
	) {return false}
	transfer.offset = end
	if end < len(transfer.bytes) {return false}
	connection.metadata_revisions[key] = transfer.revision
	replication_clear_metadata_send(transfer)
	return true
}

replication_send_entity_metadata :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	item: ^Replication_Entity,
	initial := false,
) -> bool {
	if !replication_send_metadata(
		service,
		connection,
		u64(item.id),
		item.object,
		initial,
	) {return false}
	if !classes.Is_A_Class(item.object, &classes.CharacterModel_Class) {return true}
	model := cast(^classes.CharacterModel)item.object
	if connection.player == nil || model.owner_user_id == connection.player.user_id {return true}
	// The root's spawn creates the remote Player before metadata can target it.
	root := classes.Find_First_Child(item.object, "HumanoidRootPart")
	player: ^Player
	if root != nil && connection.known[replication_entity_id(service, root)] != 0 {
		players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
		player = character_service_player_for_model(players, model)
	}
	object := &player.object if player != nil else nil
	return replication_send_metadata(
		service,
		connection,
		REPLICATION_METADATA_REMOTE_PLAYER_BASE + u64(item.id),
		object,
		initial,
	)
}

replication_send_root_metadata :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
) -> bool {
	initial := !connection.finished_replicating_sent
	ready := replication_send_metadata(
		service,
		connection,
		REPLICATION_METADATA_DATAMODEL,
		&service.data_model.object,
		initial,
	)
	if connection.player != nil && !connection.player.destroyed {
		player := &connection.player.object
		ready =
			replication_send_metadata(
				service,
				connection,
				REPLICATION_METADATA_PLAYER,
				player,
				initial,
			) &&
			ready
		if (connection.client_capabilities &
			   service.server_capabilities &
			   Replication_Capability_Player_Gui) !=
		   0 {
			gui := classes.Find_First_Child_Of_Class(player, "PlayerGui")
			ready =
				replication_send_metadata(
					service,
					connection,
					REPLICATION_METADATA_PLAYER_GUI,
					gui,
					initial,
				) &&
				ready
		}
	}
	for name, index in REPLICATION_ROOT_NAMES {
		object := DataModel_Get_Service(service.data_model, name)
		ready =
			replication_send_metadata(
				service,
				connection,
				REPLICATION_METADATA_ROOT_BASE + u64(index),
				object,
				initial,
			) &&
			ready
	}
	return ready
}

replication_metadata_object :: proc(
	service: ^ReplicatorService,
	L: ^vm.State,
	key: u64,
) -> ^classes.Object {
	switch key {
	case REPLICATION_METADATA_DATAMODEL:
		return &service.data_model.object
	case REPLICATION_METADATA_PLAYER, REPLICATION_METADATA_PLAYER_GUI:
		players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
		if players == nil ||
		   players.local_player == nil ||
		   players.local_player.destroyed {return nil}
		if key == REPLICATION_METADATA_PLAYER {return &players.local_player.object}
		if !replication_uses_server_player_gui(service) {return nil}
		return PlayerGui_Prepare(players.local_player, L)
	case:
		if key <= u64(max(u32)) {return replication_entity_object(service, u32(key))}
		if key >= REPLICATION_METADATA_REMOTE_PLAYER_BASE {
			id := key - REPLICATION_METADATA_REMOTE_PLAYER_BASE
			if id > u64(max(u32)) {return nil}
			character := replication_entity_object(service, u32(id))
			if !classes.Is_A_Class(character, &classes.CharacterModel_Class) {return nil}
			players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
			player := character_service_player_for_model(
				players,
				cast(^classes.CharacterModel)character,
			)
			return &player.object if player != nil else nil
		}
		index := key - REPLICATION_METADATA_ROOT_BASE
		if index >= u64(len(REPLICATION_ROOT_NAMES)) {return nil}
		return DataModel_Get_Service(service.data_model, REPLICATION_ROOT_NAMES[index])
	}
}

replication_clear_root_metadata :: proc(service: ^ReplicatorService, L: ^vm.State) {
	if service.data_model == nil {return}
	empty: [8]u8
	_ = replication_apply_metadata(
		L,
		service.signal_registry,
		&service.data_model.object,
		empty[:],
	)
	for name in REPLICATION_ROOT_NAMES {
		object := DataModel_Get_Service(service.data_model, name)
		if object == nil ||
		   object.destroyed ||
		   (len(object.server_attributes) == 0 && len(object.server_tags) == 0) {continue}
		_ = replication_apply_metadata(L, service.signal_registry, object, empty[:])
	}
}

replication_apply_metadata :: proc(
	L: ^vm.State,
	registry: ^classes.Registry,
	object: ^classes.Object,
	bytes: []u8,
) -> bool {
	reader := Replication_Reader {
		data  = bytes,
		valid = true,
	}
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	attributes: [dynamic]classes.Object_Attribute
	defer {
		for attribute in attributes {vm.ReleaseValue(L, attribute.value_ref)}
		delete(attributes)
	}
	attribute_names, tags: map[string]bool
	defer delete(attribute_names)
	defer delete(tags)
	tag_names: [dynamic]string
	defer delete(tag_names)
	count := replication_read_u32(&reader)
	if !reader.valid || u64(count) > u64(len(bytes) / 6) {return false}
	for _ in 0 ..< count {
		name := replication_read_string(&reader)
		if !reader.valid ||
		   !classes.Attribute_Name_Is_Valid(name) ||
		   attribute_names[name] {return false}
		consumed, ok := serializer.Read_Replicated_Value(bytes[reader.offset:], L, registry)
		if !ok || !classes.Attribute_Value_Is_Supported(L, -1) {return false}
		reader.offset += consumed
		if !vm.IsNil(L, -1) {
			attribute_names[name] = true
			append(
				&attributes,
				classes.Object_Attribute{name = name, value_ref = vm.RetainValue(L)},
			)
		}
		vm.Pop(L)
	}
	count = replication_read_u32(&reader)
	if !reader.valid || u64(count) > u64((len(bytes) - reader.offset) / 5) {return false}
	for _ in 0 ..< count {
		tag := replication_read_string(&reader)
		if !reader.valid || !classes.Tag_Name_Is_Valid(tag) || tags[tag] {return false}
		tags[tag] = true
		append(&tag_names, tag)
	}
	if reader.offset != len(bytes) {return false}

	// Remove keys previously supplied by the server while preserving unrelated
	// metadata created by client scripts.
	vm.PushNil(L)
	for name in object.server_attributes {
		if !attribute_names[name] {_ = classes.Set_Attribute(L, object, name, -1)}
		delete(name)
	}
	vm.Pop(L)
	clear(&object.server_attributes)
	for attribute in attributes {
		vm.PushRegistryReference(L, attribute.value_ref)
		_ = classes.Set_Attribute(L, object, attribute.name, -1)
		vm.Pop(L)
		append(&object.server_attributes, strings.clone(attribute.name))
	}
	for tag in object.server_tags {
		if !tags[tag] {classes.Object_Remove_Tag(object, tag)}
		delete(tag)
	}
	clear(&object.server_tags)
	for tag in tag_names {
		classes.Object_Add_Tag(object, tag)
		append(&object.server_tags, strings.clone(tag))
	}
	return true
}

replication_receive_metadata :: proc(
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
			   Replication_Capability_Metadata) ==
		   0 {return}
	key := replication_read_u64(reader)
	total := int(replication_read_u32(reader))
	offset := int(replication_read_u32(reader))
	chunk := reader.data[reader.offset:]
	if !reader.valid ||
	   total < 8 ||
	   total > REPLICATION_METADATA_MAX ||
	   offset < 0 ||
	   offset >= total ||
	   len(chunk) == 0 ||
	   len(chunk) > total - offset {
		reader.valid = false
		return
	}
	transfer := &service.metadata_receive
	if offset == 0 {
		replication_clear_metadata_receive(transfer)
		transfer.key = key
		transfer.total = total
	}
	if transfer.key != key || transfer.total != total || len(transfer.bytes) != offset {
		reader.valid = false
		return
	}
	append(&transfer.bytes, ..chunk)
	reader.offset = len(reader.data)
	if len(transfer.bytes) != total {return}
	defer replication_clear_metadata_receive(transfer)
	object := replication_metadata_object(service, L, key)
	if object == nil || object.destroyed {return}
	reader.valid = replication_apply_metadata(
		L,
		service.signal_registry,
		object,
		transfer.bytes[:],
	)
}
