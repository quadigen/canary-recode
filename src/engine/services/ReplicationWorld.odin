#+build !js
package services

import classes "../classes"
import datatypes "../datatypes"
import vm "../vm"
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
	for &schema in service.schemas {if schema.class_name == class_name {return &schema}}
	return nil
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
		class_name == "BoolValue" ||
		class_name == "IntValue" ||
		class_name == "NumberValue" ||
		class_name == "StringValue" ||
		class_name == "Vector3Value" ||
		class_name == "Color3Value" ||
		class_name == "CFrameValue" \
	)
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
	if part.anchored {return false}
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
	workspace := DataModel_Get_Service(service.data_model, "Workspace")
	storage := DataModel_Get_Service(service.data_model, "ReplicatedStorage")
	for current := object; current != nil; current = current.parent {
		if current == workspace || current == storage {return true}
		if current == &service.data_model.object {return false}
	}
	return false
}

replication_sync :: proc(service: ^ReplicatorService) {
	if service.mode != .Server || service.data_model == nil {return}
	workspace := DataModel_Get_Service(service.data_model, "Workspace")
	storage := DataModel_Get_Service(service.data_model, "ReplicatedStorage")
	replication_sync_tree(service, workspace)
	replication_sync_tree(service, storage)
	for &connection in service.peers {
		connection.bytes_this_tick = 0
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
			}
		}
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
		}
		for item in service.entities {
			if connection.known[item.id] == 0 ||
			   item.object == nil ||
			   item.object.destroyed {continue}
			if connection.initialized[item.id] &&
			   !replication_relevant(service, &connection, item.object) {continue}
			sent := false
			if classes.Is_A(item.object, "Part") {
				state_sent, state_hash, unchanged := replication_send_part_state(
					service,
					connection.peer,
					cast(^classes.Part)item.object,
					connection.state_hashes[item.id],
					connection.initialized[item.id],
				)
				if unchanged {
					service.unchanged_states_skipped += 1
					sent = true
				} else {
					sent = state_sent
					if sent {connection.state_hashes[item.id] = state_hash}
				}
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
			schema := replication_schema(service, classes.Get_Class_Name(item.object))
			if schema != nil {
				for property in schema.properties {
					if property != "Name" && property != "Value" {
						_ = replication_send_property(
							service,
							service.data_model.registry.vm_state.L,
							connection.peer,
							item.object,
							property,
						)
					}
				}
			}
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
