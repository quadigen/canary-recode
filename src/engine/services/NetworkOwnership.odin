package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

replication_broadcast_ownership :: proc(service: ^ReplicatorService, entity: ^Replication_Entity) {
	if service == nil || entity == nil {return}
	linear := entity.owned_linear_velocity
	angular := entity.owned_angular_velocity


	if entity.owner_id == 0 && entity.object != nil && classes.Is_A(entity.object, "Part") {
		part := cast(^classes.Part)entity.object
		if registry := service.signal_registry; registry != nil {
			linear = classes.Part_Linear_Velocity(registry, &part.object)
			angular = classes.Part_Angular_Velocity(registry, &part.object)
		}
	}
	bytes: [dynamic]u8
	defer delete(bytes)
	replication_put_u32(&bytes, entity.id)
	replication_put_u32(&bytes, entity.owner_id)
	append(&bytes, entity.owned_as_model ? u8(1) : u8(0))
	replication_put_f32(&bytes, linear.x)
	replication_put_f32(&bytes, linear.y)
	replication_put_f32(&bytes, linear.z)
	replication_put_f32(&bytes, angular.x)
	replication_put_f32(&bytes, angular.y)
	replication_put_f32(&bytes, angular.z)
	for &connection in service.peers {
		if connection.known[entity.id] != 0 {
			_ = replication_send(service, connection.peer, 10, bytes[:])
		}
	}
}

replication_set_ownership :: proc(
	service: ^ReplicatorService,
	entity: ^Replication_Entity,
	owner_id: u32,
	refresh_physics: bool = true,
) {
	if service == nil || entity == nil {return}
	previous := entity.owner_id
	entity.owner_id = owner_id
	if previous != owner_id {

		entity.pivot_pending = false
		entity.pivot_upload_guard = false
	}
	if entity.object != nil && classes.Is_A(entity.object, "Part") {
		part := cast(^classes.Part)entity.object
		entity.last_accepted_position = datatypes.Vector3 {
			part.cframe.x,
			part.cframe.y,
			part.cframe.z,
		}
		entity.last_accepted_ms = transport_time_get()
		entity.owned_window_origin = entity.last_accepted_position
		entity.owned_window_time = 0
		entity.owned_rate_window_time = 0
		entity.owned_updates_window = 0


		if previous != owner_id {
			if previous == 0 {
				if registry := service.signal_registry; registry != nil {
					entity.pending_linear_velocity = classes.Part_Linear_Velocity(
						registry,
						&part.object,
					)
					entity.pending_angular_velocity = classes.Part_Angular_Velocity(
						registry,
						&part.object,
					)
				}
			} else {
				entity.pending_linear_velocity = entity.owned_linear_velocity
				entity.pending_angular_velocity = entity.owned_angular_velocity
			}
			entity.pending_velocity_valid = true
		}
		if refresh_physics {
			physics := cast(^Physics)DataModel_Get_Service(service.data_model, "Physics")
			if physics != nil {physics_refresh_part(physics, part)}
		}
	}
	if previous != owner_id {
		if previous != 0 {entity.force_correction = true}
		replication_broadcast_ownership(service, entity)
		ownership_fire_changed(service, entity, entity.owner_id)
	}
}

replication_auto_owner :: proc(object: ^classes.Object) -> u32 {
	if object == nil {return 0}
	for current := object; current != nil; current = current.parent {
		if classes.Is_A(current, "CharacterModel") {
			model := cast(^classes.CharacterModel)current
			if model.owner_user_id != 0 {return model.owner_user_id}
			break
		}
	}
	return 0
}


REPLICATION_AUTO_OWNERSHIP_INTERVAL :: 0.1

replication_auto_ownership_step :: proc(service: ^ReplicatorService) {
	if service == nil ||
	   service.data_model == nil ||
	   service.mode != .Server ||
	   !service.auto_ownership_enabled {return}
	players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
	if players == nil {return}


	Ownership_Player :: struct {
		user_id: u32,
		x, y, z: f32,
	}
	max_players := 64
	connected := 0
	snapshot: [64]Ownership_Player
	for &connection in service.peers {
		if connected >= max_players {break}
		if connection.player == nil || connection.player.character == nil {continue}
		part := replication_peer_focus_part(service, connection.player.user_id)
		if part == nil {continue}
		snapshot[connected] = Ownership_Player {
			connection.player.user_id,
			part.cframe.x,
			part.cframe.y,
			part.cframe.z,
		}
		connected += 1
	}
	if connected == 0 {return}

	acquire_sq := service.auto_ownership_acquire_radius * service.auto_ownership_acquire_radius
	release_sq := service.auto_ownership_release_radius * service.auto_ownership_release_radius

	for entity in service.entity_list {
		if entity == nil ||
		   entity.owner_locked ||
		   entity.object == nil ||
		   entity.object.destroyed ||
		   !classes.Is_A(entity.object, "Part") ||
		   !replication_in_scope(service, entity.object) {continue}
		part := cast(^classes.Part)entity.object
		if part.anchored {continue}


		if replication_auto_owner(&part.object) != 0 {continue}

		nearest_id: u32
		nearest_sq := acquire_sq
		owner_sq := f32(0)
		owner_found := false
		for p in snapshot[:connected] {
			dx := part.cframe.x - p.x
			dy := part.cframe.y - p.y
			dz := part.cframe.z - p.z
			d := dx * dx + dy * dy + dz * dz
			if p.user_id == entity.owner_id {
				owner_sq = d
				owner_found = true
			}
			if d < nearest_sq {
				nearest_sq = d
				nearest_id = p.user_id
			}
		}

		target := entity.owner_id
		if entity.owner_id == 0 {
			target = nearest_id
		} else if !owner_found || owner_sq > release_sq {


			target = nearest_id
		} else if nearest_id != 0 && nearest_id != entity.owner_id && nearest_sq * 4 < owner_sq {


			target = nearest_id
		}
		if target != entity.owner_id {
			replication_set_ownership(service, entity, target)
		}
	}
}

replication_send_ownership_request :: proc(
	service: ^ReplicatorService,
	entity: ^Replication_Entity,
	automatic: bool,
) -> bool {
	if service == nil ||
	   entity == nil ||
	   service.mode != .Client ||
	   service.remote == nil {return false}
	entity.owned_request_pending = true
	bytes: [dynamic]u8
	defer delete(bytes)
	replication_put_u32(&bytes, entity.id)
	append(&bytes, automatic ? u8(1) : u8(0))
	return replication_send(service, service.remote, 13, bytes[:], true)
}

replication_receive_ownership_request :: proc(
	service: ^ReplicatorService,
	peer: ^Replication_Transport_Peer,
	reader: ^Replication_Reader,
) {
	if service == nil || service.mode != .Server {reader.valid = false; return}
	id := replication_read_u32(reader)
	if reader.offset >= len(reader.data) {reader.valid = false; return}
	automatic := reader.data[reader.offset] != 0
	reader.offset += 1
	connection: ^Replication_Peer
	for &candidate in service.peers {if candidate.peer == peer {connection = &candidate; break}}
	if !reader.valid || connection == nil || connection.player == nil {return}
	entity := replication_entity_by_id(service, id)
	if entity == nil ||
	   entity.object == nil ||
	   entity.object.destroyed ||
	   !classes.Is_A(entity.object, "Part") ||
	   !replication_in_scope(service, entity.object) {return}
	part := cast(^classes.Part)entity.object
	if part.anchored && !automatic {return}
	if automatic {
		entity.owner_locked = false
		replication_set_ownership(service, entity, replication_auto_owner(entity.object))
		return
	}
	entity.owner_locked = true
	replication_set_ownership(service, entity, connection.player.user_id)
}

ownership_entity_for :: proc(
	service: ^ReplicatorService,
	object: ^classes.Object,
) -> ^Replication_Entity {
	if service == nil || object == nil {return nil}
	entity := replication_entity(service, object)
	if entity != nil {return entity}
	if !replication_in_scope(service, object) {return nil}
	id := replication_register(service, object)
	if id == 0 {return nil}
	return replication_entity_by_id(service, id)
}

ownership_collect_parts :: proc(object: ^classes.Object, parts: ^[dynamic]^classes.Part) {
	if object == nil {return}
	for child in object.children {
		if child == nil || child.destroyed {continue}
		if classes.Is_A(child, "Part") {append(parts, cast(^classes.Part)child)}
		ownership_collect_parts(child, parts)
	}
}

ownership_find_first_part :: proc(object: ^classes.Object) -> ^classes.Part {
	if object == nil {return nil}
	for child in object.children {
		if child == nil || child.destroyed {continue}
		if classes.Is_A(child, "Part") {return cast(^classes.Part)child}
		part := ownership_find_first_part(child)
		if part != nil {return part}
	}
	return nil
}

ownership_fire_changed :: proc(
	service: ^ReplicatorService,
	entity: ^Replication_Entity,
	owner_id: u32,
) {
	if service == nil || entity == nil || entity.object == nil {return}
	if !classes.Is_A(entity.object, "Part") {return}
	part := cast(^classes.Part)entity.object
	if part.ownership_changed == nil {return}
	if service.signal_registry == nil || service.signal_registry.vm_state == nil {return}
	L := service.signal_registry.vm_state.L
	if L == nil {return}
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	_ = ownership_push_owner(L, service, owner_id)
	signals.Fire(L, part.ownership_changed, 1)
}

ownership_local_user_id :: proc(service: ^ReplicatorService) -> u32 {
	players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
	if players != nil && players.local_player != nil {return players.local_player.user_id}
	return 0
}

ownership_push_owner :: proc(L: ^vm.State, service: ^ReplicatorService, owner_id: u32) -> i32 {
	if owner_id == 0 {
		vm.PushNil(L)
		return 1
	}
	players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
	if players != nil {
		for child in players.children {
			if child != nil &&
			   !child.destroyed &&
			   classes.Is_A(child, "Player") &&
			   (cast(^Player)child).user_id == owner_id {
				classes.Push_Object(L, child)
				return 1
			}
		}
	}
	vm.PushNil(L)
	return 1
}

ownership_ancestral_part :: proc(object: ^classes.Object) -> (^classes.Object, bool, bool) {

	if object == nil {return nil, false, false}
	return object, classes.Is_A(object, "Part"), classes.Is_A(object, "Model")
}

network_ownership_set :: proc(
	L: ^vm.State,
	replicator: ^ReplicatorService,
	object: ^classes.Object,
) -> i32 {
	if replicator.mode == .Stopped {return vm.RaiseError(L, "Replication is not running")}
	if object == nil ||
	   object.destroyed {return vm.RaiseError(L, "SetNetworkOwner requires a live instance")}
	target: ^Player = nil
	if !vm.IsNoneOrNil(L, 2) {
		player_object := collection_object_from_argument(L, 2)
		if player_object == nil ||
		   !classes.Is_A(
				   player_object,
				   "Player",
			   ) {return vm.RaiseError(L, "SetNetworkOwner expects a Player or nil")}
		target = cast(^Player)player_object
	}
	if classes.Is_A(object, "Part") {
		part := cast(^classes.Part)object
		if part.anchored {return vm.RaiseError(L, "Cannot change the network owner of an anchored part")}
	}
	if replicator.mode == .Server {
		if target != nil {
			connected := false
			for connection in replicator.peers {
				if connection.player != nil &&
				   connection.player == target {connected = true; break}
			}
			if !connected {return vm.RaiseError(L, "That player is not connected")}
		}
		owner_id := target == nil ? u32(0) : target.user_id
		if classes.Is_A(object, "Model") {
			parts: [dynamic]^classes.Part
			defer delete(parts)
			ownership_collect_parts(object, &parts)
			for part in parts {
				entity := ownership_entity_for(replicator, &part.object)
				if entity != nil {
					entity.owned_as_model = true
					entity.owner_locked = true
					replication_set_ownership(replicator, entity, owner_id)
				}
			}
			return 0
		}
		entity := ownership_entity_for(replicator, object)
		if entity != nil {
			entity.owned_as_model = false
			entity.owner_locked = true
			replication_set_ownership(replicator, entity, owner_id)
		}
		return 0
	}
	if replicator.mode == .Client {
		local_id := ownership_local_user_id(replicator)
		if target != nil && target.user_id != local_id {
			return vm.RaiseError(
				L,
				"SetNetworkOwner must be called with your own Player on a client",
			)
		}
		if classes.Is_A(object, "Model") {
			parts: [dynamic]^classes.Part
			defer delete(parts)
			ownership_collect_parts(object, &parts)
			for part in parts {
				entity := replication_entity(replicator, &part.object)
				if entity == nil {continue}
				entity.owned_as_model = target != nil
				if target != nil {entity.owner_id = target.user_id}
				_ = replication_send_ownership_request(replicator, entity, target == nil)
			}
			return 0
		}
		entity := replication_entity(replicator, object)
		if entity != nil {
			entity.owned_as_model = false
			if target != nil {entity.owner_id = target.user_id}
			_ = replication_send_ownership_request(replicator, entity, target == nil)
		}
		return 0
	}
	return vm.RaiseError(L, "Replication is not running")
}

network_ownership_get :: proc(
	L: ^vm.State,
	replicator: ^ReplicatorService,
	object: ^classes.Object,
) -> i32 {
	owner_id: u32
	if classes.Is_A(object, "Model") {
		entity := replication_entity(replicator, object)
		if entity != nil {
			owner_id = entity.owner_id
		} else {
			part := ownership_find_first_part(object)
			if part != nil {
				entity := replication_entity(replicator, &part.object)
				if entity != nil {owner_id = entity.owner_id}
			}
		}
	} else {
		entity := replication_entity(replicator, object)
		if entity != nil {owner_id = entity.owner_id}
	}
	return ownership_push_owner(L, replicator, owner_id)
}

network_ownership_auto :: proc(
	L: ^vm.State,
	replicator: ^ReplicatorService,
	object: ^classes.Object,
) -> i32 {
	if replicator.mode == .Stopped {return vm.RaiseError(L, "Replication is not running")}
	if object == nil || object.destroyed {return 0}
	if replicator.mode == .Server {
		if classes.Is_A(object, "Model") {
			parts: [dynamic]^classes.Part
			defer delete(parts)
			ownership_collect_parts(object, &parts)
			for part in parts {
				entity := ownership_entity_for(replicator, &part.object)
				if entity != nil {
					entity.owned_as_model = false
					entity.owner_locked = false
					replication_set_ownership(
						replicator,
						entity,
						replication_auto_owner(&part.object),
					)
				}
			}
			return 0
		}
		if classes.Is_A(object, "Part") {
			entity := ownership_entity_for(replicator, object)
			if entity != nil {
				entity.owned_as_model = false
				entity.owner_locked = false
				replication_set_ownership(replicator, entity, replication_auto_owner(object))
			}
		}
		return 0
	}
	if replicator.mode == .Client {
		if classes.Is_A(object, "Model") {
			parts: [dynamic]^classes.Part
			defer delete(parts)
			ownership_collect_parts(object, &parts)
			for part in parts {
				entity := replication_entity(replicator, &part.object)
				if entity != nil {
					entity.owned_as_model = false
					_ = replication_send_ownership_request(replicator, entity, true)
				}
			}
			return 0
		}
		entity := replication_entity(replicator, object)
		if entity != nil {
			entity.owned_as_model = false
			_ = replication_send_ownership_request(replicator, entity, true)
		}
		return 0
	}
	return vm.RaiseError(L, "Replication is not running")
}

ownership_status_get :: proc(
	L: ^vm.State,
	replicator: ^ReplicatorService,
	object: ^classes.Object,
) -> (
	i32,
	bool,
) {
	entity: ^Replication_Entity
	if classes.Is_A(object, "Model") {


		part := ownership_find_first_part(object)
		if part != nil {entity = replication_entity(replicator, &part.object)}
	} else {
		entity = replication_entity(replicator, object)
	}
	status := enums.NetworkOwnership.Unknown
	if entity != nil && entity.object != nil && !entity.object.destroyed {
		switch {
		case entity.owner_id == 0:
			status =
				entity.owned_as_model ? enums.NetworkOwnership.ServerPart : enums.NetworkOwnership.Server
		case replicator.mode == .Client && entity.owner_id == ownership_local_user_id(replicator):
			status =
				entity.owned_as_model ? enums.NetworkOwnership.ClientPart : enums.NetworkOwnership.Client
		case:
			status =
				entity.owned_as_model ? enums.NetworkOwnership.ServerPart : enums.NetworkOwnership.Server
		}
	}
	enum_registry: ^enums.Registry
	if replicator.signal_registry != nil {enum_registry = replicator.signal_registry.enums}
	if enum_registry == nil {
		vm.PushNil(L)
		return 1, true
	}
	_ = enums.Push_Item_By_Value(L, enum_registry, "NetworkOwnership", i64(status))
	return 1, true
}

network_ownership_namecall :: proc(
	ctx: rawptr,
	L: ^vm.State,
	object: ^classes.Object,
	method: string,
) -> (
	i32,
	bool,
) {
	if object == nil || object.destroyed || ctx == nil {return 0, false}
	data_model := cast(^DataModel)ctx
	if data_model == nil || data_model.registry == nil {return 0, false}
	replicator := cast(^ReplicatorService)DataModel_Get_Service(data_model, "ReplicatorService")
	if replicator == nil {return 0, false}
	is_part := classes.Is_A(object, "Part")
	is_model := classes.Is_A(object, "Model")
	if !is_part && !is_model {return 0, false}
	switch method {
	case "SetNetworkOwner":
		return network_ownership_set(L, replicator, object), true
	case "GetNetworkOwner":
		return network_ownership_get(L, replicator, object), true
	case "GetNetworkOwnershipStatus":
		return ownership_status_get(L, replicator, object)
	case "SetNetworkOwnershipAuto":
		return network_ownership_auto(L, replicator, object), true
	}
	return 0, false
}
