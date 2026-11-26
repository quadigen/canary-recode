package services

import kineffi "../bindings"
import classes "../classes"

CHARACTER_POSE_MAX_BONES :: 256
CHARACTER_POSE_INTERVAL :: f32(1.0 / 15.0)

Character_Pose_Send_State :: struct {
	sequence: u32,
	sent_at:  f32,
}

replication_character_pose_owner :: proc(
	service: ^ReplicatorService,
	object: ^classes.Object,
) -> u32 {
	if object == nil || object.destroyed || !classes.Is_A(object, "MeshPart") {return 0}
	for node := object.parent; node != nil; node = node.parent {
		if !classes.Is_A(node, "CharacterModel") {continue}
		model := cast(^classes.CharacterModel)node
		root := classes.CharacterModel_Root(model)
		entity := replication_entity(service, root)
		if entity != nil && entity.owner_id == model.owner_user_id {return entity.owner_id}
		return 0
	}
	return 0
}

replication_character_pose_signature :: proc(mesh: ^classes.MeshPart) -> u64 {
	hash := u64(14695981039346656037)
	for value in transmute([]u8)classes.MeshPart_Source_Path(mesh) {
		hash = (hash ~ u64(value)) * 1099511628211
	}
	return (hash ~ u64(mesh.mesh_index)) * 1099511628211
}

replication_character_pose_encode :: proc(entity: ^Replication_Entity, payload: ^[dynamic]u8) {
	replication_put_u32(payload, entity.id)
	replication_put_u32(payload, entity.pose_sequence)
	replication_put_u64(payload, entity.pose_signature)
	replication_put_u16(payload, u16(len(entity.pose)))
	for &transform in entity.pose {
		for value in transform[:12] {replication_put_f32(payload, value)}
	}
}

replication_receive_character_pose :: proc(
	service: ^ReplicatorService,
	peer: ^Replication_Transport_Peer,
	reader: ^Replication_Reader,
) {
	if (reader.capabilities & Replication_Capability_Character_Pose) == 0 {return}
	id := replication_read_u32(reader)
	sequence := replication_read_u32(reader)
	signature := replication_read_u64(reader)
	count := int(replication_read_u16(reader))
	if !reader.valid ||
	   sequence == 0 ||
	   count < 1 ||
	   count > CHARACTER_POSE_MAX_BONES ||
	   len(reader.data) - reader.offset != count * 48 {reader.valid = false; return}
	entity := replication_entity_by_id(service, id)
	if entity == nil ||
	   entity.object == nil ||
	   entity.object.destroyed ||
	   !classes.Is_A(entity.object, "MeshPart") {return}
	owner := replication_character_pose_owner(service, entity.object)
	if owner == 0 {return}
	if service.mode == .Server {
		allowed := false
		for &connection in service.peers {
			if connection.peer == peer &&
			   connection.player != nil &&
			   connection.handshake_complete &&
			   connection.scene_ready_sent &&
			   connection.player.user_id == owner &&
			   connection.initialized[id] {
				allowed = true
				break
			}
		}
		if !allowed {return}
		if entity.pose_received_at > 0 &&
		   service.clock - entity.pose_received_at < 1.0 / 40.0 {return}
	} else if service.mode == .Client {
		if peer != service.remote || owner == ownership_local_user_id(service) {return}
	} else {return}
	mesh := cast(^classes.MeshPart)entity.object
	if signature != replication_character_pose_signature(mesh) {return}
	if entity.pose_signature == signature &&
	   entity.pose_sequence != 0 &&
	   transmute(i32)(sequence - entity.pose_sequence) <= 0 {return}
	if mesh.native_mesh != nil &&
	   kineffi.Kine_Filament_GetMeshBoneCount(mesh.native_mesh) != i32(count) {return}
	pose: [CHARACTER_POSE_MAX_BONES][16]f32
	for index in 0 ..< count {
		for j in 0 ..< 12 {
			value := replication_read_f32(reader)
			if !physics_finite_f32(value) || abs(value) > 10000 {reader.valid = false; return}
			pose[index][j] = value
		}
		pose[index][15] = 1
	}
	if !reader.valid {return}
	if len(entity.pose) != count {
		delete(entity.pose)
		entity.pose = make([][16]f32, count)
	}
	copy(entity.pose, pose[:count])
	entity.pose_signature = signature
	entity.pose_sequence = sequence
	entity.pose_received_at = service.clock
	entity.pose_applied_valid = false
}

replication_character_pose_capture :: proc(
	entity: ^Replication_Entity,
	mesh: ^classes.MeshPart,
) -> bool {
	if mesh.native_mesh == nil {return false}
	count := int(kineffi.Kine_Filament_GetMeshBoneCount(mesh.native_mesh))
	if count <= 0 || count > CHARACTER_POSE_MAX_BONES {return false}
	pose: [CHARACTER_POSE_MAX_BONES][16]f32
	for index in 0 ..< count {
		if !kineffi.Kine_Filament_CopyMeshBoneGlobalTransform(
			mesh.native_mesh,
			i32(index),
			&pose[index][0],
		) {return false}
	}
	signature := replication_character_pose_signature(mesh)
	if len(entity.pose) == count && entity.pose_signature == signature {
		changed := false
		for index in 0 ..< count {
			if entity.pose[index] != pose[index] {changed = true; break}
		}
		if !changed {return true}
	} else {
		delete(entity.pose)
		entity.pose = make([][16]f32, count)
	}
	copy(entity.pose, pose[:count])
	entity.pose_signature = signature
	entity.pose_sequence += 1
	if entity.pose_sequence == 0 {entity.pose_sequence = 1}
	return true
}

replication_character_pose_apply :: proc(entity: ^Replication_Entity, mesh: ^classes.MeshPart) {
	if len(entity.pose) == 0 ||
	   mesh.native_mesh == nil ||
	   mesh.native_context == nil ||
	   entity.pose_signature != replication_character_pose_signature(mesh) ||
	   kineffi.Kine_Filament_GetMeshBoneCount(mesh.native_mesh) != i32(len(entity.pose)) {return}
	if entity.pose_applied_valid &&
	   entity.pose_applied_sequence == entity.pose_sequence &&
	   entity.pose_applied_mesh == rawptr(mesh.native_mesh) {return}
	if kineffi.Kine_Filament_SetMeshBoneTransforms(
		mesh.native_context,
		mesh.native_mesh,
		&entity.pose[0][0],
		i32(len(entity.pose)),
	) {
		entity.pose_applied_sequence = entity.pose_sequence
		entity.pose_applied_valid = true
		entity.pose_applied_mesh = rawptr(mesh.native_mesh)
		classes.Render_3D_Mark_Dirty()
	}
}

replication_character_pose_step :: proc(service: ^ReplicatorService, delta_time: f32) {
	service.pose_elapsed += delta_time
	if service.pose_elapsed < CHARACTER_POSE_INTERVAL {return}
	service.pose_elapsed = 0
	if !service.handshake_complete && service.mode == .Client {return}
	local_owner := ownership_local_user_id(service)
	for entity in service.entity_list {
		if entity == nil ||
		   entity.object == nil ||
		   entity.object.destroyed ||
		   !classes.Is_A(entity.object, "MeshPart") {continue}
		owner := replication_character_pose_owner(service, entity.object)
		if owner == 0 {continue}
		mesh := cast(^classes.MeshPart)entity.object
		if service.mode == .Client && owner == local_owner {
			if !service.scene_ready ||
			   (service.client_capabilities &
					   service.server_capabilities &
					   Replication_Capability_Character_Pose) ==
				   0 {continue}
			previous := entity.pose_sequence
			if !replication_character_pose_capture(entity, mesh) {continue}
			if previous == entity.pose_sequence &&
			   entity.pose_applied_sequence == entity.pose_sequence &&
			   service.clock - entity.pose_sent_at < 1 {continue}
			payload: [dynamic]u8
			replication_character_pose_encode(entity, &payload)
			if replication_send(
				service,
				service.remote,
				Replication_Kind_Character_Pose,
				payload[:],
				false,
			) {
				entity.pose_sent_at = service.clock
				entity.pose_applied_sequence = entity.pose_sequence
			}
			delete(payload)
		} else {
			replication_character_pose_apply(entity, mesh)
			if service.mode != .Server ||
			   len(entity.pose) == 0 ||
			   entity.pose_signature != replication_character_pose_signature(mesh) {continue}
			payload: [dynamic]u8
			replication_character_pose_encode(entity, &payload)
			for &connection in service.peers {
				if connection.player == nil ||
				   connection.player.user_id == owner ||
				   !connection.initialized[entity.id] ||
				   (connection.client_capabilities & Replication_Capability_Character_Pose) ==
					   0 {continue}
				if connection.pose_sent ==
				   nil {connection.pose_sent = make(map[u32]Character_Pose_Send_State)}
				sent := connection.pose_sent[entity.id]
				if sent.sequence == entity.pose_sequence &&
				   service.clock - sent.sent_at < 1 {continue}
				if replication_send(
					service,
					connection.peer,
					Replication_Kind_Character_Pose,
					payload[:],
					false,
				) {
					connection.pose_sent[entity.id] = {entity.pose_sequence, service.clock}
				}
			}
			delete(payload)
			entity.pose_sent_at = service.clock
		}
	}
}
