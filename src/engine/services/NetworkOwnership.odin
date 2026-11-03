package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

replication_broadcast_ownership :: proc(service: ^ReplicatorService, entity: ^Replication_Entity) {
	if service == nil || entity == nil {return}
	linear := entity.pending_linear_velocity
	angular := entity.pending_angular_velocity


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
	notify: bool = true,
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
		if notify {
			replication_broadcast_ownership(service, entity)
			ownership_fire_changed(service, entity, entity.owner_id)
		}
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

Ownership_Link :: struct {
	joint, attachment0, attachment1: ^Replication_Entity,
	first, second: int,
}

ownership_root :: proc(roots: []int, index: int) -> int {
	root := index
	for roots[root] != root {
		roots[root] = roots[roots[root]]
		root = roots[root]
	}
	return root
}

ownership_links :: proc(service: ^ReplicatorService, indices: map[^classes.Object]int) -> [dynamic]Ownership_Link {
	links: [dynamic]Ownership_Link
	registry := service.signal_registry
	constraint_names := [?]string{"HingeConstraint", "RopeConstraint", "WeldConstraint"}
	for name in constraint_names {
		descriptor := classes.Find_Class(registry, name)
		if descriptor == nil {continue}
		for object in descriptor.instances {
			if object == nil || object.destroyed || !replication_in_scope(service, object) {continue}
			constraint := cast(^classes.Constraint)object
			a, b: ^classes.Object
			link: Ownership_Link
			link.joint = replication_entity(service, object)
			if object.class == &classes.WeldConstraint_Class {
				weld := cast(^classes.WeldConstraint)object
				a, b = weld.part0, weld.part1
			} else {
				if object.class == &classes.HingeConstraint_Class && !constraint.enabled {continue}
				a0, a1 := constraint.attachment0, constraint.attachment1
				link.attachment0 = replication_entity(service, a0)
				link.attachment1 = replication_entity(service, a1)
				if link.attachment0 == nil || link.attachment1 == nil ||
				   link.attachment0.object.destroyed || link.attachment1.object.destroyed {continue}
				a, b = link.attachment0.object.parent, link.attachment1.object.parent
			}
			first, first_ok := indices[a]
			second, second_ok := indices[b]
			if !first_ok || !second_ok || first == second {continue}
			link.first, link.second = first, second
			append(&links, link)
		}
	}
	return links
}

ownership_group_ready :: proc(
	peer: ^Replication_Peer,
	parts: []^Replication_Entity,
	links: []Ownership_Link,
) -> bool {
	for part in parts {
		if !peer.initialized[part.id] {return false}
	}
	for link in links {
		if link.joint == nil || peer.acked_extra[link.joint.id] == 0 {return false}
		if link.attachment0 != nil && peer.acked_extra[link.attachment0.id] == 0 {return false}
		if link.attachment1 != nil && peer.acked_extra[link.attachment1.id] == 0 {return false}
	}
	return true
}

replication_transfer_group :: proc(service: ^ReplicatorService, parts: []^Replication_Entity, owner_id: u32) {
	if len(parts) > (int(Replication_Max_Frame_Payload) - 4) / OWNERSHIP_RECORD_BYTES {return}
	changed: [dynamic]^Replication_Entity
	defer delete(changed)
	for entity in parts {
		if entity.owner_id == owner_id {continue}
		replication_set_ownership(service, entity, owner_id, false, false)
		append(&changed, entity)
	}
	if len(changed) == 0 {return}
	Physics_Request_Sync_For_Data_Model(service.data_model)

	bytes: [dynamic]u8
	defer delete(bytes)
	for &peer in service.peers {
		clear(&bytes)
		replication_put_u32(&bytes, owner_id)
		for entity in changed {
			if peer.known[entity.id] == 0 {continue}
			part := cast(^classes.Part)entity.object
			frame := part.cframe
			linear, angular := entity.pending_linear_velocity, entity.pending_angular_velocity
			replication_put_u32(&bytes, entity.id)
			append(&bytes, entity.owned_as_model ? u8(1) : u8(0))
			values := [18]f32{
				frame.x, frame.y, frame.z, frame.r00, frame.r01, frame.r02,
				frame.r10, frame.r11, frame.r12, frame.r20, frame.r21, frame.r22,
				linear.x, linear.y, linear.z, angular.x, angular.y, angular.z,
			}
			for value in values {
				replication_put_f32(&bytes, value)
			}
		}
		if len(bytes) > 4 {_ = replication_send(service, peer.peer, 21, bytes[:])}
	}
	for entity in changed {ownership_fire_changed(service, entity, owner_id)}
}

replication_reclaim_disconnected_owner :: proc(service: ^ReplicatorService, owner_id: u32) {
	if owner_id == 0 {return}
	parts: [dynamic]^Replication_Entity
	defer delete(parts)
	for entity in service.entity_list {
		if entity.owner_id != owner_id || entity.object == nil || entity.object.destroyed ||
		   !classes.Is_A(entity.object, "Part") {continue}
		entity.owner_locked = false
		append(&parts, entity)
	}
	replication_transfer_group(service, parts[:], 0)
}

OWNERSHIP_RECORD_BYTES :: 4 + 1 + 18 * 4

replication_receive_group_ownership :: proc(service: ^ReplicatorService, reader: ^Replication_Reader) {
	owner := replication_read_u32(reader)
	if !reader.valid || (len(reader.data) - reader.offset) % OWNERSHIP_RECORD_BYTES != 0 {return}
	local_owner := owner != 0 && owner == ownership_local_user_id(service)
	changed: [dynamic]^Replication_Entity
	defer delete(changed)
	for reader.offset < len(reader.data) {
		entity := replication_entity_by_id(service, replication_read_u32(reader))
		model := replication_read_u8(reader) != 0
		frame := datatypes.CFrame{
			x = replication_read_f32(reader), y = replication_read_f32(reader), z = replication_read_f32(reader),
			r00 = replication_read_f32(reader), r01 = replication_read_f32(reader), r02 = replication_read_f32(reader),
			r10 = replication_read_f32(reader), r11 = replication_read_f32(reader), r12 = replication_read_f32(reader),
			r20 = replication_read_f32(reader), r21 = replication_read_f32(reader), r22 = replication_read_f32(reader),
		}
		linear := datatypes.Vector3{replication_read_f32(reader), replication_read_f32(reader), replication_read_f32(reader)}
		angular := datatypes.Vector3{replication_read_f32(reader), replication_read_f32(reader), replication_read_f32(reader)}
		if entity == nil || entity.object == nil || entity.object.destroyed ||
		   !classes.Is_A(entity.object, "Part") {continue}
		if !replication_frame_finite(frame) || !replication_vector3_finite(linear) ||
		   !replication_vector3_finite(angular) {continue}

		if entity.owner_id != owner || entity.owned_request_pending {
			append(&changed, entity)
		}
		entity.owner_id = owner
		entity.owned_as_model = model
		entity.owned_request_pending = false
		if local_owner {
			clear(&entity.samples)
			entity.sample_age = 0
			entity.frame_seeded = false
			entity.has_transform = true
			entity.pending_linear_velocity = linear
			entity.pending_angular_velocity = angular
			entity.pending_velocity_valid = true
			part := cast(^classes.Part)entity.object
			part.cframe = frame
			part.position = datatypes.CFrame_Position(frame)
		}
	}
	if len(changed) != 0 {
		Physics_Request_Sync_For_Data_Model(service.data_model)
		for entity in changed {ownership_fire_changed(service, entity, owner)}
	}
}

replication_auto_ownership_step :: proc(service: ^ReplicatorService) {
	if service == nil || service.data_model == nil || service.mode != .Server ||
	   !service.auto_ownership_enabled {return}

	parts: [dynamic]^Replication_Entity
	indices: map[^classes.Object]int
	roots: [dynamic]int
	defer delete(parts)
	defer delete(indices)
	defer delete(roots)
	for entity in service.entity_list {
		if entity == nil || entity.object == nil || entity.object.destroyed ||
		   !classes.Is_A(entity.object, "Part") || !replication_in_scope(service, entity.object) {continue}
		indices[entity.object] = len(parts)
		append(&roots, len(parts))
		append(&parts, entity)
	}
	links := ownership_links(service, indices)
	defer delete(links)
	for link in links {
		roots[ownership_root(roots[:], link.second)] = ownership_root(roots[:], link.first)
	}
	groups := make([][dynamic]^Replication_Entity, len(parts))
	group_links := make([][dynamic]Ownership_Link, len(parts))
	defer delete(groups)
	defer delete(group_links)
	for entity, index in parts {
		append(&groups[ownership_root(roots[:], index)], entity)
	}
	for link in links {
		append(&group_links[ownership_root(roots[:], link.first)], link)
	}

	acquire_sq := service.auto_ownership_acquire_radius * service.auto_ownership_acquire_radius
	release_sq := service.auto_ownership_release_radius * service.auto_ownership_release_radius
	for group, index in groups {
		defer delete(group)
		defer delete(group_links[index])
		if len(group) == 0 {continue}

		center: datatypes.Vector3
		anchored, locked := false, false
		for entity in group {
			part := cast(^classes.Part)entity.object
			anchored = anchored || part.anchored
			locked = locked || entity.owner_locked || replication_auto_owner(entity.object) != 0
			center.x += part.cframe.x
			center.y += part.cframe.y
			center.z += part.cframe.z
		}
		if locked {continue}
		current := group[0].owner_id
		for entity in group {
			if entity.owner_id != current {
				current = 0
				break
			}
		}
		count := f32(len(group))
		center.x /= count
		center.y /= count
		center.z /= count

		nearest_id, nearest_sq := u32(0), acquire_sq
		current_sq: f32
		current_found := false
		if !anchored {
			for &peer in service.peers {
				if !peer.handshake_complete || peer.player == nil || peer.player.character == nil {continue}
				focus := classes.CharacterModel_Root(peer.player.character)
				if focus == nil {continue}
				distance := replication_distance_sq(center.x, center.y, center.z, focus)
				if peer.player.user_id == current {
					current_found, current_sq = true, distance
				}
				if distance < nearest_sq && ownership_group_ready(&peer, group[:], group_links[index][:]) {
					nearest_id, nearest_sq = peer.player.user_id, distance
				}
			}
		}
		target := current
		if anchored || current == 0 || !current_found || current_sq > release_sq ||
		   (nearest_id != 0 && nearest_id != current && nearest_sq * 4 < current_sq) {
			target = nearest_id
		}
		replication_transfer_group(service, group[:], target)
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
			entities: [dynamic]^Replication_Entity
			defer delete(parts)
			defer delete(entities)
			ownership_collect_parts(object, &parts)
			for part in parts {
				if part.anchored {continue}
				entity := ownership_entity_for(replicator, &part.object)
				if entity != nil {
					entity.owned_as_model = true
					entity.owner_locked = true
					append(&entities, entity)
				}
			}
			replication_transfer_group(replicator, entities[:], owner_id)
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
			entities: [dynamic]^Replication_Entity
			defer delete(parts)
			defer delete(entities)
			ownership_collect_parts(object, &parts)
			for part in parts {
				entity := ownership_entity_for(replicator, &part.object)
				if entity != nil {
					entity.owned_as_model = false
					entity.owner_locked = false
					append(&entities, entity)
				}
			}
			replication_transfer_group(replicator, entities[:], replication_auto_owner(object))
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
