package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import "core:strings"

Replication_Kind_Cloth_Config :: u8(37)

replication_cloth_attachment_id :: proc(service: ^ReplicatorService, peer: ^Replication_Peer, attachment: ^classes.Object) -> u32 {
	id := replication_entity_id(service, attachment)
	return id if peer.known[id] != 0 else 0
}

replication_send_cloth_config :: proc(service: ^ReplicatorService, peer: ^Replication_Peer, item: ^Replication_Entity, cloth: ^classes.Cloth) -> bool {
	state := peer.cloth_states[item.id]
	if state.config != 0 && state.config_revision == cloth.config_revision &&
	   state.attachment_generation == peer.attachment_generation {return true}
	data := make([dynamic]u8, 0, 128)
	defer delete(data)
	replication_put_u32(&data, item.id)
	replication_put_u64(&data, 0) // Patched with the hash of the configuration.
	flags: u8
	if cloth.enabled {flags |= 1}
	if cloth.can_collide {flags |= 2}
	if cloth.self_collision {flags |= 4}
	if cloth.custom_pins {flags |= 8}
	append(&data, u8(cloth.segments_x), u8(cloth.segments_y),
		u8(cloth.render_segments_x), u8(cloth.render_segments_y), u8(cloth.solver_iterations),
		u8(cloth.cloth_type), u8(cloth.fold_count), flags)
	values := [?]f32{
		cloth.size.X, cloth.size.Y, cloth.color.R, cloth.color.G, cloth.color.B,
		cloth.mass, cloth.damping, cloth.force.x, cloth.force.y, cloth.force.z,
		cloth.fold_depth, cloth.gather_ratio, cloth.fold_stiffness, cloth.bend_stiffness,
		cloth.stretch_stiffness, cloth.shear_stiffness,
	}
	for value in values {replication_put_f32(&data, value)}
	replication_put_string(&data, cloth.material_variant)
	left := replication_cloth_attachment_id(service, peer, cloth.attachment)
	right := replication_cloth_attachment_id(service, peer, cloth.attachment1)
	replication_put_u32(&data, left)
	replication_put_u32(&data, right)
	hash: u64 = 14695981039346656037
	hash = (hash ~ peer.attachment_generations[left]) * 1099511628211
	hash = (hash ~ peer.attachment_generations[right]) * 1099511628211
	for attachment, i in cloth.pin_attachments {
		if attachment == nil {continue}
		id := replication_cloth_attachment_id(service, peer, attachment)
		if id == 0 {continue}
		hash = (hash ~ peer.attachment_generations[id]) * 1099511628211
		replication_put_u16(&data, u16(i))
		replication_put_u32(&data, id)
		replication_put_f32(&data, cloth.pin_weights[i])
		for value in cloth.pin_offsets[i] {replication_put_f32(&data, value)}
	}
	for byte in data[12:] {hash = (hash ~ u64(byte)) * 1099511628211}
	if hash == 0 {hash = 1}
	if state.config != hash {
		for i in 0..<8 {data[4 + i] = u8(hash >> u32(i * 8))}
		if !replication_send(service, peer.peer, Replication_Kind_Cloth_Config, data[:]) {return false}
		state = {config = hash}
	}
	state.config_revision = cloth.config_revision
	state.attachment_generation = peer.attachment_generation
	peer.cloth_states[item.id] = state
	return true
}

Cloth_Pin_Wire :: struct {
	index: int,
	attachment: ^classes.Object,
	offset: [3]f32,
	weight: f32,
}

replication_receive_cloth_config :: proc(service: ^ReplicatorService, peer: ^Replication_Transport_Peer, reader: ^Replication_Reader) {
	if service.mode != .Client || peer != service.remote {return}
	object := replication_entity_object(service, replication_read_u32(reader))
	if object == nil || object.destroyed {return}
	if object.class != &classes.Cloth_Class {reader.valid = false; return}
	token := replication_read_u64(reader)
	sx, sy := int(replication_read_u8(reader)), int(replication_read_u8(reader))
	rx, ry := int(replication_read_u8(reader)), int(replication_read_u8(reader))
	iterations := int(replication_read_u8(reader))
	kind, folds, flags := replication_read_u8(reader), int(replication_read_u8(reader)), replication_read_u8(reader)
	values: [16]f32
	for &value in values {
		value = replication_read_f32(reader)
		if !physics_finite_f32(value) {reader.valid = false; return}
	}
	variant := replication_read_string(reader)
	left := replication_entity_object(service, replication_read_u32(reader))
	right := replication_entity_object(service, replication_read_u32(reader))
	if !reader.valid || token == 0 || flags > 15 ||
	   sx < 1 || sx > classes.CLOTH_MAX_SEGMENTS || sy < 1 || sy > classes.CLOTH_MAX_SEGMENTS ||
	   rx > 2 * classes.CLOTH_MAX_SEGMENTS || ry > 2 * classes.CLOTH_MAX_SEGMENTS ||
	   iterations < 1 || iterations > 32 || kind > u8(enums.ClothType.Custom) || folds > 32 ||
	   values[0] < 0.1 || values[0] > 1024 || values[1] < 0.1 || values[1] > 1024 ||
	   values[5] < 0.001 || values[6] < 0 || values[10] < 0 || values[10] > 1024 ||
	   (len(reader.data) - reader.offset) % 22 != 0 ||
	   (left != nil && !classes.Is_A_Class(left, &classes.Attachment_Class)) ||
	   (right != nil && !classes.Is_A_Class(right, &classes.Attachment_Class)) {
		reader.valid = false
		return
	}
	for value in values[11:] {
		if value < 0 || value > 1 {reader.valid = false; return}
	}
	count := (len(reader.data) - reader.offset) / 22
	if count > (sx + 1) * (sy + 1) {reader.valid = false; return}
	pins := make([]Cloth_Pin_Wire, count)
	defer delete(pins)
	last := -1
	for &pin in pins {
		pin.index = int(replication_read_u16(reader))
		pin.attachment = replication_entity_object(service, replication_read_u32(reader))
		pin.weight = replication_read_f32(reader)
		for &value in pin.offset {
			value = replication_read_f32(reader)
			if !(abs(value) <= 4096) {reader.valid = false; return}
		}
		if !reader.valid || pin.index <= last || pin.index >= (sx + 1) * (sy + 1) ||
		   !classes.Is_A_Class(pin.attachment, &classes.Attachment_Class) ||
		   !(pin.weight >= 0 && pin.weight <= 1) {
			reader.valid = false
			return
		}
		last = pin.index
	}

	cloth := cast(^classes.Cloth)object
	cloth.segments_x, cloth.segments_y = sx, sy
	classes.Cloth_Ensure_Grid(cloth)
	cloth.render_segments_x, cloth.render_segments_y = rx, ry
	cloth.solver_iterations, cloth.cloth_type, cloth.fold_count = iterations, enums.ClothType(kind), folds
	cloth.enabled, cloth.can_collide = flags & 1 != 0, flags & 2 != 0
	cloth.self_collision, cloth.custom_pins = flags & 4 != 0, flags & 8 != 0
	cloth.size, cloth.color = {values[0], values[1]}, {values[2], values[3], values[4]}
	cloth.mass, cloth.damping = values[5], values[6]
	cloth.force = {values[7], values[8], values[9]}
	cloth.fold_depth, cloth.gather_ratio = values[10], values[11]
	cloth.fold_stiffness, cloth.bend_stiffness = values[12], values[13]
	cloth.stretch_stiffness, cloth.shear_stiffness = values[14], values[15]
	if cloth.material_variant != variant {
		delete(cloth.material_variant)
		cloth.material_variant = strings.clone(variant)
	}
	cloth.attachment, cloth.attachment1 = left, right
	for &pin, i in cloth.pin_attachments {
		pin = nil
		cloth.pin_weights[i] = 1
		cloth.pin_offsets[i] = {}
	}
	for pin in pins {
		cloth.pin_attachments[pin.index] = pin.attachment
		cloth.pin_offsets[pin.index] = pin.offset
		cloth.pin_weights[pin.index] = pin.weight
	}
	cloth.snapshot_config = token
	cloth.snapshot_tick = 0
	classes.Render_3D_Mark_Dirty()
}

Replication_Cloth_Send_State :: struct {
	config, revision, reliable_revision: u64,
	config_revision, attachment_generation: u64,
	sequence, reliable_tick: u32,
}

replication_send_cloth :: proc(service: ^ReplicatorService, peer: ^Replication_Peer, item: ^Replication_Entity) -> bool {
	cloth := cast(^classes.Cloth)item.object
	if !replication_send_cloth_config(service, peer, item, cloth) {return false}
	state := peer.cloth_states[item.id]
	if !cloth.enabled || !cloth.initialized {return false}
	// A reliable keyframe ensures the final pose arrives even if an unreliable update was lost.
	keyframe := state.sequence == 0 || service.tick - state.reliable_tick >= 15
	if state.revision == cloth.revision && (!keyframe || state.revision == state.reliable_revision) {return false}

	lo, hi := cloth.particles[0].position, cloth.particles[0].position
	for particle in cloth.particles {
		for axis in 0..<3 {
			v := particle.position[axis]
			if !physics_finite_f32(v) {return false}
			lo[axis], hi[axis] = min(lo[axis], v), max(hi[axis], v)
		}
	}
	extent := hi - lo
	data := make([dynamic]u8, 0, 65 + len(cloth.particles) * 6)
	defer delete(data)
	replication_put_u32(&data, item.id)
	append(&data, Replication_Deformable_Cloth)
	replication_put_u64(&data, state.config)
	replication_put_u32(&data, state.sequence + 1)
	origin := cloth.simulation_origin
	replication_put_f64(&data, origin.x)
	replication_put_f64(&data, origin.y)
	replication_put_f64(&data, origin.z)
	for v in lo {replication_put_f32(&data, v)}
	for v in extent {replication_put_f32(&data, v)}
	for particle in cloth.particles {
		for axis in 0..<3 {
			v := (particle.position[axis] - lo[axis]) / extent[axis] if extent[axis] > 0 else 0
			replication_put_u16(&data, u16(clamp(v, 0, 1) * 65535 + 0.5))
		}
	}
	if !replication_send(service, peer.peer, Replication_Kind_Deformable, data[:], keyframe) {return false}
	state.revision = cloth.revision
	state.sequence += 1
	if keyframe {state.reliable_tick = service.tick; state.reliable_revision = state.revision}
	peer.cloth_states[item.id] = state
	return true
}

replication_receive_cloth_pose :: proc(cloth: ^classes.Cloth, reader: ^Replication_Reader) {
	config := replication_read_u64(reader)
	sequence := replication_read_u32(reader)
	if !reader.valid || config == 0 || config != cloth.snapshot_config ||
	   (cloth.snapshot_tick != 0 && transmute(i32)(sequence - cloth.snapshot_tick) <= 0) {return}
	origin := datatypes.Vector3{replication_read_f64(reader), replication_read_f64(reader), replication_read_f64(reader)}
	lo, extent: [3]f32
	for &v in lo {v = replication_read_f32(reader)}
	for &v in extent {v = replication_read_f32(reader)}
	if !reader.valid || !replication_vector3_finite(origin) ||
	   len(reader.data) - reader.offset != len(cloth.particles) * 6 {reader.valid = false; return}
	for axis in 0..<3 {
		if !physics_finite_f32(lo[axis]) || !(extent[axis] >= 0 && physics_finite_f32(lo[axis] + extent[axis])) {
			reader.valid = false
			return
		}
	}
	seed := !cloth.snapshot_received || origin != cloth.simulation_origin || !cloth.initialized
	for &target, i in cloth.snapshot_target {
		for axis in 0..<3 {target[axis] = lo[axis] + extent[axis] * (f32(replication_read_u16(reader)) / 65535)}
		cloth.snapshot_start[i] = cloth.particles[i].position
		if seed {cloth.particles[i] = {target, {}}}
	}
	cloth.snapshot_duration = 0 if seed else clamp(cloth.snapshot_elapsed, 1.0/120, 0.15)
	cloth.snapshot_elapsed = 0
	cloth.snapshot_tick, cloth.snapshot_received = sequence, true
	cloth.simulation_origin = origin
	cloth.width = classes.Cloth_Gathered_Width(cloth)
	cloth.pose_source = .Replication
	cloth.initialized = true
	cloth.revision += 1
	classes.Render_3D_Mark_Dirty()
}

replication_interpolate_cloth :: proc(cloth: ^classes.Cloth, dt: f32) -> bool {
	if !cloth.snapshot_received || !cloth.enabled || !cloth.initialized {return false}
	before := cloth.snapshot_elapsed
	cloth.snapshot_elapsed = min(before + dt, 0.2)
	if before >= cloth.snapshot_duration {return false}
	alpha := min(1, cloth.snapshot_elapsed / cloth.snapshot_duration)
	for &particle, i in cloth.particles {
		particle.position = cloth.snapshot_start[i] + (cloth.snapshot_target[i] - cloth.snapshot_start[i]) * alpha
	}
	cloth.revision += 1
	return true
}
