package services

import classes "../classes"
import datatypes "../datatypes"


replication_pivot_barrier :: proc(
	service: ^ReplicatorService,
	object: ^classes.Object,
	revision: u32,
	pending: bool,
	tick: u32,
) {
	if entity := replication_entity_by_id(service, object.network_id); entity != nil {
		entity.pivot_revision = revision
		entity.pivot_pending = false
		if pending && entity.owner_id != 0 {
			for connection in service.peers {
				if connection.player != nil &&
				   connection.player.user_id == entity.owner_id &&
				   connection.known[object.network_id] != 0 &&
				   (connection.client_capabilities & Replication_Capability_Model_Pivot) !=
					   0 {entity.pivot_pending = true; break}
			}
		}
		entity.pivot_upload_guard = !pending
		entity.pivot_upload_after = tick
		entity.owned_window_time = 0
		entity.owned_rate_window_time = 0
		entity.owned_updates_window = 0
		entity.owned_rest_upload_tick = 0
		clear(&entity.samples)
		entity.frame_seeded = false
	}
	for child in object.children {
		if child != nil &&
		   !child.destroyed {replication_pivot_barrier(service, child, revision, pending, tick)}
	}
}

replication_model_pivoted :: proc(ctx: rawptr, model: ^classes.Model) {
	data_model := cast(^DataModel)ctx
	service := cast(^ReplicatorService)DataModel_Get_Service(data_model, "ReplicatorService")
	if service == nil || service.mode != .Server || model.network_id == 0 {return}
	entity := replication_entity_by_id(service, model.network_id)
	if entity == nil {return}
	revision := entity.pivot_revision + 1
	replication_pivot_barrier(service, &model.object, revision, true, 0)
	payload: [dynamic]u8
	defer delete(payload)
	append(&payload, 0)
	replication_put_u32(&payload, model.network_id)
	replication_put_u32(&payload, revision)
	cf := classes.Model_Get_Pivot(model)
	values := [?]f32 {
		cf.x,
		cf.y,
		cf.z,
		cf.r00,
		cf.r01,
		cf.r02,
		cf.r10,
		cf.r11,
		cf.r12,
		cf.r20,
		cf.r21,
		cf.r22,
	}
	for value in values {replication_put_f32(&payload, value)}
	for &connection in service.peers {
		if connection.handshake_complete &&
		   connection.known[model.network_id] != 0 &&
		   (connection.client_capabilities & Replication_Capability_Model_Pivot) != 0 {
			_ = replication_send(
				service,
				connection.peer,
				Replication_Kind_Model_Pivot,
				payload[:],
				true,
			)
		}
	}
}

replication_receive_model_pivot :: proc(
	service: ^ReplicatorService,
	peer: ^Replication_Transport_Peer,
	reader: ^Replication_Reader,
) {
	subtype := replication_read_u8(reader)
	id := replication_read_u32(reader)
	revision := replication_read_u32(reader)
	entity := replication_entity_by_id(service, id)
	if !reader.valid ||
	   entity == nil ||
	   entity.object == nil ||
	   entity.object.destroyed ||
	   !classes.Is_A(entity.object, "Model") {return}
	model := cast(^classes.Model)entity.object
	if subtype == 1 {
		tick := replication_read_u32(reader)
		if service.mode != .Server ||
		   !reader.valid ||
		   reader.offset != len(reader.data) ||
		   entity.pivot_revision != revision {return}

		owner: u32
		for connection in service.peers {if connection.peer == peer && connection.player != nil {owner = connection.player.user_id; break}}
		if owner == 0 {return}
		replication_pivot_ack_owner(service, entity.object, owner, revision, tick)
		return
	}
	if subtype != 0 || service.mode != .Client || peer != service.remote {return}
	cf: datatypes.CFrame
	values := cast(^[12]f32)&cf
	for &value in values {value = replication_read_f32(reader)}
	if !reader.valid ||
	   reader.offset != len(reader.data) ||
	   !replication_frame_finite(cf) ||
	   !replication_frame_rotation_valid(cf) {return}
	classes.Model_Pivot_To(model, cf)
	replication_pivot_barrier(service, entity.object, revision, false, service.tick)
	if classes.Is_A(entity.object, "CharacterModel") {
		characters := cast(^CharacterService)DataModel_Get_Service(
			service.data_model,
			"CharacterService",
		)
		players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
		if characters != nil &&
		   players != nil &&
		   players.local_player != nil &&
		   players.local_player.character == cast(^classes.CharacterModel)model {
			clear(&characters.predictions)
			characters.authoritative_received = true
			characters.last_ack = characters.input_sequence
			if root := classes.CharacterModel_Root(cast(^classes.CharacterModel)model);
			   root != nil {
				if root_entity := replication_entity_by_id(service, root.network_id);
				   root_entity !=
				   nil {root_entity.server_frame = cf; root_entity.server_frame_valid = true}
			}
		}
	}
	Physics_Request_Sync_For_Data_Model(service.data_model)
	payload: [dynamic]u8
	defer delete(payload)
	append(&payload, 1)
	replication_put_u32(&payload, id)
	replication_put_u32(&payload, revision)
	replication_put_u32(&payload, service.tick)
	_ = replication_send(service, peer, Replication_Kind_Model_Pivot, payload[:], true)
}

replication_pivot_ack_owner :: proc(
	service: ^ReplicatorService,
	object: ^classes.Object,
	owner, revision, tick: u32,
) {
	if entity := replication_entity_by_id(service, object.network_id);
	   entity != nil && entity.owner_id == owner && entity.pivot_revision == revision {
		entity.pivot_pending = false
		entity.pivot_upload_guard = true
		entity.pivot_upload_after = tick
	}
	for child in object.children {
		if child != nil &&
		   !child.destroyed {replication_pivot_ack_owner(service, child, owner, revision, tick)}
	}
}
