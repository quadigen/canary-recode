#+build !js
package services

import classes "../classes"
import datatypes "../datatypes"
import vm "../vm"
import "core:fmt"
import "core:sort"
import "core:strings"
import enet "vendor:ENet"

// Entity lookups. Every one of these used to be a linear scan over the entity
// array, which put the hot snapshot path at O(peers * entities * parts * depth).

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

replication_entity_insert :: proc(
	service: ^ReplicatorService,
	entity: ^Replication_Entity,
) {
	append(&service.entity_list, entity)
	service.entity_by_id[entity.id] = entity
	if entity.object != nil {service.entity_ids[entity.object] = entity.id}
}

// replication_forget_peer_entity drops every per-entity token this connection
// was tracking. Called whenever the client stops knowing about an entity, so a
// re-spawn always re-sends from scratch instead of being suppressed against a
// stale acknowledgement.
replication_forget_peer_entity :: proc(connection: ^Replication_Peer, id: u32) {
	delete_key(&connection.known, id)
	delete_key(&connection.initialized, id)
	delete_key(&connection.state_hashes, id)
	delete_key(&connection.property_hashes, id)
	delete_key(&connection.extra_hashes, id)
	delete_key(&connection.acked_state, id)
	delete_key(&connection.acked_property, id)
	delete_key(&connection.acked_extra, id)
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

replication_entity_remove :: proc(
	service: ^ReplicatorService,
	id: u32,
) -> bool {
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
	)
	schema: Replication_Schema
	schema.class_name = strings.clone(class_name)
	for property in properties {
		switch property {
		case "Parent", "Name", "ReplicationMode", "ReplicationGroup",
		     "AbsolutePosition", "AbsoluteSize",
		     "TextBounds", "SelectedText", "LineCount",
		     "AbsoluteCellCount", "AbsoluteCellSize", "AbsoluteContentSize",
		     "ClassName", "NetworkId", "UniqueId", "Capabilities", "IsInSandbox":
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

// replication_focus resolves the point a connection's relevancy is measured
// from: the client's own character, which is the owned Part the server can
// actually see.
//
// A camera would be the better reference, but the server cannot use one. A
// Camera is not a Part, is not owned by anyone, and is not a registered
// replicable class, so no client camera ever appears in entity_list. Making the
// sphere follow the view would first require replicating the camera, which is
// new protocol surface rather than a relevancy change.
//
// When the character is momentarily absent the previous focus point is reused
// instead of collapsing to "no focus". Under relevancy "no focus" means the
// client is sent nothing at all, so without a cache every respawn would briefly
// blank the world for that client and then spend time re-spawning the scene.
//
// The result is resolved once per peer per snapshot and threaded through, rather
// than rescanned for every entity: the previous per-entity version made each
// snapshot cost O(entities^2 * peers).
replication_focus :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
) -> (x, y, z: f32, ok: bool) {
	if connection.player == nil {return 0, 0, 0, false}
	part := replication_peer_focus_part(service, connection.player.user_id)
	if part != nil {
		connection.focus_x = part.cframe.x
		connection.focus_y = part.cframe.y
		connection.focus_z = part.cframe.z
		connection.focus_ok = true
		return connection.focus_x, connection.focus_y, connection.focus_z, true
	}
	// No character right now: reuse the last known point if there ever was one.
	return connection.focus_x, connection.focus_y, connection.focus_z, connection.focus_ok
}

// replication_lod_tier classifies a part against the focus by distance. Parts
// inside the inner band are "near" and are refreshed every snapshot; parts
// between the inner band and the relevance sphere are "far" and are refreshed
// on a slower cadence, because a part 300 studs away does not need to be smooth
// to be useful.
replication_lod_tier :: proc(
	service: ^ReplicatorService,
	fx, fy, fz: f32,
	part: ^classes.Part,
) -> (far: bool) {
	if service.lod_near_fraction >= 1 {return false}
	if service.relevancy_distance <= 0 {return false}
	near_sq := service.relevancy_distance * service.relevancy_distance * service.lod_near_fraction
	return replication_distance_sq(fx, fy, fz, part) > near_sq
}

// replication_lod_due decides whether a far part is refreshed on this tick.
//
// The cadence is a divisor of the tick count rather than a per-entity counter so
// that a part which drops out of range and comes back resynchronises on the
// shared grid instead of staying in phase with whatever it was doing before.
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

replication_peer_focus_part :: proc(
	service: ^ReplicatorService,
	user_id: u32,
) -> ^classes.Part {
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

replication_distance_sq :: proc(
	fx, fy, fz: f32,
	part: ^classes.Part,
) -> f32 {
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

// replication_relevant_to is the batchable form. A client with no focus point
// gets nothing rather than everything.
replication_relevant_to :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	object: ^classes.Object,
	fx, fy, fz: f32,
	has_focus: bool,
) -> bool {
	if object == nil || !has_focus {return false}
	// Anything that is not spatially positioned inherits the focus's scope, so
	// the server's own containers and singletons still reach the client.
	if !classes.Is_A(object, "Part") {return true}
	return replication_distance_sq(fx, fy, fz, cast(^classes.Part)object) <=
		service.relevancy_distance * service.relevancy_distance
}

// replication_visible_to folds the class and group rules together with spatial
// relevancy, so spawn, despawn and state cannot disagree about what a client
// should know about. Keeping these separate is what let an out-of-range part be
// spawned by one phase and then simply stopped being updated by another.
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
	return replication_visible(service, connection, object)
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
	// Spawns stay chargeable: refusing one is the load controller's job and costs
	// the client a missing object for a tick, which it retries. The client copes
	// with the inverse ordering, where the spawn beats the first transform, by
	// refusing to give an untransformed Part a physics body at all, so a
	// temporarily unplaced Part is inert rather than something the client's
	// solver picks up at the world origin.
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

// replication_send_part_state serialises a part's transform and appearance,
// returning whether it went out, the content token, and whether it was
// suppressed as already-confirmed.
//
// suppress/confirmed_token let the caller skip a send only when the client has
// explicitly acknowledged holding exactly this content. Passing the last *sent*
// token instead (which is what this used to do) meant a lost packet was never
// retried: a stationary part hashed the same forever and stayed at its default
// transform on the client.
replication_send_part_state :: proc(
	service: ^ReplicatorService,
	peer: ^enet.Peer,
	part: ^classes.Part,
	suppress: bool = false,
	confirmed_token: u32 = 0,
	reliable: bool = false,
) -> (bool, u32, bool) {
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
	// The token digest covers every content byte from the name onward. Two
	// things deliberately sit outside it:
	//   * the input acknowledgement, which changes every snapshot for
	//     HumanoidRootPart and would defeat suppression for the one part that
	//     always moves. It travels as its own kind 14 packet.
	//   * the token itself, obviously.
	hash: u64 = 14695981039346656037
	for byte in bytes[9:] {
		hash = (hash ~ u64(byte)) * 1099511628211
	}
	token := u32(hash & 0xFFFFFFFF)
	if suppress && token == confirmed_token {return true, token, true}
	replication_put_u32(&bytes, token)
	return replication_send(service, peer, 5, bytes[:], reliable), token, false
}

// replication_send_character_ack ships the last input sequence the server has
// consumed for a character to the client that owns it. Reconciliation needs
// this every snapshot regardless of whether the transform changed, so it lives
// outside the part-state packet and outside its content hash.
// replication_frame_finite reports whether every component of a CFrame is a
// finite number. Odin has no is_finite, so NaN and the infinities are detected by
// the fact that comparisons against them are never true.
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

// replication_frame_rotation_valid checks that the 3x3 basis is a right-handed
// rotation: unit-length rows that are mutually orthogonal. That is what
// separates a genuine orientation from a scaled or skewed matrix.
replication_frame_rotation_valid :: proc(frame: datatypes.CFrame) -> bool {
	// 1e-3 is far looser than the ~1e-6 error a real CFrame accumulates, while
	// still being far tighter than any scale or shear worth accepting.
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
			dot :=
				rows[i][0] * rows[j][0] +
				rows[i][1] * rows[j][1] +
				rows[i][2] * rows[j][2]
			if abs(dot) > tolerance {return false}
		}
	}
	// An orthonormal basis has |det| == 1; requiring a positive determinant
	// rejects mirrored reflections.
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
		if child == nil ||
		   child.destroyed ||
		   !classes.Is_A(child, "Player") {continue}
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

// replication_encode_property writes a kind 5 property frame (subtype, entity
// replication_encode_property_value encodes just the value of one property.
//
// It exists so the pass that decides which members are encodable and the pass
// that actually ships them cannot disagree. They used to call different code:
// the first pushed the field and encoded it, the second went through
// replication_encode_property, which also writes the frame header. Any property
// those two disagreed about produced a member count the client was told to wait
// for but the server never sent, so the batch was never acknowledged and both
// sides retried it forever.
replication_encode_property_value :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	property: string,
	bytes: ^[dynamic]u8,
) -> bool {
	if L == nil || object == nil || object.destroyed {return false}
	top := vm.StackTop(L)
	previous := vm.GetThreadSecurityCapabilities(L)
	vm.SetThreadSecurityCapabilities(L, vm.THREAD_SECURITY_ALL)
	defer vm.SetThreadSecurityCapabilities(L, previous)
	defer vm.SetStackTop(L, top)
	classes.Push_Object(L, object)
	_ = vm.GetField(L, -1, property)
	return replication_encode_value(L, -1, bytes, 0)
}

// id, tick, name, encoded value) into `bytes` without a trailer. Splitting the
// encode from the send lets a whole batch be hashed before any of it goes out.
replication_encode_property :: proc(
	service: ^ReplicatorService,
	L: ^vm.State,
	object: ^classes.Object,
	property: string,
	bytes: ^[dynamic]u8,
) -> bool {
	if service == nil || L == nil || object == nil || object.destroyed {return false}
	append(bytes, 2)
	replication_put_u32(bytes, replication_entity_id(service, object))
	replication_put_u32(bytes, service.tick)
	replication_put_string(bytes, property)
	return replication_encode_property_value(L, object, property, bytes)
}

// replication_send_property_frame appends the stream selector and the shared
// batch token, then ships the frame. Every member of a batch carries the same
// token, so the client ends up holding it no matter which subset of the members
// it received, and can acknowledge the batch as a unit.
replication_send_property_frame :: proc(
	service: ^ReplicatorService,
	peer: ^enet.Peer,
	bytes: ^[dynamic]u8,
	stream: u8,
	batch_token: u32,
	member_index: u8,
	member_count: u8,
	reliable: bool,
) -> bool {
	// stream | token | member_index | member_count. The last two let the client
	// work out when it has the whole batch. Without them a client that receives
	// one member of a lost batch would report the batch token anyway, and the
	// server would then suppress the members that never arrived, losing those
	// properties permanently.
	append(bytes, stream)
	replication_put_u32(bytes, batch_token)
	append(bytes, member_index, member_count)
	return replication_send(service, peer, 5, bytes[:], reliable)
}

replication_property_stream_builtin: u8 = 0
replication_property_stream_extra:   u8 = 1

// A property batch is tracked with a 64-bit arrival mask on the client, so a
// group can never be larger than the mask can represent. The limit is one short
// of 64 rather than 64 itself so the "have I got them all" test is a shift that
// cannot overflow: with 64 members the expression would need a 1 << 64, which is
// undefined, and the group would never be recognised as complete.
//
// A schema with more properties than this is not silently truncated. The members
// past the limit are sent reliably and unsuppressed every frame, so they always
// arrive; only the first group gets the suppression optimisation.
replication_property_batch_limit: u8 = 63

// replication_remaining_budget reports how many more bytes a peer may send this
// snapshot, or a negative value when a packet of this kind is not charged to the
// budget at all. It mirrors the exemption list in replication_send, so the
// pre-flight check here and the check in replication_send cannot disagree about
// whether a frame is budgeted.
replication_remaining_budget :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	kind: u8,
) -> int {
	if service == nil || connection == nil {return -1}
	// Mirrors replication_budgeted, so this pre-flight check and the charge in
	// replication_send cannot disagree about whether a frame counts.
	if !replication_budgeted(service, kind) {return -1}
	return int(service.bandwidth_budget) - int(connection.bytes_this_tick)
}

// replication_send_property_batch encodes every name in `names`, derives a
// single content token for the whole group, and sends each member carrying that
// shared token.
//
// Suppression is per batch, not per property. The previous design hashed each
// property separately and then combined the halves on the server, but the client
// only ever reported the last frame it applied, so the combined token could
// never match what the client sent back. Every property therefore re-sent on
// every tick, and a lost one was unrecoverable. Now the token the server
// compares is the exact token the client reports.
replication_send_property_batch :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	item: ^Replication_Entity,
	names: []string,
	stream: u8,
	reliable: bool,
	skip_if_confirmed: bool,
	confirmed: u32,
) -> (bool, u32) {
	if service == nil || connection == nil || item == nil {return false, 0}
	if item.object == nil || item.object.destroyed {return false, 0}
	if len(names) == 0 {return true, confirmed}
	L := service.data_model.registry.vm_state.L
	if L == nil {return false, 0}

	// Pass one: encode the whole group to derive its token. Members whose value
	// will not encode are excluded from both the hash and the send so the two
	// always agree, and the encodability test uses the same encoder the send
	// uses so the member count the client is told to expect is the count that
	// actually goes out.
	scratch: [dynamic]u8
	defer delete(scratch)
	encodable: [dynamic]bool
	defer delete(encodable)
	for name in names {
		mark := len(scratch)
		if replication_encode_property_value(L, item.object, name, &scratch) {
			append(&encodable, true)
		} else {
			resize(&scratch, mark)
			append(&encodable, false)
		}
	}

	hash: u64 = 14695981039346656037
	for byte in scratch {hash = (hash ~ u64(byte)) * 1099511628211}
	batch_token := u32(hash & 0xFFFFFFFF)

	if skip_if_confirmed && batch_token == confirmed {return true, batch_token}

	// A group where nothing encoded carries no information, so it must settle
	// against whatever was already confirmed. Returning a fresh token here would
	// make the server believe it had shipped content it never sent, and it would
	// resend the empty group every tick forever.
	encodable_count := 0
	for flag in encodable {if flag {encodable_count += 1}}
	if encodable_count == 0 {return true, confirmed}

	// Pass two: encode every member up front, then decide whether the group fits
	// before sending any of it.
	//
	// The group has to be atomic against the budget. Sending members one at a
	// time and letting the budget run out mid-group leaves the client holding a
	// partial group, and by design the client will not report a group complete
	// until every member has arrived, so it never acknowledges, so the server
	// retries it forever. Under sustained pressure that is a deadlock rather than
	// backpressure, and it is self-sustaining: the partial sends are exactly the
	// traffic that keeps the load controller holding the budget down.
	//
	// Refusing the whole group is what makes the drop count honest. It costs this
	// entity one snapshot, and the rotation in replication_sync guarantees it
	// eventually leads the walk and gets the budget to itself.
	frames: [dynamic][dynamic]u8
	defer delete(frames)
	all_sent := true
	total: int
	for name, index in names {
		if !encodable[index] {continue}
		bytes: [dynamic]u8
		if !replication_encode_property(service, L, item.object, name, &bytes) {
			delete(bytes)
			all_sent = false
			continue
		}
		// replication_send charges the five byte transport header on top of the
		// payload it is handed.
		total += len(bytes) + 5
		append(&frames, bytes)
	}
	if len(frames) == 0 {return all_sent, confirmed}

	wide := encodable_count > int(replication_property_batch_limit)
	remaining := replication_remaining_budget(service, connection, 5)
	if remaining >= 0 && total > remaining {
		for frame in frames {delete(frame)}
		return false, confirmed
	}

	// A group wider than the client's arrival mask cannot be reported complete, so
	// the server does not try to suppress it. Members go out reliable every
	// frame and the group settles against the previously confirmed token instead
	// of claiming a delivery that would otherwise never be acknowledged. Schema
	// registration rejects groups this wide up front, so this is a backstop for
	// a caller that bypassed registration rather than a normal path.
	if wide {
		for &frame in frames {
			if !replication_send_property_frame(
				service,
				connection.peer,
				&frame,
				stream,
				batch_token,
				0,
				1,
				true,
			) {
				all_sent = false
			}
		}
		return all_sent, confirmed
	}
	sent: u8 = 0
	for &frame in frames {
		if !replication_send_property_frame(
			service,
			connection.peer,
			&frame,
			stream,
			batch_token,
			sent,
			u8(encodable_count),
			reliable,
		) {
			all_sent = false
		}
		sent += 1
	}
	return all_sent, batch_token
}

// replication_builtin_property_names lists the properties that ride on the
// builtin suppression channel: the instance name and, for value containers, the
// stored value.
replication_builtin_property_names :: proc(item: ^Replication_Entity) -> [dynamic]string {
	names: [dynamic]string
	if item == nil || item.object == nil || item.object.destroyed {return names}
	if replication_builtin_property(item.object, "Name") {append(&names, "Name")}
	if classes.Is_A(item.object, "ValueBase") {append(&names, "Value")}
	return names
}

replication_root_service :: proc(
	service: ^ReplicatorService,
	object: ^classes.Object,
) -> bool {
	return service != nil &&
	       service.data_model != nil &&
	       object != nil &&
	       classes.Is_A(object, "Service") &&
	       object.parent == &service.data_model.object &&
	       replication_root_allowed(object.name)
}

replication_sync_tree :: proc(service: ^ReplicatorService, object: ^classes.Object) {
	if object == nil || object.destroyed || object == &service.object {return}
	if !replication_root_service(service, object) &&
	   object != &service.data_model.object &&
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

// replication_spawn_part finds the Part a joining character is about to stand
// on: the Spawn part the character service reads its spawn position from. It is
// a direct child of Workspace and is the only part whose arrival the client
// needs before its character can be simulated at all.
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

// replication_spawn_entity sends one entity's spawn to a peer if the peer is
// meant to see it and does not have it yet. It is the single spawn path used by
// both the prioritized spawn pass and the general pass, so the two cannot drift
// apart on what "already spawned" means.
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
	parent_id := replication_entity_id(service, object.parent)
	if parent_id != 0 && connection.known[parent_id] == 0 {
		return false
	}
	if connection.known[item.id] == parent_id + 1 {return false}
	if connection.known[item.id] != 0 {
		bytes: [dynamic]u8
		replication_put_u32(&bytes, item.id)
		_ = replication_send(service, connection.peer, 8, bytes[:])
		delete(bytes)
	}
	if !replication_send_spawn(service, connection.peer, object) {
		return false
	}
	connection.known[item.id] = parent_id + 1
	replication_forget_peer_entity(connection, item.id)
	connection.known[item.id] = parent_id + 1
	return true
}

// replication_spawn_tree walks a subtree depth first and spawns each of its
// entities, parents before children. The depth first order is what lets the
// spawn's own children be sent in the same pass as the spawn: a child is skipped
// while its parent is unknown, and the parent is visited first.
replication_spawn_tree :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	root: ^classes.Object,
	focus_x, focus_y, focus_z: f32,
	has_focus: bool,
) -> int {
	if service == nil || connection == nil || root == nil || root.destroyed {return 0}
	spawned := 0
	if replication_spawn_entity(
		service,
		connection,
		root,
		focus_x,
		focus_y,
		focus_z,
		has_focus,
	) {
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

// replication_spawn_tree_with_ancestry makes a subtree usable immediately: its
// replicated service and container ancestors are emitted before the subtree.
// This is used for the joining player's character ahead of the bulk map, so a
// large Workspace can never postpone the character behind unrelated geometry.
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
			service, connection, chain[index], focus_x, focus_y, focus_z, has_focus,
		) {spawned += 1}
	}
	return spawned + replication_spawn_tree(
		service, connection, root, focus_x, focus_y, focus_z, has_focus,
	)
}

// replication_initialise_entity sends the first usable content for a spawn.
// Initial Part transforms must be reliable and are intentionally emitted ahead
// of the map stream for the local character and its spawn platform.
replication_initialise_entity :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	item: ^Replication_Entity,
) -> bool {
	if service == nil || connection == nil || item == nil || item.object == nil ||
	   item.object.destroyed || connection.known[item.id] == 0 {return false}
	if connection.initialized[item.id] {return true}
	sent := false
	if classes.Is_A(item.object, "Part") {
		state_sent, state_token, _ := replication_send_part_state(
			service, connection.peer, cast(^classes.Part)item.object, false, 0, true,
		)
		sent = state_sent
		if sent {connection.state_hashes[item.id] = state_token}
	} else {
		names := replication_builtin_property_names(item)
		defer delete(names)
		property_sent, property_token := replication_send_property_batch(
			service, connection, item, names[:], replication_property_stream_builtin,
			true, false, 0,
		)
		sent = property_sent
		connection.property_hashes[item.id] = property_token
	}
	if sent {connection.initialized[item.id] = true}
	replication_send_extra_properties(service, connection, item, sent)
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

// replication_peer_scene_complete reports whether every entity this peer is
// meant to see has already been spawned to it.
//
// The test mirrors the spawn loop's own filter exactly. Reusing that filter is
// the point: an entity the loop skips (out of relevancy range, suppressed, or
// waiting on a parent that has not spawned yet) must not keep the marker from
// being sent, and an entity the loop would send must not be reported complete
// before it actually went out. An entity whose parent has not arrived yet is
// still pending, because a later tick will spawn it.
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
		) ||
		   service.suppressed[item.object] {
			continue
		}
		if connection.known[item.id] == 0 {return false}
	}
	return true
}

// replication_terrain_complete reports whether this peer is done with the
// initial terrain push.
//
// A map with no Terrain service, or a peer that never asked for terrain, is
// complete immediately. Otherwise the initial snapshot has to have gone out,
// and terrain runs at half rate, so "not due yet this tick" is not "never":
// only the initial send is required, not the deltas that follow.
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

// replication_peer_support_ready reports whether the geometry the character is
// actually standing on has been flushed to this peer.
//
// The Spawn marker is usually a non-colliding position hint, so readiness keyed
// only on it released the client into a world whose real floor had not arrived.
// The client is client-authoritative, so it integrated gravity against nothing
// and fell out of the map.
//
// This deliberately does NOT block forever. When the world genuinely has no
// collidable surface below the spawn there is nothing to wait for, so the
// caller falls through to ready rather than stalling the join indefinitely.
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
	result, hit := Physics_Raycast(physics, workspace, origin, datatypes.Vector3{0, -512, 0}, &params)
	if !hit {return true}
	// Terrain carries no Instance behind it; replication_terrain_complete covers it.
	support := cast(^classes.Part)result.ObjectRef
	if support == nil {return true}
	item := replication_entity(service, &support.object)
	// A body with no replication entity cannot be replicated, so waiting on it
	// would stall the join forever.
	if item == nil {return true}
	return connection.initialized[item.id]
}

// replication_peer_spawn_ready is deliberately narrower than "the whole map
// has streamed".  The local character only needs its own authoritative Parts,
// the authored Spawn platform (when present), the geometry it will stand on,
// and terrain before gravity is safe.  Waiting for every map Part made join time
// proportional to map size.
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

// REPLICATION_DROP_PRESSURE_RECOVER_BELOW is the smoothed drop pressure below
// which the link counts as unpressured and the scale is allowed to climb again.
// It sits far below the pressure a real sustained overload settles at.
REPLICATION_DROP_PRESSURE_RECOVER_BELOW: f32 = 0.02

replication_sync :: proc(service: ^ReplicatorService) {
	// Terrain rides the snapshot clock at half rate. Adaptive load control already
	// governs this call's frequency, so a server shedding load sheds terrain
	// updates with it.
	service.terrain_sync_tick += 1
	service.terrain_sync_due = service.terrain_sync_tick % 2 == 0
	if service.mode != .Server || service.data_model == nil {return}
	for root_name in REPLICATION_ROOT_NAMES {
		replication_sync_tree(service, DataModel_Get_Service(service.data_model, root_name))
	}

	// -------------------------------------------------------------------------
	// Adaptive load control
	//
	// bandwidth_drops counts packets the per-connection budget refused, which is
	// a measurement of being OVER budget. The correct response is therefore to
	// send less. The previous version did the opposite: on any drop it widened
	// the budget and pushed the snapshot rate up toward 30 Hz. That is a positive
	// feedback loop, because a wider budget buys more sends, more sends buy more
	// drops, and more drops buy a wider budget again.
	//
	// Drops now scale the budget and snapshot rate down toward a floor, and an
	// unpressured link creeps back up to the configured values. Recovery is
	// deliberately slower than the back-off so a momentary spike does not
	// immediately re-saturate the link.
	// -------------------------------------------------------------------------
	drops := service.drops_window
	service.drops_window = 0
	// Drop pressure is an exponential moving average of the per-snapshot severity
	// rather than a "did this snapshot drop anything" flag. Under a sustained
	// overload the budget refuses on most snapshots but not all of them (the
	// rotation makes any given snapshot cheaper), so a one-snapshot test creeps the
	// scale back up in the middle of an overload and the scale oscillates instead of
	// holding its back-off. Once the scene settles the drops stop and the average
	// decays, which is what permits recovery.
	severity := f32(0)
	if drops > 0 {severity = min(1, f32(drops) / 32)}
	service.drop_pressure += 0.1 * (severity - service.drop_pressure)
	if service.drop_pressure > REPLICATION_DROP_PRESSURE_RECOVER_BELOW {
		// Back off in proportion to how badly we overshot, floored so a
		// sustained overload settles at a reduced rate rather than at zero.
		service.adaptive_scale = max(
			service.adaptive_scale * (1 - 0.25 * severity),
			service.adaptive_min_scale,
		)
	} else {
		service.adaptive_scale = min(service.adaptive_scale + 0.05, 1)
	}
	service.bandwidth_budget =
		u32(f32(service.base_bandwidth_budget) * service.adaptive_scale)
	service.snapshot_rate = f32(max(
		u32(f32(service.base_snapshot_rate) * service.adaptive_scale),
		service.adaptive_min_snapshot_rate,
	))

	// Update velocity_sq on each Part entity so the priority sort below can
	// rank fast-moving parts ahead of stationary ones.
	for item in service.entity_list {
		if item.object == nil ||
		   item.object.destroyed ||
		   !classes.Is_A(item.object, "Part") {
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

	for &connection in service.peers {
		connection.bytes_this_tick = 0
		// A peer that has connected but not yet completed the handshake has no
		// player and no agreed protocol, so it receives nothing. Sending it spawn
		// or state frames would spend bandwidth on a connection that is about to
		// be refused, and would put unversioned frames in front of a client that
		// has not been told what it is allowed to understand.
		if !connection.handshake_complete {continue}

		// Terrain is pushed separately from the instance tree: it is a bulk,
		// low-frequency transfer rather than per-entity state, and running it on
		// the snapshot cadence would resend a voxel map whose changes are mostly
		// other players standing on it. It rides the snapshot clock at half rate
		// rather than its own, so the existing adaptive load control already
		// throttles it instead of a second budget having to be invented.
		if service.mode == .Server && service.terrain_sync_due {
			replication_send_terrain_delta(service, &connection)
		}

		// The focus is resolved once here and reused by all three phases below.
		// Resolving it per entity made every snapshot O(entities^2 * peers).
		focus_x, focus_y, focus_z, has_focus := replication_focus(service, &connection)

		// -----------------------------------------------------------------------
		// Phase 1: Spawns — always reliable, skip bandwidth check.
		// -----------------------------------------------------------------------
		spawned := 0
		// Put this peer's character before the bulk Workspace.  On a large map
		// entity_list is map-first, so the old single linear walk could enqueue
		// thousands of map spawns before the one model that needs to begin play.
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
		// Send the local character's first transforms before the general map
		// stream.  A spawn alone constructs Parts at their default transform;
		// allowing simulation before this state arrived was the direct cause of
		// characters falling through a still-streaming world.
		if connection.player != nil && connection.player.character != nil {
			replication_initialise_tree(
				service,
				&connection,
				&connection.player.character.object,
			)
		}
		if spawn_part != nil {replication_initialise_tree(service, &connection, &spawn_part.object)}

		// This marker is a spawn-area readiness barrier, not a whole-map barrier:
		// the rest of the map continues to stream below while the player can
		// safely stand on their replicated spawn platform.
		if !connection.scene_ready_sent &&
		   (connection.client_capabilities & Replication_Capability_Scene_Ready) != 0 &&
		   replication_peer_spawn_ready(service, &connection, spawn_part) {
			connection.scene_ready_sent =
				replication_send(service, connection.peer, Replication_Kind_Scene_Ready, nil, true)
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
		// Now that the general pass has run, every entity this peer is meant to
		// see has been considered, so the scene-completeness test is meaningful.
		// This is the frame behind workspace.FinishedReplicating, and unlike the
		// spawn-area barrier above it waits for the whole scene.
		if !connection.finished_replicating_sent &&
		   (connection.client_capabilities &
			Replication_Capability_Finished_Replicating) != 0 &&
		   replication_peer_scene_complete(service, &connection, focus_x, focus_y, focus_z, has_focus) &&
		   replication_terrain_complete(service, &connection) {
			connection.finished_replicating_sent =
				replication_send(
					service,
					connection.peer,
					Replication_Kind_Finished_Replicating,
					nil,
					true,
				)
		}
		// -----------------------------------------------------------------------
		// Phase 2: Despawns
		// -----------------------------------------------------------------------
		for item in service.entity_list {
			if connection.known[item.id] == 0 {continue}
			// This is the other half of the relevancy fix: a part that leaves the
			// sphere is despawned here rather than being left behind on the client
			// at whatever position it last received.
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

		// -----------------------------------------------------------------------
		// Phase 3: State sends.
		//
		// Strategy:
		//   • First pass: guarantee a first authoritative state for entities that
		//     have just spawned. These go out on the RELIABLE channel so ENet's
		//     ordering guarantee puts them after the spawn that created the
		//     entity. (State normally rides the unreliable channel, and ENet
		//     does not order across channels, so an unreliable first frame could
		//     land before the spawn and be dropped against a nil entity.)
		//   • Second pass: send the remaining entities in descending velocity
		//     order, skipping any whose current content the client has already
		//     acknowledged. Fast movers claim the bandwidth budget first.
		// -----------------------------------------------------------------------

		// First: guarantee initial state for any entity that just spawned this
		// tick (initialized == false).
		//
		// This pass shares the snapshot budget, so it is rotated for the same
		// reason the steady-state pass below is. An entity stuck at
		// initialized == false is resent every tick, and in a fixed order the
		// budget is always consumed by the same few, so the rest never get their
		// first content, never get acknowledged, and never leave this pass. The
		// client is left holding a permanently wrong object.
		entity_total := len(service.entity_list)
		init_start := 0
		if entity_total > 0 {
			init_start = int(connection.init_cursor % u32(entity_total))
			connection.init_cursor += 1
		}
		for offset in 0 ..< entity_total {
			item := service.entity_list[(init_start + offset) % entity_total]
			if connection.known[item.id] == 0 ||
			   item.object == nil ||
			   item.object.destroyed {continue}
			if connection.initialized[item.id] {continue} // handled below

			sent := false
			if classes.Is_A(item.object, "Part") {
				state_sent, state_token, _ := replication_send_part_state(
					service,
					connection.peer,
					cast(^classes.Part)item.object,
					false,
					0,
					true,
				)
				sent = state_sent
				if sent {connection.state_hashes[item.id] = state_token}
			} else {
				names := replication_builtin_property_names(item)
				defer delete(names)
				// Initial content is reliable so it cannot be reordered ahead of
				// the spawn it belongs to, and it is never suppressed: the client
				// has no confirmed token for a brand new entity yet.
				property_sent, property_token := replication_send_property_batch(
					service,
					&connection,
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
			if sent {connection.initialized[item.id] = true}
			// Extra properties share the reliable channel here so a schema
			// property cannot overtake the spawn either.
			replication_send_extra_properties(service, &connection, item, sent)
			replication_send_character_ack(service, &connection, item.object)
		}

		// Second: collect the already-initialized, in-relevancy entities and
		// order them by velocity so fast parts claim the budget first.
		sorted: [dynamic]^Replication_Entity
		defer delete(sorted)
		for item in service.entity_list {
			if connection.known[item.id] == 0 ||
			   item.object == nil ||
			   item.object.destroyed {continue}
			if !connection.initialized[item.id] {continue} // already handled above
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
		// Descending by velocity_sq. This replaced an insertion sort, which was
		// O(n^2) and only "fine because N is small" by assumption.
		sort.quick_sort_proc(sorted[:], replication_velocity_desc)

		// Rotate where the walk starts so the budget is shared fairly across
		// snapshots. The velocity order still decides who wins *within* a tick, so
		// fast movers keep their priority, but every entity eventually leads once
		// and so every entity is guaranteed to be sent at least occasionally.
		//
		// This matters more than it looks. A fixed order under a budget too small
		// to cover the whole scene starves exactly the entities at the back of the
		// queue: they are never sent, so they are never acknowledged, so they stay
		// queued, and the load controller then reads the resulting drops as
		// sustained pressure and pins itself at its floor. The link never recovers
		// even though it is completely idle.
		total := len(sorted)
		start := 0
		if total > 0 {
			start = int(connection.bandwidth_cursor % u32(total))
			connection.bandwidth_cursor += 1
		}
		for offset in 0 ..< total {
			item := sorted[(start + offset) % total]
			// A far part inside the sphere is still spawned and still tracked, it
			// just does not earn a frame every snapshot. Gating here rather than
			// at collection time keeps the part in the budget rotation, so it is
			// still sent when the tick it is due for comes round.
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
			// Each suppression channel is checked against its own acknowledged
			// token. They used to share one, so a confirmed transform could mask
			// a property that had never been delivered, and vice versa.
			if classes.Is_A(item.object, "Part") {
				confirmed := connection.acked_state[item.id]
				settled := connection.state_hashes[item.id] == confirmed
				state_sent, state_token, suppressed := replication_send_part_state(
					service,
					connection.peer,
					cast(^classes.Part)item.object,
					settled,
					confirmed,
					false,
				)
				if suppressed {
					service.unchanged_states_skipped += 1
				} else if state_sent {
					connection.state_hashes[item.id] = state_token
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
			replication_send_character_ack(service, &connection, item.object)
		}

		if spawned > 0 && connection.player != nil {
			fmt.printf(
				"[Replication] sent initial snapshot to %s (%d instances)\n",
				connection.player.name,
				spawned,
			)
		}
	}
	for index := len(service.entity_list) - 1; index >= 0; index -= 1 {
		item := service.entity_list[index]
		if !replication_in_scope(service, item.object) || service.suppressed[item.object] {
			if item.object != nil && !item.object.destroyed {item.object.network_id = 0}
			_ = replication_entity_remove(service, item.id)
		}
	}
	service.tick += 1
}

// replication_velocity_desc orders entities for the state budget by descending
// speed, so fast movers are replicated before stationary geometry that would
// otherwise consume the whole allowance.
replication_velocity_desc :: proc(a: ^Replication_Entity, b: ^Replication_Entity) -> int {
	if a == nil {return b == nil ? 0 : 1}
	if b == nil {return -1}
	if a.velocity_sq > b.velocity_sq {return -1}
	if a.velocity_sq < b.velocity_sq {return 1}
	// Stable tiebreak on id so equal-speed entities keep a deterministic order.
	if a.id < b.id {return -1}
	if a.id > b.id {return 1}
	return 0
}

// replication_send_extra_properties sends the schema properties (and the
// MeshPart asset ids) that ride alongside an entity's transform on their own
// suppression channel. MeshId and TextureId used to be sent on every single tick
// with no hashing at all; folding them into an acknowledged batch means they are
// only re-sent when the client is actually missing them.
replication_send_extra_properties :: proc(
	service: ^ReplicatorService,
	connection: ^Replication_Peer,
	item: ^Replication_Entity,
	reliable: bool = false,
) {
	if item == nil || item.object == nil || item.object.destroyed {return}

	sendable: [dynamic]string
	defer delete(sendable)
	if replication_builtin_property(item.object, "MeshId") {
		append(&sendable, "MeshId")
		append(&sendable, "TextureId")
	}
	if schema := replication_schema(service, classes.Get_Class_Name(item.object)); schema != nil {
		for property in schema.properties {
			// Name and Value travel on the builtin channel so the transform
			// budget and the property budget stay independent.
			if property == "Name" || property == "Value" {continue}
			append(&sendable, property)
		}
	}
	if len(sendable) == 0 {return}

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
	// Only record the batch as delivered once every member actually went out.
	// Recording a failed send would make the next round suppress content the
	// client never received.
	if sent {connection.extra_hashes[item.id] = token} else if connection.extra_hashes[item.id] == confirmed {
		connection.extra_hashes[item.id] = 0
	}
}
