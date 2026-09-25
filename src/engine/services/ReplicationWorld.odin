#+build !js
package services

import classes "../classes"
import datatypes "../datatypes"
import vm "../vm"
import "core:fmt"
import "core:strings"
import enet "vendor:ENet"

replication_entity_id :: proc(service: ^ReplicatorService, object: ^classes.Object) -> u32 {
	for item in service.entities {if item.object == object {return item.id}}
	return 0
}

replication_entity_object :: proc(service: ^ReplicatorService, id: u32) -> ^classes.Object {
	for item in service.entities {if item.id == id {return item.object}}
	return nil
}

replication_entity_by_id :: proc(service: ^ReplicatorService, id: u32) -> ^Replication_Entity {
	for &item in service.entities {if item.id == id {return &item}}
	return nil
}

replication_forget_destroyed :: proc(service: ^ReplicatorService, object: ^classes.Object) {
	if service == nil || object == nil {return}
	for &connection in service.peers {
		if connection.player != nil &&
		   &connection.player.object == object {connection.player = nil}
	}
	delete_key(&service.suppressed, object)
	for item, index in service.entities {
		if item.object != object {continue}
		if service.mode == .Server {
			for &connection in service.peers {
				if connection.known[item.id] == 0 {continue}
				bytes: [dynamic]u8
				replication_put_u32(&bytes, item.id)
				_ = replication_send(service, connection.peer, 8, bytes[:])
				delete(bytes)
				delete_key(&connection.known, item.id)
				delete_key(&connection.initialized, item.id)
				delete_key(&connection.state_hashes, item.id)
				delete_key(&connection.property_hashes, item.id)
			}
		}
		delete(item.recipients)
		delete(item.samples)
		ordered_remove(&service.entities, index)
		break
	}
}

replication_register :: proc(service: ^ReplicatorService, object: ^classes.Object) -> u32 {
	if object == nil || object.destroyed || service.mode != .Server {return 0}
	delete_key(&service.suppressed, object)
	id := replication_entity_id(service, object)
	if id != 0 {return id}
	id = service.next_id
	service.next_id += 1
	append(&service.entities, Replication_Entity{id = id, object = object})
	object.network_id = id
	return id
}

replication_entity :: proc(
	service: ^ReplicatorService,
	object: ^classes.Object,
) -> ^Replication_Entity {
	for &item in service.entities {if item.object == object {return &item}}
	return nil
}

replication_schema :: proc(
	service: ^ReplicatorService,
	class_name: string,
) -> ^Replication_Schema {
	for &schema in service.schemas {
		if schema.class_name == class_name {return &schema}
	}
	if service == nil ||
	   service.data_model == nil ||
	   service.data_model.registry == nil ||
	   service.data_model.registry.classes == nil {
		return nil
	}
	if replication_builtin_class(class_name) {
		return nil
	}
	properties := classes.Class_Property_List(
		service.data_model.registry.classes,
		class_name,
	)
	schema: Replication_Schema
	schema.class_name = strings.clone(class_name)
	for property in properties {
		switch property {
		case "Parent", "Name", "ReplicationMode", "ReplicationGroup",
		     "AbsolutePosition", "AbsoluteSize",
		     "TextBounds", "SelectedText", "LineCount",
		     "AbsoluteCellCount", "AbsoluteCellSize", "AbsoluteContentSize":
			continue
		}
		append(&schema.properties, strings.clone(property))
	}
	delete(properties)
	if len(schema.properties) == 0 {
		delete(schema.class_name)
		return nil
	}
	append(&service.schemas, schema)
	return &service.schemas[len(service.schemas) - 1]
}

replication_schema_has :: proc(schema: ^Replication_Schema, property: string) -> bool {
	if schema == nil {return false}
	for item in schema.properties {if item == property {return true}}
	return false
}

replication_builtin_class :: proc(class_name: string) -> bool {
	return(
		class_name == "Part" ||
		class_name == "MeshPart" ||
		class_name == "Model" ||
		class_name == "CharacterModel" ||
		class_name == "Folder" ||
		class_name == "PlayerScripts" ||
		class_name == "PlayerGui" ||
		class_name == "StarterCharacterScripts" ||
		class_name == "BoolValue" ||
		class_name == "IntValue" ||
		class_name == "NumberValue" ||
		class_name == "StringValue" ||
		class_name == "Vector3Value" ||
		class_name == "Color3Value" ||
		class_name == "CFrameValue" ||
		class_name == "RemoteEvent" ||
		class_name == "RemoteFunction" ||
		class_name == "StateMachine" ||
		class_name == "CharacterMotor" ||
		class_name == "MovementController" ||
		class_name == "GroundDetector" ||
		class_name == "CollisionController" ||
		class_name == "RotationController" ||
		class_name == "CharacterAnimator" ||
		class_name == "CharacterInput" ||
		class_name == "CharacterCamera" \
	)
}

character_subtree_class :: proc(class_name: string) -> bool {
	switch class_name {
	case "CharacterController",
	     "Humanoid",
	     "CharacterMotor",
	     "MovementController",
	     "GroundDetector",
	     "RotationController",
	     "StateMachine",
	     "CollisionController",
	     "CharacterAnimator",
	     "CharacterInput",
	     "CharacterCamera":
		return true
	}
	return false
}

replication_builtin_property :: proc(object: ^classes.Object, property: string) -> bool {
	return object != nil &&
	       classes.Is_A(object, "MeshPart") &&
	       (property == "MeshId" || property == "TextureId")
}

REPLICATION_ROOT_NAMES := [?]string {
	"Workspace",
	"ReplicatedFirst",
	"ReplicatedStorage",
	"Lighting",
	"SoundService",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
}

replication_root_allowed :: proc(name: string) -> bool {
	for candidate in REPLICATION_ROOT_NAMES {if candidate == name {return true}}
	return false
}

replication_group_contains :: proc(
	service: ^ReplicatorService,
	user_id: u32,
	name: string,
) -> bool {
	for member in service.group_members {if member.user_id == user_id && member.name == name {return true}}
	return false
}

replication_visible :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	object: ^classes.Object,
) -> bool {
	if !replication_in_scope(service, object) || connection.player == nil {return false}
	for current := object;
	    current != nil && !classes.Is_A(current, "Service");
	    current = current.parent {
		if !current.can_replicate {return false}
		switch current.replication_mode {
		case .Never, .ServerOnly:
			return false
		case .OwnerOnly:
			entity := replication_entity(service, current)
			if entity == nil || entity.owner_id != connection.player.user_id {return false}
		case .Manual:
			entity := replication_entity(service, current)
			if entity == nil || !entity.recipients[connection.player.user_id] {return false}
		case .Automatic:
		}
		if current.replication_group != "" &&
		   !replication_group_contains(
				   service,
				   connection.player.user_id,
				   current.replication_group,
			   ) {return false}
	}
	return true
}

replication_relevant :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	object: ^classes.Object,
) -> bool {
	if connection.player == nil || object == nil || !classes.Is_A(object, "Part") {return true}
	focus: ^classes.Part
	for entity in service.entities {
		if entity.owner_id == connection.player.user_id &&
		   entity.object != nil &&
		   classes.Is_A(entity.object, "Part") {
			focus = cast(^classes.Part)entity.object
			break
		}
	}
	if focus == nil {return true}
	part := cast(^classes.Part)object
	dx := part.cframe.x - focus.cframe.x
	dy := part.cframe.y - focus.cframe.y
	dz := part.cframe.z - focus.cframe.z
	return dx * dx + dy * dy + dz * dz <= service.relevancy_distance * service.relevancy_distance
}

replication_send_spawn :: proc(
	service: ^ReplicatorService,
	peer: ^enet.Peer,
	object: ^classes.Object,
) -> bool {
	id := replication_entity_id(service, object)
	if id == 0 {return false}
	parent_id := replication_entity_id(service, object.parent)
	bytes: [dynamic]u8
	defer delete(bytes)
	replication_put_u32(&bytes, id)
	replication_put_u32(&bytes, parent_id)
	replication_put_string(&bytes, classes.Get_Class_Name(object))
	replication_put_string(&bytes, object.name)
	replication_put_string(
		&bytes,
		parent_id == 0 && object.parent != nil ? object.parent.name : "",
	)
	owner_user_id: u32
	if classes.Is_A(
		object,
		"CharacterModel",
	) {owner_user_id = (cast(^classes.CharacterModel)object).owner_user_id}
	replication_put_u32(&bytes, owner_user_id)
	if !replication_send(service, peer, 7, bytes[:]) {return false}
	entity := replication_entity(service, object)
	if entity != nil && entity.owner_id != 0 {
		ownership: [dynamic]u8
		replication_put_u32(&ownership, id)
		replication_put_u32(&ownership, entity.owner_id)
		_ = replication_send(service, peer, 10, ownership[:])
		delete(ownership)
	}
	return true
}

replication_send_owned_state :: proc(
	service: ^ReplicatorService,
	entity: ^Replication_Entity,
) -> bool {
	if entity == nil ||
	   entity.object == nil ||
	   entity.object.destroyed ||
	   !classes.Is_A(entity.object, "Part") {return false}
	part := cast(^classes.Part)entity.object
	if part.anchored &&
	   (part.parent == nil || !classes.Is_A(part.parent, "CharacterModel")) {return false}
	bytes: [dynamic]u8
	defer delete(bytes)
	replication_put_u32(&bytes, entity.id)
	replication_put_u32(&bytes, service.tick)
	values := [12]f32 {
		part.cframe.x,
		part.cframe.y,
		part.cframe.z,
		part.cframe.r00,
		part.cframe.r01,
		part.cframe.r02,
		part.cframe.r10,
		part.cframe.r11,
		part.cframe.r12,
		part.cframe.r20,
		part.cframe.r21,
		part.cframe.r22,
	}
	for value in values {replication_put_f32(&bytes, value)}
	return replication_send(service, service.remote, 11, bytes[:], false)
}

replication_send_part_state :: proc(
	service: ^ReplicatorService,
	peer: ^enet.Peer,
	part: ^classes.Part,
	previous_hash: u64 = 0,
	suppress_unchanged: bool = false,
) -> (bool, u64, bool) {
	bytes: [dynamic]u8
	defer delete(bytes)
	append(&bytes, 1)
	replication_put_u32(&bytes, replication_entity_id(service, &part.object))
	replication_put_u32(&bytes, service.tick)
	replication_put_string(&bytes, part.name)
	replication_put_f32(&bytes, part.cframe.x)
	replication_put_f32(&bytes, part.cframe.y)
	replication_put_f32(&bytes, part.cframe.z)
	replication_put_f32(&bytes, part.cframe.r00)
	replication_put_f32(&bytes, part.cframe.r01)
	replication_put_f32(&bytes, part.cframe.r02)
	replication_put_f32(&bytes, part.cframe.r10)
	replication_put_f32(&bytes, part.cframe.r11)
	replication_put_f32(&bytes, part.cframe.r12)
	replication_put_f32(&bytes, part.cframe.r20)
	replication_put_f32(&bytes, part.cframe.r21)
	replication_put_f32(&bytes, part.cframe.r22)
	replication_put_f32(&bytes, part.size.x)
	replication_put_f32(&bytes, part.size.y)
	replication_put_f32(&bytes, part.size.z)
	replication_put_f32(&bytes, part.color.R)
	replication_put_f32(&bytes, part.color.G)
	replication_put_f32(&bytes, part.color.B)
	replication_put_f32(&bytes, f32(part.transparency))
	append(&bytes, part.anchored ? u8(1) : u8(0))
	append(&bytes, part.can_collide ? u8(1) : u8(0))
	append(&bytes, u8(part.material))
	append(&bytes, u8(part.shape))
	ack: u32
	if part.parent != nil &&
	   classes.Is_A(part.parent, "CharacterModel") &&
	   part.name == "HumanoidRootPart" {
		model := cast(^classes.CharacterModel)part.parent
		players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
		if players != nil {
			for child in players.children {
				if child != nil &&
				   !child.destroyed &&
				   classes.Is_A(child, "Player") &&
				   (cast(^Player)child).user_id == model.owner_user_id {
					ack = (cast(^Player)child).input_sequence
					break
				}
			}
		}
	}
	replication_put_u32(&bytes, ack)
	hash: u64 = 14695981039346656037
	for byte in bytes[9:] {
		hash = (hash ~ u64(byte)) * 1099511628211
	}
	if suppress_unchanged && hash == previous_hash {return true, hash, true}
	return replication_send(service, peer, 5, bytes[:], false), hash, false
}

replication_send_property :: proc(
	service: ^ReplicatorService,
	L: ^vm.State,
	peer: ^enet.Peer,
	object: ^classes.Object,
	property: string,
) -> bool {
	if service == nil || L == nil || object == nil || object.destroyed {return false}
	bytes: [dynamic]u8
	defer delete(bytes)
	append(&bytes, 2)
	replication_put_u32(&bytes, replication_entity_id(service, object))
	replication_put_u32(&bytes, service.tick)
	replication_put_string(&bytes, property)
	top := vm.StackTop(L)
	previous := vm.GetThreadSecurityCapabilities(L)
	vm.SetThreadSecurityCapabilities(L, vm.THREAD_SECURITY_ALL)
	defer vm.SetThreadSecurityCapabilities(L, previous)
	defer vm.SetStackTop(L, top)
	classes.Push_Object(L, object)
	_ = vm.GetField(L, -1, property)
	if !replication_encode_value(L, -1, &bytes, 0) {return false}
	return replication_send(service, peer, 5, bytes[:], false)
}

replication_sync_tree :: proc(service: ^ReplicatorService, object: ^classes.Object) {
	if object == nil || object.destroyed || object == &service.object {return}
	if object != &service.data_model.object &&
	   (replication_builtin_class(classes.Get_Class_Name(object)) ||
			   replication_schema(service, classes.Get_Class_Name(object)) != nil) &&
	   !service.suppressed[object] {
		_ = replication_register(service, object)
	}
	for child in object.children {replication_sync_tree(service, child)}
}

replication_in_scope :: proc(service: ^ReplicatorService, object: ^classes.Object) -> bool {
	if object == nil || object.destroyed {return false}
	for current := object; current != nil; current = current.parent {
		if current.parent == &service.data_model.object &&
		   classes.Is_A(current, "Service") &&
		   replication_root_allowed(current.name) {return true}
		if current == &service.data_model.object {return false}
	}
	return false
}

replication_sync :: proc(service: ^ReplicatorService) {
	if service.mode != .Server || service.data_model == nil {return}
	for root_name in REPLICATION_ROOT_NAMES {
		replication_sync_tree(service, DataModel_Get_Service(service.data_model, root_name))
	}

	// -------------------------------------------------------------------------
	// Adaptive load control
	//
	// Each server tick we look at how many packets were dropped since the last
	// sync.  When pressure rises we temporarily widen the per-connection budget
	// and push the snapshot rate up toward 30 Hz so the client gets more frames
	// and the buffer stays fed.  When things calm down we cool back toward the
	// base values over about two seconds so we don't oscillate.
	// -------------------------------------------------------------------------
	drops_this_tick := service.bandwidth_drops
	if drops_this_tick > 0 {
		// Accumulate pressure; each dropped packet adds 1 unit.
		service.load_pressure = min(service.load_pressure + f32(drops_this_tick), 60)
	} else {
		// Cool down: subtract 0.5 per tick so it takes ~2 s at 20 Hz to clear.
		service.load_pressure = max(service.load_pressure - 0.5, 0)
	}
	// Reset the per-tick drop counter *after* reading it above.
	service.bandwidth_drops = 0

	if service.load_pressure > 0 {
		// Scale budget up to 2× base and snapshot_rate up to 30 Hz, linearly
		// proportional to pressure (0–60).
		t := min(service.load_pressure / 60, 1)
		service.bandwidth_budget = u32(
			f32(service.base_bandwidth_budget) * (1 + t),
		)
		service.snapshot_rate = service.base_snapshot_rate + t * (30 - service.base_snapshot_rate)
	} else {
		service.bandwidth_budget = service.base_bandwidth_budget
		service.snapshot_rate = service.base_snapshot_rate
	}

	// Update velocity_sq on each Part entity so the priority sort below can
	// rank fast-moving parts ahead of stationary ones.
	for &item in service.entities {
		if item.object == nil ||
		   item.object.destroyed ||
		   !classes.Is_A(item.object, "Part") {
			item.velocity_sq = 0
			continue
		}
		part := cast(^classes.Part)item.object
		if part.anchored {
			item.velocity_sq = 0
			continue
		}
		// Approximate velocity from the delta between the current CFrame and
		// the most recent sample on the entity (server-side last_frame stored
		// in last_accepted_position — repurpose it here).
		dx := part.cframe.x - item.last_accepted_position.x
		dy := part.cframe.y - item.last_accepted_position.y
		dz := part.cframe.z - item.last_accepted_position.z
		item.velocity_sq = dx * dx + dy * dy + dz * dz
		item.last_accepted_position = datatypes.Vector3{part.cframe.x, part.cframe.y, part.cframe.z}
	}

	for &connection in service.peers {
		connection.bytes_this_tick = 0

		// -----------------------------------------------------------------------
		// Phase 1: Spawns — always reliable, skip bandwidth check.
		// -----------------------------------------------------------------------
		spawned := 0
		for item in service.entities {
			if !replication_visible(service, &connection, item.object) ||
			   service.suppressed[item.object] {continue}
			parent_id := replication_entity_id(service, item.object.parent)
			if parent_id != 0 && connection.known[parent_id] == 0 {continue}
			if connection.known[item.id] == parent_id + 1 {continue}
			if connection.known[item.id] != 0 {
				bytes: [dynamic]u8
				replication_put_u32(&bytes, item.id)
				_ = replication_send(service, connection.peer, 8, bytes[:])
				delete(bytes)
			}
			if replication_send_spawn(service, connection.peer, item.object) {
				connection.known[item.id] = parent_id + 1
				delete_key(&connection.initialized, item.id)
				delete_key(&connection.state_hashes, item.id)
				delete_key(&connection.property_hashes, item.id)
				spawned += 1
			}
		}

		// -----------------------------------------------------------------------
		// Phase 2: Despawns
		// -----------------------------------------------------------------------
		for item in service.entities {
			if connection.known[item.id] == 0 {continue}
			if replication_visible(service, &connection, item.object) &&
			   !service.suppressed[item.object] {continue}
			bytes: [dynamic]u8
			replication_put_u32(&bytes, item.id)
			_ = replication_send(service, connection.peer, 8, bytes[:])
			delete(bytes)
			delete_key(&connection.known, item.id)
			delete_key(&connection.initialized, item.id)
			delete_key(&connection.state_hashes, item.id)
			delete_key(&connection.property_hashes, item.id)
		}

		// -----------------------------------------------------------------------
		// Phase 3: State sends — sort Part entities so fast-moving unanchored
		// parts come first and are never starved by the bandwidth budget.
		//
		// Strategy:
		//   • First pass: guarantee first-state sends for newly spawned entities
		//     (initialized == false). These bypass the bandwidth check so the
		//     client always receives at least one authoritative frame right after
		//     a spawn.
		//   • Second pass: sort the remaining (already-initialized) entities
		//     by velocity_sq descending and send in that order so fast parts
		//     fill the budget before slow/stationary ones.
		// -----------------------------------------------------------------------

		// First: guarantee initial state for any entity that just spawned this
		// tick (initialized == false), ignoring the bandwidth limiter.
		for item in service.entities {
			if connection.known[item.id] == 0 ||
			   item.object == nil ||
			   item.object.destroyed {continue}
			if connection.initialized[item.id] {continue} // handled below

			sent := false
			if classes.Is_A(item.object, "Part") {
				// Force-send regardless of budget by passing suppress_unchanged=false
				// and not checking the budget — the send itself will account for it.
				state_sent, state_hash, _ := replication_send_part_state(
					service,
					connection.peer,
					cast(^classes.Part)item.object,
					0,
					false,
				)
				sent = state_sent
				if sent {connection.state_hashes[item.id] = state_hash}
			} else {
				sent = replication_send_property(
					service,
					service.data_model.registry.vm_state.L,
					connection.peer,
					item.object,
					"Name",
				)
				if classes.Is_A(item.object, "ValueBase") {
					_ = replication_send_property(
						service,
						service.data_model.registry.vm_state.L,
						connection.peer,
						item.object,
						"Value",
					)
				}
			}
			if sent {connection.initialized[item.id] = true}
			replication_send_extra_properties(service, &connection, item)
		}

		// Second: build a priority-sorted slice of already-initialized entity
		// indices then send in velocity order.
		sorted_indices: [dynamic]int
		defer delete(sorted_indices)
		for item, index in service.entities {
			if connection.known[item.id] == 0 ||
			   item.object == nil ||
			   item.object.destroyed {continue}
			if !connection.initialized[item.id] {continue} // already handled above
			if !replication_relevant(service, &connection, item.object) {continue}
			append(&sorted_indices, index)
		}
		// Insertion-sort by velocity_sq descending — N is typically small
		// (hundreds, not thousands) so this is fine.
		for i := 1; i < len(sorted_indices); i += 1 {
			key_idx := sorted_indices[i]
			key_vel := service.entities[key_idx].velocity_sq
			j := i - 1
			for j >= 0 && service.entities[sorted_indices[j]].velocity_sq < key_vel {
				sorted_indices[j + 1] = sorted_indices[j]
				j -= 1
			}
			sorted_indices[j + 1] = key_idx
		}

		for index in sorted_indices {
			item := service.entities[index]
			if classes.Is_A(item.object, "Part") {
				state_sent, state_hash, unchanged := replication_send_part_state(
					service,
					connection.peer,
					cast(^classes.Part)item.object,
					connection.state_hashes[item.id],
					true,
				)
				if unchanged {
					service.unchanged_states_skipped += 1
				} else if state_sent {
					connection.state_hashes[item.id] = state_hash
				}
			} else {
				_ = replication_send_property(
					service,
					service.data_model.registry.vm_state.L,
					connection.peer,
					item.object,
					"Name",
				)
				if classes.Is_A(item.object, "ValueBase") {
					_ = replication_send_property(
						service,
						service.data_model.registry.vm_state.L,
						connection.peer,
						item.object,
						"Value",
					)
				}
			}
			replication_send_extra_properties(service, &connection, item)
		}

		if spawned > 0 && connection.player != nil {
			fmt.printf(
				"[Replication] sent initial snapshot to %s (%d instances)\n",
				connection.player.name,
				spawned,
			)
		}
	}
	for index := len(service.entities) - 1; index >= 0; index -= 1 {
		item := service.entities[index]
		if !replication_in_scope(service, item.object) || service.suppressed[item.object] {
			if item.object != nil && !item.object.destroyed {item.object.network_id = 0}
			delete(item.recipients)
			delete(item.samples)
			ordered_remove(&service.entities, index)
		}
	}
	service.tick += 1
}

// replication_send_extra_properties sends MeshId/TextureId and schema
// properties for an entity. Schema property values are hashed per connection
// and only re-sent when they actually change, so local client edits to a
// replicated object are not clobbered every tick.
replication_send_extra_properties :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	item: Replication_Entity,
) {
	if item.object == nil || item.object.destroyed {return}
	L := service.data_model.registry.vm_state.L
	if replication_builtin_property(item.object, "MeshId") {
		_ = replication_send_property(
			service,
			L,
			connection.peer,
			item.object,
			"MeshId",
		)
		_ = replication_send_property(
			service,
			L,
			connection.peer,
			item.object,
			"TextureId",
		)
	}
	schema := replication_schema(service, classes.Get_Class_Name(item.object))
	if schema == nil {return}
	hash := replication_schema_properties_hash(service, L, item.object, schema)
	if previous, ok := connection.property_hashes[item.id]; ok && previous == hash {return}
	all_sent := true
	for property in schema.properties {
		if property != "Name" && property != "Value" {
			if !replication_send_property(service, L, connection.peer, item.object, property) {
				all_sent = false
			}
		}
	}
	if all_sent {connection.property_hashes[item.id] = hash}
}

replication_schema_properties_hash :: proc(
	service: ^ReplicatorService,
	L: ^vm.State,
	object: ^classes.Object,
	schema: ^Replication_Schema,
) -> u64 {
	if service == nil || L == nil || object == nil || object.destroyed || schema == nil {return 0}
	scratch: [dynamic]u8
	defer delete(scratch)
	top := vm.StackTop(L)
	previous := vm.GetThreadSecurityCapabilities(L)
	vm.SetThreadSecurityCapabilities(L, vm.THREAD_SECURITY_ALL)
	defer vm.SetThreadSecurityCapabilities(L, previous)
	defer vm.SetStackTop(L, top)
	classes.Push_Object(L, object)
	for property in schema.properties {
		if property == "Name" || property == "Value" {continue}
		_ = vm.GetField(L, -1, property)
		if !replication_encode_value(L, -1, &scratch, 0) {
			vm.Pop(L)
			vm.Pop(L)
			return 0
		}
		vm.Pop(L)
	}
	hash: u64 = 14695981039346656037
	for byte in scratch {
		hash = (hash ~ u64(byte)) * 1099511628211
	}
	return hash
}
