package services

import classes "../classes"
import datatypes "../datatypes"
import vm "../vm"
import "core:fmt"
import "core:sort"
import "core:strings"


replication_entity_id :: proc(service: ^ReplicatorService, object: ^classes.Object) -> u32 {
	if service == nil || object == nil {return 0}
	return service.entity_ids[object]
}

replication_entity_object :: proc(service: ^ReplicatorService, id: u32) -> ^classes.Object {
	if service == nil {return nil}
	entity := service.entity_by_id[id]
	if entity == nil {return nil}
	return entity.object
}

replication_entity_by_id :: proc(service: ^ReplicatorService, id: u32) -> ^Replication_Entity {
	if service == nil {return nil}
	return service.entity_by_id[id]
}

replication_entity :: proc(
	service: ^ReplicatorService,
	object: ^classes.Object,
) -> ^Replication_Entity {
	if service == nil || object == nil {return nil}
	return service.entity_by_id[service.entity_ids[object]]
}

replication_part_awaiting_transform :: proc(
	service: ^ReplicatorService,
	part: ^classes.Part,
) -> bool {
	if service == nil ||
	   service.mode != .Client ||
	   part == nil ||
	   part.network_id == 0 {return false}
	entity := replication_entity(service, &part.object)
	return entity != nil && !entity.has_transform
}

replication_entity_insert :: proc(service: ^ReplicatorService, entity: ^Replication_Entity) {
	append(&service.entity_list, entity)
	service.entity_by_id[entity.id] = entity
	if entity.object != nil {service.entity_ids[entity.object] = entity.id}
}


replication_forget_peer_entity :: proc(connection: ^Replication_Peer, id: u32) {
	delete_key(&connection.known, id)
	delete_key(&connection.initialized, id)
	delete_key(&connection.part_states, id)
	delete_key(&connection.property_hashes, id)
	delete_key(&connection.reliable_join_properties, u64(id) << 1)
	delete_key(&connection.reliable_join_properties, (u64(id) << 1) | 1)
	delete_key(&connection.extra_hashes, id)
	delete_key(&connection.acked_state, id)
	delete_key(&connection.acked_property, id)
	delete_key(&connection.acked_extra, id)
	delete_key(&connection.deformable, id)
	delete_key(&connection.script_sources, id)
	if connection.script_send.id == id {replication_clear_script_send(&connection.script_send)}
	delete_key(&connection.metadata_revisions, u64(id))
	remote_player_key := REPLICATION_METADATA_REMOTE_PLAYER_BASE + u64(id)
	delete_key(&connection.metadata_revisions, remote_player_key)
	if connection.metadata_send.key == u64(id) ||
	   connection.metadata_send.key == remote_player_key {
		replication_clear_metadata_send(&connection.metadata_send)
	}
}

replication_entity_new :: proc(
	service: ^ReplicatorService,
	id: u32,
	object: ^classes.Object,
) -> ^Replication_Entity {
	entity := new(Replication_Entity)
	entity.id = id
	entity.object = object
	replication_entity_insert(service, entity)
	return entity
}

replication_entity_remove :: proc(service: ^ReplicatorService, id: u32) -> bool {
	if service.script_receive.id == id {replication_clear_script_receive(&service.script_receive)}
	entity := service.entity_by_id[id]
	if entity == nil {return false}
	delete_key(&service.entity_by_id, id)
	if entity.object != nil {delete_key(&service.entity_ids, entity.object)}
	for candidate, index in service.entity_list {
		if candidate != entity {continue}
		ordered_remove(&service.entity_list, index)
		break
	}
	delete(entity.recipients)
	delete(entity.samples)
	free(entity)
	return true
}

replication_forget_destroyed :: proc(service: ^ReplicatorService, object: ^classes.Object) {
	if service == nil || object == nil {return}
	for &connection in service.peers {
		if connection.player != nil &&
		   &connection.player.object == object {connection.player = nil}
	}
	delete_key(&service.suppressed, object)
	id := service.entity_ids[object]
	if id == 0 {return}
	if service.mode == .Server {
		for &connection in service.peers {
			if connection.known[id] == 0 {continue}
			bytes: [dynamic]u8
			replication_put_u32(&bytes, id)
			_ = replication_send(service, connection.peer, 8, bytes[:])
			delete(bytes)
			replication_forget_peer_entity(&connection, id)
		}
	}
	_ = replication_entity_remove(service, id)
}

replication_register :: proc(service: ^ReplicatorService, object: ^classes.Object) -> u32 {
	if object == nil || object.destroyed || service.mode != .Server {return 0}
	delete_key(&service.suppressed, object)
	id := service.entity_ids[object]
	if id != 0 {return id}
	id = service.next_id
	service.next_id += 1
	entity := new(Replication_Entity)
	entity.id = id
	entity.object = object
	replication_entity_insert(service, entity)
	object.network_id = id
	return id
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
		include_imported = false,
	)
	schema: Replication_Schema
	schema.class_name = strings.clone(class_name)
	for property in properties {
		if class_name == "Attachment" && property == "CFrame" {continue}
		if class_name == "HingeConstraint" &&
		   (property == "Active" || property == "CurrentAngle") {
			continue
		}
		if class_name == "SpringConstraint" &&
		   (property == "Active" || property == "CurrentLength") {
			continue
		}
		if class_name == "SoftBody" && property == "LastError" {continue}
		switch property {
		case "Parent",
		     "Name",
		     "ReplicationMode",
		     "ReplicationGroup",
		     "AbsolutePosition",
		     "AbsoluteSize",
		     "TextBounds",
		     "SelectedText",
		     "LineCount",
		     "AbsoluteCellCount",
		     "AbsoluteCellSize",
		     "AbsoluteContentSize",
		     "PositionCallback",
		     "IsLoaded",
		     "ClassName",
		     "NetworkId",
		     "UniqueId",
		     "Capabilities",
		     "IsInSandbox":
			continue
		}
		duplicate := false
		for existing in schema.properties {
			if existing == property {duplicate = true; break}
		}
		if !duplicate {
			append(&schema.properties, strings.clone(property))
		}
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
		class_name == "UnionOperation" ||
		class_name == "NegateOperation" ||
		class_name == "IntersectOperation" ||
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
	return(
		object != nil &&
		((classes.Is_A_Class(object, &classes.Part_Class) && property == "CanTouch") ||
				(classes.Is_A_Class(object, &classes.PartOperation_Class) &&
						(property == "UsePartColor" ||
								property == "CanQuery" ||
								property == "CastShadow")) ||
				(classes.Is_A(object, "MeshPart") &&
						(property == "MeshId" ||
								property == "MeshIndex" ||
								property == "TextureId" ||
								property == "CollisionFidelity"))) \
	)
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

// PlayerGui containers are local to each runtime. Only their contents are
// network entities, with the owning Player used as the visibility boundary.
replication_player_gui_owner :: proc(
	service: ^ReplicatorService,
	object: ^classes.Object,
) -> ^Player {
	if service == nil ||
	   service.data_model == nil ||
	   object == nil ||
	   object.destroyed ||
	   object.class != &PlayerGui_Class {return nil}
	player := object.parent
	if player == nil || player.destroyed || player.class != &Player_Class {return nil}
	players := player.parent
	if players == nil ||
	   players.destroyed ||
	   players.class != &Players_Class ||
	   players.parent != &service.data_model.object {return nil}
	return cast(^Player)player
}

replication_uses_server_player_gui :: proc(service: ^ReplicatorService) -> bool {
	return(
		service != nil &&
		service.mode == .Client &&
		service.remote != nil &&
		(service.client_capabilities &
				service.server_capabilities &
				Replication_Capability_Player_Gui) !=
			0 \
	)
}

replication_visible :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	object: ^classes.Object,
) -> bool {
	allowed, owner := replication_scope(service, object)
	if !allowed || connection.player == nil {return false}
	if owner != nil &&
	   (owner != connection.player ||
			   (service.server_capabilities &
					   connection.client_capabilities &
					   Replication_Capability_Player_Gui) ==
				   0) {
		return false
	}
	for current := object;
	    current != nil && !classes.Is_A(current, "Service");
	    current = current.parent {
		if !current.can_replicate {return false}
		switch current.replication_mode {
		case .Never, .ServerOnly:
			return false
		case .OwnerOnly:
			if current.class != &PlayerGui_Class {
				entity := replication_entity(service, current)
				if entity == nil || entity.owner_id != connection.player.user_id {return false}
			}
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


replication_focus :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
) -> (
	x, y, z: f32,
	ok: bool,
) {
	if connection.player == nil {return 0, 0, 0, false}
	part := replication_peer_focus_part(service, connection.player.user_id)
	if part != nil {
		connection.focus_x = part.cframe.x
		connection.focus_y = part.cframe.y
		connection.focus_z = part.cframe.z
		connection.focus_ok = true
		return connection.focus_x, connection.focus_y, connection.focus_z, true
	}

	return connection.focus_x, connection.focus_y, connection.focus_z, connection.focus_ok
}


replication_lod_tier :: proc(
	service: ^ReplicatorService,
	fx, fy, fz: f32,
	part: ^classes.Part,
) -> (
	far: bool,
) {
	if service.lod_near_fraction >= 1 {return false}
	if service.relevancy_distance <= 0 {return false}
	near_sq := service.relevancy_distance * service.relevancy_distance * service.lod_near_fraction
	return replication_distance_sq(fx, fy, fz, part) > near_sq
}


replication_lod_due :: proc(
	service: ^ReplicatorService,
	fx, fy, fz: f32,
	part: ^classes.Part,
) -> bool {
	if !replication_lod_tier(service, fx, fy, fz, part) {return true}
	every := service.lod_far_interval
	if every < 2 {return true}
	return (service.tick % u32(every)) == 0
}

replication_peer_focus_part :: proc(service: ^ReplicatorService, user_id: u32) -> ^classes.Part {
	for entity in service.entity_list {
		if entity.owner_id == user_id &&
		   entity.object != nil &&
		   !entity.object.destroyed &&
		   classes.Is_A(entity.object, "Part") {
			return cast(^classes.Part)entity.object
		}
	}
	return nil
}

replication_distance_sq :: proc(fx, fy, fz: f32, part: ^classes.Part) -> f32 {
	dx := part.cframe.x - fx
	dy := part.cframe.y - fy
	dz := part.cframe.z - fz
	return dx * dx + dy * dy + dz * dz
}

replication_relevant :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	object: ^classes.Object,
) -> bool {
	fx, fy, fz, ok := replication_focus(service, connection)
	return replication_relevant_to(service, connection, object, fx, fy, fz, ok)
}


replication_relevant_to :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	object: ^classes.Object,
	fx, fy, fz: f32,
	has_focus: bool,
) -> bool {
	if object == nil {return false}
	// Parts in an owned PlayerGui belong to its viewports.
	if _, owner := replication_scope(service, object); owner != nil {return true}
	if !has_focus {return false}
	distance_sq := service.relevancy_distance * service.relevancy_distance
	// An entity cannot arrive before its ancestors, including streamed-out parts.
	for current := object;
	    current != nil && !classes.Is_A(current, "Service");
	    current = current.parent {
		if classes.Is_A(current, "Part") &&
		   replication_distance_sq(fx, fy, fz, cast(^classes.Part)current) >
			   distance_sq {return false}
	}
	return true
}


replication_visible_to :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	object: ^classes.Object,
	fx, fy, fz: f32,
	has_focus: bool,
) -> bool {
	if !replication_relevant_to(service, connection, object, fx, fy, fz, has_focus) {
		return false
	}
	for current := object;
	    current != nil && !classes.Is_A(current, "Service");
	    current = current.parent {
		if service.suppressed[current] {return false}
	}
	return replication_visible(service, connection, object)
}

replication_send_spawn :: proc(
	service: ^ReplicatorService,
	peer: ^Replication_Transport_Peer,
	object: ^classes.Object,
) -> bool {
	id := replication_entity_id(service, object)
	if id == 0 {return false}
	gui_owner := replication_player_gui_owner(service, object.parent)
	parent_id := u32(0)
	if gui_owner == nil {parent_id = replication_entity_id(service, object.parent)}
	bytes: [dynamic]u8
	defer delete(bytes)
	replication_put_u32(&bytes, id)
	replication_put_u32(&bytes, parent_id)
	replication_put_string(&bytes, classes.Get_Class_Name(object))
	replication_put_string(&bytes, object.name)
	root_name := ""
	owner_user_id: u32
	if parent_id == 0 && object.parent != nil {
		if gui_owner != nil {
			root_name = "PlayerGui"
			owner_user_id = gui_owner.user_id
		} else {
			root_name = object.parent.name
		}
	}
	replication_put_string(&bytes, root_name)
	if classes.Is_A(object, "CharacterModel") && owner_user_id == 0 {
		owner_user_id = (cast(^classes.CharacterModel)object).owner_user_id
	}
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
	linear := classes.Part_Linear_Velocity(service.signal_registry, &part.object)
	angular := classes.Part_Angular_Velocity(service.signal_registry, &part.object)
	values := [18]f32 {
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
		linear.x,
		linear.y,
		linear.z,
		angular.x,
		angular.y,
		angular.z,
	}
	resting := linear == (datatypes.Vector3{}) && angular == (datatypes.Vector3{})
	hash := u64(14695981039346656037)
	if resting {
		for value in values[:12] {
			hash = (hash ~ u64(transmute(u32)value)) * 1099511628211
		}
		// Refresh unchanged resting poses twice a second in case an upload was lost.
		if entity.owned_rest_upload_tick != 0 &&
		   service.tick - entity.owned_rest_upload_tick < 15 &&
		   entity.owned_rest_upload_hash == hash {return true}
	} else {
		entity.owned_rest_upload_tick = 0
	}

	bytes: [dynamic]u8
	defer delete(bytes)
	replication_put_u32(&bytes, entity.id)
	replication_put_u32(&bytes, service.tick)
	for value in values {replication_put_f32(&bytes, value)}
	if !replication_send(
		service,
		service.remote,
		Replication_Kind_Owned_State,
		bytes[:],
		false,
	) {return false}
	if resting {
		entity.owned_rest_upload_tick = service.tick
		entity.owned_rest_upload_hash = hash
	}
	return true
}


replication_peer_snapshot_tick :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
) -> u32 {
	// Changing the send cadence must not change the clock used for packet ordering.
	if connection.snapshot_clock_rate <= 0 {return service.tick}
	return u32(f64(service.clock) * f64(connection.snapshot_clock_rate))
}

replication_send_part_state :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	part: ^classes.Part,
	tick: u32,
	suppress: bool = false,
	confirmed_token: u32 = 0,
	reliable: bool = false,
	repeat_acknowledged: bool = false,
) -> (
	bool,
	u32,
	bool,
) {
	bytes: [dynamic]u8
	defer delete(bytes)
	append(&bytes, 1)
	replication_put_u32(&bytes, replication_entity_id(service, &part.object))
	replication_put_u32(&bytes, tick)
	replication_put_string(&bytes, part.name)
	replication_put_cframe(&bytes, part.cframe)
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


	hash: u64 = 14695981039346656037
	for byte in bytes[9:] {
		hash = (hash ~ u64(byte)) * 1099511628211
	}
	token := u32(hash & 0xFFFFFFFF)
	repeating := suppress && token == confirmed_token
	if repeating && !repeat_acknowledged {return true, token, true}
	replication_put_u32(&bytes, token)
	return replication_send(service, connection.peer, 5, bytes[:], reliable || repeating),
		token,
		false
}


replication_frame_finite :: proc(frame: datatypes.CFrame) -> bool {
	values := [12]f32 {
		frame.x,
		frame.y,
		frame.z,
		frame.r00,
		frame.r01,
		frame.r02,
		frame.r10,
		frame.r11,
		frame.r12,
		frame.r20,
		frame.r21,
		frame.r22,
	}
	for value in values {
		if !(value > -1e30) || !(value < 1e30) {return false}
	}
	return true
}

replication_vector3_finite :: proc(value: datatypes.Vector3) -> bool {
	return(
		(value.x > -1e30) &&
		(value.x < 1e30) &&
		(value.y > -1e30) &&
		(value.y < 1e30) &&
		(value.z > -1e30) &&
		(value.z < 1e30) \
	)
}


replication_frame_rotation_valid :: proc(frame: datatypes.CFrame) -> bool {


	tolerance: f32 = 1e-3
	rows := [3][3]f32 {
		{frame.r00, frame.r01, frame.r02},
		{frame.r10, frame.r11, frame.r12},
		{frame.r20, frame.r21, frame.r22},
	}
	for row in rows {
		length_sq := row[0] * row[0] + row[1] * row[1] + row[2] * row[2]
		if abs(length_sq - 1) > tolerance {return false}
	}
	for i in 0 ..< 3 {
		for j in i + 1 ..< 3 {
			dot := rows[i][0] * rows[j][0] + rows[i][1] * rows[j][1] + rows[i][2] * rows[j][2]
			if abs(dot) > tolerance {return false}
		}
	}


	determinant :=
		rows[0][0] * (rows[1][1] * rows[2][2] - rows[1][2] * rows[2][1]) -
		rows[0][1] * (rows[1][0] * rows[2][2] - rows[1][2] * rows[2][0]) +
		rows[0][2] * (rows[1][0] * rows[2][1] - rows[1][1] * rows[2][0])
	return determinant > 0
}

replication_send_character_ack :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	object: ^classes.Object,
) {
	if service == nil ||
	   connection == nil ||
	   connection.player == nil ||
	   object == nil ||
	   object.parent == nil ||
	   !classes.Is_A(object.parent, "CharacterModel") ||
	   object.name != "HumanoidRootPart" {return}
	entity := replication_entity(service, object)
	if entity == nil {return}
	owner_id := (cast(^classes.CharacterModel)object.parent).owner_user_id
	if owner_id == 0 || owner_id != connection.player.user_id {return}
	players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
	if players == nil {return}
	ack: u32
	found := false
	for child in players.children {
		if child == nil || child.destroyed || !classes.Is_A(child, "Player") {continue}
		player := cast(^Player)child
		if player.user_id != owner_id {continue}
		ack = player.input_sequence
		found = true
		break
	}
	if !found || connection.last_ack_sent == ack {return}
	bytes: [dynamic]u8
	defer delete(bytes)
	replication_put_u32(&bytes, entity.id)
	replication_put_u32(&bytes, ack)
	if replication_send(service, connection.peer, 14, bytes[:], false) {
		connection.last_ack_sent = ack
	}
}


replication_encode_property_value :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	property: string,
	bytes: ^[dynamic]u8,
	connection: ^Replication_Peer = nil,
) -> bool {
	if L == nil || object == nil || object.destroyed {return false}
	top := vm.StackTop(L)
	previous := vm.GetThreadSecurityCapabilities(L)
	vm.SetThreadSecurityCapabilities(L, vm.THREAD_SECURITY_ALL)
	defer vm.SetThreadSecurityCapabilities(L, previous)
	defer vm.SetStackTop(L, top)
	classes.Push_Object(L, object)
	_ = vm.GetField(L, -1, property)
	if object.class == &classes.ParticleEmitter_Class {
		if binding := vm.UserdataBindingOf(L, -1);
		   binding != nil && binding.name == "NumberRange" {
			value := cast(^datatypes.NumberRange)vm.UserdataValue(L, -1)
			append(bytes, 19)
			replication_put_f32(bytes, value.Min)
			replication_put_f32(bytes, value.Max)
			return true
		}
	}
	return replication_encode_value(L, -1, bytes, 0, connection)
}


replication_property_stream_builtin: u8 = 0
replication_property_stream_extra: u8 = 1


replication_property_batch_limit: u8 = 63

// A packet header, a script or metadata chunk header, and one payload byte.
REPLICATION_MIN_INITIAL_FRAME_BYTES :: 5 + REPLICATION_SCRIPT_SOURCE_HEADER + 1


replication_remaining_budget :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	kind: u8,
) -> int {
	if service == nil || connection == nil {return -1}


	if !replication_budgeted(service, kind) {return -1}
	return(
		int(replication_peer_bandwidth_budget(service, connection)) -
		int(connection.bytes_this_tick) \
	)
}


replication_send_property_batch :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	item: ^Replication_Entity,
	names: []string,
	stream: u8,
	reliable: bool,
	skip_if_confirmed: bool,
	confirmed: u32,
) -> (
	bool,
	u32,
) {
	if service == nil || connection == nil || item == nil {return false, 0}
	if item.object == nil || item.object.destroyed {return false, 0}
	if len(names) == 0 {return true, confirmed}
	L := service.data_model.registry.vm_state.L
	if L == nil {return false, 0}

	packet: [dynamic]u8
	defer delete(packet)
	value: [dynamic]u8
	defer delete(value)
	ends: [dynamic]int
	defer delete(ends)
	hash: u64 = 14695981039346656037
	tick := replication_peer_snapshot_tick(service, connection)
	for name in names {
		clear(&value)
		if !replication_encode_property_value(L, item.object, name, &value) {continue}
		for byte in value {hash = (hash ~ u64(byte)) * 1099511628211}
		append(&packet, 2)
		replication_put_u32(&packet, item.id)
		replication_put_u32(&packet, tick)
		replication_put_string(&packet, name)
		append(&packet, ..value[:])
		append(&packet, stream, 0, 0, 0, 0, 0, 0)
		append(&ends, len(packet))
	}
	if len(ends) == 0 {return true, confirmed}
	batch_token := u32(hash & 0xFFFFFFFF)
	key := (u64(item.id) << 1) | u64(stream)
	join_token, queued := connection.reliable_join_properties[key]
	if queued && confirmed == join_token {delete_key(&connection.reliable_join_properties, key)}
	if skip_if_confirmed && (batch_token == confirmed || (queued && batch_token == join_token)) {
		return true, batch_token
	}

	remaining := replication_remaining_budget(service, connection, 5)
	if remaining >= 0 && len(packet) + 5 * len(ends) > remaining {return false, confirmed}

	wide := len(ends) > int(replication_property_batch_limit)
	// A different update supersedes the reliably queued startup value.
	if queued {delete_key(&connection.reliable_join_properties, key)}
	all_sent := true
	start := 0
	for end, index in ends {
		metadata := packet[end - 6:end]
		for byte in 0 ..< 4 {metadata[byte] = u8(batch_token >> u32(byte * 8))}
		metadata[4] = wide ? 0 : u8(index)
		metadata[5] = wide ? 1 : u8(len(ends))
		if !replication_send(service, connection.peer, 5, packet[start:end], reliable || wide) {
			all_sent = false
		}
		start = end
	}
	if all_sent && !wide && reliable && connection.join_batch_enabled {
		connection.reliable_join_properties[key] = batch_token
	}
	return all_sent, wide ? confirmed : batch_token
}


replication_builtin_property_names :: proc(item: ^Replication_Entity) -> [dynamic]string {
	names: [dynamic]string
	if item == nil || item.object == nil || item.object.destroyed {return names}
	if replication_builtin_property(item.object, "Name") {append(&names, "Name")}
	if classes.Is_A(item.object, "ValueBase") {append(&names, "Value")}
	return names
}

replication_root_service :: proc(service: ^ReplicatorService, object: ^classes.Object) -> bool {
	return(
		service != nil &&
		service.data_model != nil &&
		object != nil &&
		classes.Is_A(object, "Service") &&
		object.parent == &service.data_model.object &&
		replication_root_allowed(object.name) \
	)
}

replication_sync_tree :: proc(service: ^ReplicatorService, object: ^classes.Object) {
	if object == nil || object.destroyed || object == &service.object {return}
	if !replication_root_service(service, object) &&
	   replication_player_gui_owner(service, object) == nil &&
	   object != &service.data_model.object &&
	   (replication_builtin_class(classes.Get_Class_Name(object)) ||
			   replication_schema(service, classes.Get_Class_Name(object)) != nil) &&
	   !service.suppressed[object] {
		_ = replication_register(service, object)
	}
	for child in object.children {replication_sync_tree(service, child)}
}

replication_scope :: proc(
	service: ^ReplicatorService,
	object: ^classes.Object,
) -> (
	bool,
	^Player,
) {
	if object == nil || object.destroyed {return false, nil}
	for current := object; current != nil; current = current.parent {
		if owner := replication_player_gui_owner(service, current); owner != nil {
			return current != object, owner
		}
		if current.parent == &service.data_model.object &&
		   classes.Is_A(current, "Service") &&
		   replication_root_allowed(current.name) {return true, nil}
		if current == &service.data_model.object {break}
	}
	return false, nil
}

replication_in_scope :: proc(service: ^ReplicatorService, object: ^classes.Object) -> bool {
	allowed, _ := replication_scope(service, object)
	return allowed
}


replication_spawn_part :: proc(service: ^ReplicatorService) -> ^classes.Part {
	if service == nil || service.data_model == nil {return nil}
	workspace := DataModel_Get_Service(service.data_model, "Workspace")
	if workspace == nil {return nil}
	for child in workspace.children {
		if child != nil &&
		   !child.destroyed &&
		   child.name == "Spawn" &&
		   classes.Is_A(child, "Part") {
			return cast(^classes.Part)child
		}
	}
	return nil
}


replication_spawn_entity :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	object: ^classes.Object,
	focus_x, focus_y, focus_z: f32,
	has_focus: bool,
) -> bool {
	if object == nil || object.destroyed {return false}
	if !replication_visible_to(
		   service,
		   connection,
		   object,
		   focus_x,
		   focus_y,
		   focus_z,
		   has_focus,
	   ) ||
	   service.suppressed[object] {
		return false
	}
	item := replication_entity(service, object)
	if item == nil {return false}
	parent_key: u64
	if replication_player_gui_owner(service, object.parent) != nil {
		parent_key = u64(max(u32)) + 2
	} else {
		parent_id := replication_entity_id(service, object.parent)
		if parent_id != 0 && connection.known[parent_id] == 0 {return false}
		parent_key = u64(parent_id) + 1
	}
	if connection.known[item.id] == parent_key {return false}
	if connection.known[item.id] != 0 {
		bytes: [dynamic]u8
		replication_put_u32(&bytes, item.id)
		_ = replication_send(service, connection.peer, 8, bytes[:])
		delete(bytes)
	}
	if !replication_send_operation_mesh(service, connection, object) ||
	   !replication_send_spawn(service, connection.peer, object) {
		return false
	}
	replication_forget_peer_entity(connection, item.id)
	connection.known[item.id] = parent_key
	return true
}


replication_spawn_tree :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	root: ^classes.Object,
	focus_x, focus_y, focus_z: f32,
	has_focus: bool,
) -> int {
	if service == nil || connection == nil || root == nil || root.destroyed {return 0}
	spawned := 0
	if replication_spawn_entity(service, connection, root, focus_x, focus_y, focus_z, has_focus) {
		spawned += 1
	}
	for child in root.children {
		spawned += replication_spawn_tree(
			service,
			connection,
			child,
			focus_x,
			focus_y,
			focus_z,
			has_focus,
		)
	}
	return spawned
}


replication_spawn_tree_with_ancestry :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	root: ^classes.Object,
	focus_x, focus_y, focus_z: f32,
	has_focus: bool,
) -> int {
	if service == nil || connection == nil || root == nil || root.destroyed {return 0}
	spawned := 0
	chain: [dynamic]^classes.Object
	defer delete(chain)
	for object := root.parent; object != nil; object = object.parent {
		append(&chain, object)
		if replication_root_service(service, object) {break}
	}
	for index := len(chain) - 1; index >= 0; index -= 1 {
		if replication_spawn_entity(
			service,
			connection,
			chain[index],
			focus_x,
			focus_y,
			focus_z,
			has_focus,
		) {spawned += 1}
	}
	return(
		spawned +
		replication_spawn_tree(service, connection, root, focus_x, focus_y, focus_z, has_focus) \
	)
}


replication_initialise_entity :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	item: ^Replication_Entity,
) -> bool {
	if service == nil ||
	   connection == nil ||
	   item == nil ||
	   item.object == nil ||
	   item.object.destroyed ||
	   connection.known[item.id] == 0 {return false}
	if connection.initialized[item.id] {return true}
	if !replication_send_entity_metadata(service, connection, item, initial = true) {return false}
	script := replication_peer_script(service, connection, item.object)
	if script != nil {
		if connection.script_send.id == item.id {
			sent := replication_send_script_source(service, connection, item, script)
			if sent {connection.initialized[item.id] = true}
			return sent
		}
		if connection.script_send.id != 0 {return false}
	}
	sent := false
	if classes.Is_A(item.object, "Part") {
		tick := replication_peer_snapshot_tick(service, connection)
		state_sent, state_token, _ := replication_send_part_state(
			service,
			connection,
			cast(^classes.Part)item.object,
			tick,
			false,
			0,
			true,
		)
		sent = state_sent
		if sent {
			connection.part_states[item.id] = {
				token     = state_token,
				tick      = tick,
				rest_sent = true,
			}
		}
	} else {
		names := replication_builtin_property_names(item)
		defer delete(names)
		property_sent, property_token := replication_send_property_batch(
			service,
			connection,
			item,
			names[:],
			replication_property_stream_builtin,
			true,
			false,
			0,
		)
		sent = property_sent
		connection.property_hashes[item.id] = property_token
	}
	// Queue every initial property reliably before announcing a complete scene.
	extra_sent := replication_send_extra_properties(service, connection, item, true)
	sent = sent && extra_sent
	if sent && script != nil {
		sent = replication_send_script_source(service, connection, item, script)
	}
	if sent {connection.initialized[item.id] = true}
	replication_send_character_ack(service, connection, item.object)
	return sent
}

replication_initialise_tree :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	root: ^classes.Object,
) {
	if service == nil || connection == nil || root == nil || root.destroyed {return}
	if item := replication_entity(service, root); item != nil {
		_ = replication_initialise_entity(service, connection, item)
	}
	for child in root.children {replication_initialise_tree(service, connection, child)}
}


replication_peer_scene_complete :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	focus_x, focus_y, focus_z: f32,
	has_focus: bool,
) -> bool {
	if service == nil || connection == nil {return false}
	for item in service.entity_list {
		if item == nil || item.object == nil || item.object.destroyed {continue}
		if !replication_visible_to(
			service,
			connection,
			item.object,
			focus_x,
			focus_y,
			focus_z,
			has_focus,
		) {
			continue
		}
		if connection.known[item.id] == 0 || !connection.initialized[item.id] {return false}
	}
	return true
}


replication_terrain_complete :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
) -> bool {
	if service == nil || connection == nil {return true}
	if (connection.client_capabilities & Replication_Capability_Terrain) == 0 {return true}
	terrain_object := DataModel_Get_Service(service.data_model, "Terrain")
	if terrain_object == nil {return true}
	return connection.terrain_initial_sent
}


replication_peer_support_ready :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
) -> bool {
	if service == nil ||
	   connection == nil ||
	   connection.player == nil ||
	   service.data_model == nil {return true}
	character := connection.player.character
	if character == nil || character.destroyed {return true}
	root := classes.CharacterModel_Root(character)
	if root == nil {return true}
	workspace := DataModel_Get_Service(service.data_model, "Workspace")
	physics := cast(^Physics)DataModel_Get_Service(service.data_model, "Physics")
	if workspace == nil || physics == nil || !physics.initialized {return true}
	params := datatypes.RaycastParams{}
	params.RespectCanCollide = true
	params.ExcludeFilterSet = true
	append(
		&params.ExcludeInstances,
		datatypes.Raycast_Instance_Reference{object = &character.object},
	)
	defer delete(params.ExcludeInstances)
	origin := datatypes.Vector3{root.cframe.x, root.cframe.y, root.cframe.z}
	result, hit := Physics_Raycast(
		physics,
		workspace,
		origin,
		datatypes.Vector3{0, -512, 0},
		&params,
	)
	if !hit {return true}

	support := cast(^classes.Part)result.ObjectRef
	if support == nil {return true}
	item := replication_entity(service, &support.object)


	if item == nil {return true}
	return connection.initialized[item.id]
}


replication_peer_spawn_ready :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	spawn_part: ^classes.Part,
) -> bool {
	if service == nil || connection == nil || connection.player == nil {return false}
	character := connection.player.character
	if character == nil || character.destroyed {return false}
	for child in character.children {
		if child == nil || child.destroyed || !classes.Is_A(child, "Part") {continue}
		item := replication_entity(service, child)
		if item == nil || !connection.initialized[item.id] {return false}
	}
	if spawn_part != nil {
		item := replication_entity(service, &spawn_part.object)
		if item == nil || !connection.initialized[item.id] {return false}
	}
	if !replication_peer_support_ready(service, connection) {return false}
	return replication_terrain_complete(service, connection)
}


REPLICATION_DROP_PRESSURE_RECOVER_BELOW: f32 = 0.02

replication_sync :: proc(service: ^ReplicatorService) {


	service.terrain_sync_tick += 1
	service.terrain_sync_due = service.terrain_sync_tick % 2 == 0
	if service.mode != .Server || service.data_model == nil {return}


	service.tick = u32(f64(service.clock) * f64(service.snapshot_rate))
	for root_name in REPLICATION_ROOT_NAMES {
		replication_sync_tree(service, DataModel_Get_Service(service.data_model, root_name))
	}
	for &connection in service.peers {
		if connection.player == nil || connection.player.destroyed {continue}
		gui := classes.Find_First_Child_Of_Class(&connection.player.object, "PlayerGui")
		replication_sync_tree(service, gui)
	}


	drops := service.drops_window
	service.drops_window = 0


	severity := f32(0)
	if drops > 0 {severity = min(1, f32(drops) / 32)}
	service.drop_pressure += 0.1 * (severity - service.drop_pressure)
	if service.drop_pressure > REPLICATION_DROP_PRESSURE_RECOVER_BELOW {


		service.adaptive_scale = max(
			service.adaptive_scale * (1 - 0.25 * severity),
			service.adaptive_min_scale,
		)
	} else {
		service.adaptive_scale = min(service.adaptive_scale + 0.05, 1)
	}
	service.bandwidth_budget = u32(f32(service.base_bandwidth_budget) * service.adaptive_scale)


	for item in service.entity_list {
		if item.object == nil || item.object.destroyed || !classes.Is_A(item.object, "Part") {
			item.velocity_sq = 0
			item.velocity_seeded = false
			continue
		}
		part := cast(^classes.Part)item.object
		current := datatypes.Vector3{part.cframe.x, part.cframe.y, part.cframe.z}
		if part.anchored || !item.velocity_seeded {
			item.velocity_sq = 0
			item.velocity_seeded = !part.anchored
			item.velocity_origin = current
			continue
		}
		dx := current.x - item.velocity_origin.x
		dy := current.y - item.velocity_origin.y
		dz := current.z - item.velocity_origin.z
		item.velocity_sq = dx * dx + dy * dy + dz * dz
		item.velocity_origin = current
	}


	// A new owner must see the same gravity before it starts simulating.
	replication_send_gravity_updates(service)
	if service.auto_ownership_enabled &&
	   service.clock - service.auto_ownership_clock >= REPLICATION_AUTO_OWNERSHIP_INTERVAL {
		service.auto_ownership_clock = service.clock
		replication_auto_ownership_step(service)
	}

	for &connection in service.peers {
		connection.bytes_this_tick = 0


		if !connection.handshake_complete {continue}
		if !replication_flush_join_batch(service, &connection) {continue}
		connection.join_batch_enabled =
			replication_initial_snapshot_pending(&connection) &&
			(connection.client_capabilities &
					service.server_capabilities &
					Replication_Capability_Join_Batch) !=
				0

		root_metadata_ready := replication_send_root_metadata(service, &connection)

		if service.mode == .Server && service.terrain_sync_due {
			replication_send_terrain_delta(service, &connection)
		}
		if service.mode == .Server {
			replication_send_deformables(service, &connection)
		}


		focus_x, focus_y, focus_z, has_focus := replication_focus(service, &connection)


		spawned := 0


		if connection.player != nil && connection.player.character != nil {
			spawned += replication_spawn_tree_with_ancestry(
				service,
				&connection,
				&connection.player.character.object,
				focus_x,
				focus_y,
				focus_z,
				has_focus,
			)
		}
		spawn_part := replication_spawn_part(service)
		if spawn_part != nil {
			spawned += replication_spawn_tree_with_ancestry(
				service,
				&connection,
				&spawn_part.object,
				focus_x,
				focus_y,
				focus_z,
				has_focus,
			)
		}


		if connection.player != nil && connection.player.character != nil {
			replication_initialise_tree(service, &connection, &connection.player.character.object)
		}
		if spawn_part !=
		   nil {replication_initialise_tree(service, &connection, &spawn_part.object)}


		if !connection.scene_ready_sent &&
		   (connection.client_capabilities & Replication_Capability_Scene_Ready) != 0 &&
		   replication_peer_spawn_ready(service, &connection, spawn_part) {
			connection.scene_ready_sent = replication_send(
				service,
				connection.peer,
				Replication_Kind_Scene_Ready,
				nil,
				true,
			)
		}
		for item in service.entity_list {
			if replication_spawn_entity(
				service,
				&connection,
				item.object,
				focus_x,
				focus_y,
				focus_z,
				has_focus,
			) {
				spawned += 1
			}
		}


		for item in service.entity_list {
			if connection.known[item.id] == 0 {continue}


			if replication_visible_to(
				   service,
				   &connection,
				   item.object,
				   focus_x,
				   focus_y,
				   focus_z,
				   has_focus,
			   ) &&
			   !service.suppressed[item.object] {continue}
			bytes: [dynamic]u8
			replication_put_u32(&bytes, item.id)
			_ = replication_send(service, connection.peer, 8, bytes[:])
			delete(bytes)
			replication_forget_peer_entity(&connection, item.id)
		}


		entity_total := len(service.entity_list)
		init_start := 0
		if entity_total > 0 {
			init_start = int(connection.init_cursor % u32(entity_total))
			connection.init_cursor += 1
		}
		fast_join :=
			!service.bandwidth_budget_configured &&
			replication_initial_snapshot_pending(&connection)
		// Resume in-flight reliable chunks before other objects can use the budget.
		if fast_join {
			if item := replication_entity_by_id(service, u32(connection.metadata_send.key));
			   item != nil && u64(item.id) == connection.metadata_send.key {
				_ = replication_initialise_entity(service, &connection, item)
			}
			if item := replication_entity_by_id(service, connection.script_send.id); item != nil {
				_ = replication_initialise_entity(service, &connection, item)
			}
		}
		for offset in 0 ..< entity_total {
			index := (init_start + offset) % entity_total
			if fast_join &&
			   replication_remaining_budget(service, &connection, 5) <
				   REPLICATION_MIN_INITIAL_FRAME_BYTES {
				connection.init_cursor = u32(index)
				break
			}
			item := service.entity_list[index]
			if connection.known[item.id] == 0 ||
			   item.object == nil ||
			   item.object.destroyed {continue}
			if connection.initialized[item.id] {continue}

			_ = replication_initialise_entity(service, &connection, item)
		}

		connection.join_batch_enabled = false
		if !replication_flush_join_batch(service, &connection) {continue}

		if !connection.finished_replicating_sent &&
		   (connection.client_capabilities & Replication_Capability_Finished_Replicating) != 0 &&
		   root_metadata_ready &&
		   replication_peer_scene_complete(
			   service,
			   &connection,
			   focus_x,
			   focus_y,
			   focus_z,
			   has_focus,
		   ) &&
		   replication_terrain_complete(service, &connection) {
			connection.finished_replicating_sent = replication_send(
				service,
				connection.peer,
				Replication_Kind_Finished_Replicating,
				nil,
				true,
			)
			if connection.finished_replicating_sent {
				delete(connection.join_batch)
				connection.join_batch = nil
			}
		}

		if spawned > 0 && connection.player != nil {
			fmt.printf(
				"[Replication] sent initial snapshot to %s (%d instances)\n",
				connection.player.name,
				spawned,
			)
		}
		// A full startup budget leaves no room for an update packet. Avoid
		// rescanning every initialized object to attempt sends that cannot fit.
		if fast_join &&
		   replication_initial_snapshot_pending(&connection) &&
		   replication_remaining_budget(service, &connection, 5) <
			   REPLICATION_MIN_INITIAL_FRAME_BYTES {continue}

		sorted: [dynamic]^Replication_Entity
		defer delete(sorted)
		for item in service.entity_list {
			if connection.known[item.id] == 0 ||
			   item.object == nil ||
			   item.object.destroyed {continue}
			if !connection.initialized[item.id] {continue}
			if !replication_relevant_to(
				service,
				&connection,
				item.object,
				focus_x,
				focus_y,
				focus_z,
				has_focus,
			) {continue}
			append(&sorted, item)
		}


		sort.quick_sort_proc(sorted[:], replication_velocity_desc)


		total := len(sorted)
		start := 0
		if total > 0 {
			start = int(connection.bandwidth_cursor % u32(total))
			connection.bandwidth_cursor += 1
		}
		for offset in 0 ..< total {
			item := sorted[(start + offset) % total]

			_ = replication_send_entity_metadata(service, &connection, item)

			if classes.Is_A(item.object, "Part") &&
			   has_focus &&
			   !replication_lod_due(
					   service,
					   focus_x,
					   focus_y,
					   focus_z,
					   cast(^classes.Part)item.object,
				   ) {
				continue
			}


			if classes.Is_A(item.object, "Part") {
				confirmed := connection.acked_state[item.id]
				last := connection.part_states[item.id]
				settled := last.token == confirmed
				tick := replication_peer_snapshot_tick(service, &connection)
				// A second sample of the final pose tells observers its inferred velocity is zero.
				repeat_acknowledged := !last.rest_sent && tick != last.tick
				state_sent, state_token, suppressed := replication_send_part_state(
					service,
					&connection,
					cast(^classes.Part)item.object,
					tick,
					settled,
					confirmed,
					false,
					repeat_acknowledged,
				)
				if suppressed {
					service.unchanged_states_skipped += 1
				} else if state_sent {
					connection.part_states[item.id] = {
						token     = state_token,
						tick      = tick,
						rest_sent = settled && state_token == confirmed,
					}
				}
			} else {
				names := replication_builtin_property_names(item)
				defer delete(names)
				confirmed := connection.acked_property[item.id]
				property_sent, property_token := replication_send_property_batch(
					service,
					&connection,
					item,
					names[:],
					replication_property_stream_builtin,
					false,
					true,
					confirmed,
				)
				if property_token == confirmed && property_sent {
					service.unchanged_states_skipped += 1
				}
				if property_sent {
					connection.property_hashes[item.id] = property_token
				} else if connection.property_hashes[item.id] == confirmed {
					connection.property_hashes[item.id] = 0
				}
			}
			replication_send_extra_properties(service, &connection, item, false)
			if script := replication_peer_script(service, &connection, item.object);
			   script != nil {
				_ = replication_send_script_source(service, &connection, item, script)
			}
			replication_send_character_ack(service, &connection, item.object)
		}

	}
	if service.mode == .Server &&
	   service.terrain_sync_due {replication_trim_terrain_history(service)}
	for index := len(service.entity_list) - 1; index >= 0; index -= 1 {
		item := service.entity_list[index]
		if !replication_in_scope(service, item.object) || service.suppressed[item.object] {
			if item.object != nil && !item.object.destroyed {item.object.network_id = 0}
			_ = replication_entity_remove(service, item.id)
		}
	}
}


replication_velocity_desc :: proc(a: ^Replication_Entity, b: ^Replication_Entity) -> int {
	if a == nil {return b == nil ? 0 : 1}
	if b == nil {return -1}
	if a.velocity_sq > b.velocity_sq {return -1}
	if a.velocity_sq < b.velocity_sq {return 1}

	if a.id < b.id {return -1}
	if a.id > b.id {return 1}
	return 0
}


REPLICATION_MAX_DEFORMABLES_PER_TICK :: 8

replication_send_deformables :: proc(service: ^ReplicatorService, connection: ^Replication_Peer) {
	if service == nil || connection == nil {return}
	sent := 0
	for item in service.entity_list {
		if sent >= REPLICATION_MAX_DEFORMABLES_PER_TICK {break}
		object := item.object
		if object == nil || object.destroyed {continue}
		if connection.known[item.id] == 0 || !connection.initialized[item.id] {continue}
		if service.suppressed[object] {continue}
		if classes.Is_A(object, "Cloth") {
			cloth := cast(^classes.Cloth)object
			if !cloth.enabled || !cloth.initialized {continue}
			if connection.deformable[item.id] == cloth.revision {continue}
			bytes: [dynamic]u8
			replication_put_u32(&bytes, item.id)
			append(&bytes, Replication_Deformable_Cloth)
			for particle in cloth.particles {
				replication_put_f32(&bytes, particle.position.x)
				replication_put_f32(&bytes, particle.position.y)
				replication_put_f32(&bytes, particle.position.z)
			}
			if replication_send(service, connection.peer, Replication_Kind_Deformable, bytes[:]) {
				connection.deformable[item.id] = cloth.revision
				sent += 1
			}
			delete(bytes)
		} else if classes.Is_A(object, "SoftBody") {
			body := cast(^classes.SoftBody)object
			if !body.enabled || len(body.positions) == 0 {continue}
			if len(body.positions) > int(Replication_Deformable_Max_Vertices) {continue}
			if connection.deformable[item.id] == body.revision {continue}
			frame := classes.SoftBody_Current_CFrame(body)
			bytes: [dynamic]u8
			replication_put_u32(&bytes, item.id)
			append(&bytes, Replication_Deformable_SoftBody)
			replication_put_cframe(&bytes, frame)
			replication_put_u32(&bytes, u32(len(body.positions)))
			for position in body.positions {
				replication_put_f32(&bytes, position.x)
				replication_put_f32(&bytes, position.y)
				replication_put_f32(&bytes, position.z)
			}
			if replication_send(service, connection.peer, Replication_Kind_Deformable, bytes[:]) {
				connection.deformable[item.id] = body.revision
				sent += 1
			}
			delete(bytes)
		}
	}
}

replication_send_extra_properties :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	item: ^Replication_Entity,
	reliable: bool = false,
) -> bool {
	if item == nil || item.object == nil || item.object.destroyed {return false}

	sendable: [dynamic]string
	script := replication_peer_script(service, connection, item.object)
	defer delete(sendable)
	if replication_builtin_property(item.object, "CanTouch") {
		append(&sendable, "CanTouch")
	}
	if replication_builtin_property(item.object, "MeshId") {
		append(&sendable, "MeshId")
		append(&sendable, "MeshIndex")
		append(&sendable, "TextureId")
		append(&sendable, "CollisionFidelity")
	}
	if classes.Is_A_Class(item.object, &classes.PartOperation_Class) {
		append(&sendable, "UsePartColor", "CanQuery", "CastShadow")
	}
	if schema := replication_schema(service, classes.Get_Class_Name(item.object)); schema != nil {
		for property in schema.properties {


			if property == "Name" || property == "Value" {continue}
			if property == "Source" && script != nil {continue}
			append(&sendable, property)
		}
	}
	if len(sendable) == 0 {return true}

	confirmed := connection.acked_extra[item.id]
	sent, token := replication_send_property_batch(
		service,
		connection,
		item,
		sendable[:],
		replication_property_stream_extra,
		reliable,
		true,
		confirmed,
	)


	if sent {connection.extra_hashes[item.id] = token} else if connection.extra_hashes[item.id] == confirmed {
		connection.extra_hashes[item.id] = 0
	}
	return sent
}
