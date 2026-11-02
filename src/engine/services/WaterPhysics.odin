package services

import k "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import "core:math"

Water_Parameters :: proc(model: ^DataModel) -> k.KineFilamentWaterParams {
	params := classes.Water_Render_Params(nil)
	if model == nil || model.registry == nil {return params}
	if terrain := cast(^Terrain)DataModel_Get_Service(model, "Terrain"); terrain != nil {
		params.strength = terrain.water_wave_size
		params.speed = terrain.water_wave_speed * 0.1
	}
	if descriptor := classes.Find_Class(model.registry.classes, "Water"); descriptor != nil {
		for object in descriptor.instances {
			if object == nil || object.destroyed {continue}
			water := cast(^classes.Water)object
			if water.enabled && water.parent != nil {params = classes.Water_Render_Params(water)}
		}
	}
	return params
}

Water_Time :: proc(model: ^DataModel) -> f32 {
	if model == nil {return 0}
	if replication := cast(^ReplicatorService)DataModel_Get_Service(model, "ReplicatorService");
	   replication != nil {
		if replication.mode == .Server {return replication.clock}
		if replication.mode == .Client &&
		   replication.time_offset_measured {return replication.clock + replication.time_offset}
	}
	workspace := cast(^Workspace)DataModel_Get_Service(model, "Workspace")
	return workspace != nil ? f32(workspace.water_time) : 0
}

Water_Height :: proc(params: k.KineFilamentWaterParams, x, z, time: f32) -> f32 {
	return datatypes.Water_Wave_Height(
		x,
		z,
		time,
		params.speed,
		params.strength,
		params.height,
		params.waveScale,
		int(params.octaves),
	)
}

Water_Context :: struct {
	params:  k.KineFilamentWaterParams,
	time:    f32,
	terrain: ^Terrain,
	parts:   [dynamic]^classes.Part,
}

Water_Context_Create :: proc(physics: ^Physics) -> Water_Context {


	if workspace := DataModel_Get_Service(physics.data_model, "Workspace");
	   workspace != nil {Physics_Synchronize(physics, workspace)}
	result := Water_Context {
		params  = Water_Parameters(physics.data_model),
		time    = Water_Time(physics.data_model),
		terrain = cast(^Terrain)DataModel_Get_Service(physics.data_model, "Terrain"),
	}
	if result.terrain != nil {
		has_liquid := false
		for _, chunk in result.terrain.chunks {
			if chunk != nil &&
			   chunk.data != nil &&
			   chunk.data.surface > 0 {has_liquid = true; break}
		}
		if !has_liquid {result.terrain = nil}
	}
	for part in physics.scratch_parts {
		if part != nil && !part.destroyed && part.material == .Water {append(&result.parts, part)}
	}
	return result
}


water_part_interval :: proc(part: ^classes.Part, x, z: f32) -> (bottom, top: f32, found: bool) {
	inverse := datatypes.CFrame_Inverse(part.cframe)
	origin := datatypes.CFrame_Mul_Vector3(inverse, {x, 0, z})
	direction := datatypes.Vector3{inverse.r01, inverse.r11, inverse.r21}
	low, high := f32(-1e8), f32(1e8)
	o := [?]f32{origin.x, origin.y, origin.z}
	d := [?]f32{direction.x, direction.y, direction.z}
	size := [?]f32{part.size.x, part.size.y, part.size.z}
	for i in 0 ..< 3 {
		half := size[i] * 0.5
		if abs(d[i]) < 0.00001 {
			if abs(o[i]) > half {return}
		} else {
			a, b := (-half - o[i]) / d[i], (half - o[i]) / d[i]
			low = max(low, min(a, b)); high = min(high, max(a, b))
			if high <= low {return}
		}
	}
	return low, high, true
}

Water_Submersion :: proc(
	water: ^Water_Context,
	position: datatypes.Vector3,
	half_height: f32,
) -> (
	fraction, velocity: f32,
) {
	if len(water.parts) == 0 && (water.terrain == nil || len(water.terrain.chunks) == 0) {return}
	half := max(half_height, 0.05)
	bottom, top := position.y - half, position.y + half
	params := water.params
	h, speed := datatypes.Water_Wave_Sample(
		position.x,
		position.z,
		water.time,
		params.speed,
		params.strength,
		params.height,
		params.waveScale,
		int(params.octaves),
	)
	velocity = speed
	wet := f32(0)
	for part in water.parts {
		low, high, inside := water_part_interval(part, position.x, position.z)
		if inside {wet = max(wet, max(0, min(top, high + h) - max(bottom, low)))}
	}
	if terrain := water.terrain; terrain != nil && len(terrain.chunks) > 0 {
		vs := terrain.voxel_size
		x, z := int(math.floor(position.x / vs)), int(math.floor(position.z / vs))
		amplitude := 0.65 * water.params.strength * water.params.height
		first := int(math.floor((bottom - amplitude - 0.15) / vs + 0.5)) - 1
		last := int(math.ceil((top + amplitude - 0.15) / vs + 0.5)) + 1
		terrain_wet := f32(0)
		for y in first ..= last {
			cell, exists := Terrain_Get_Cell(terrain, x, y, z)
			if !exists || cell.water <= 0 || cell.material == .Glass {continue}

			low := (f32(y) - 0.5) * vs + 0.15
			high := (f32(y) + max(cell.water, cell.occupancy) - 0.5) * vs + 0.15
			above, has_above := Terrain_Get_Cell(terrain, x, y + 1, z)
			if !has_above || (above.water <= 0 && above.occupancy <= 0) {high += h}
			terrain_wet += max(0, min(top, high) - max(bottom, low))
		}
		wet = max(wet, terrain_wet)
	}
	fraction = clamp(wet / (half * 2), 0, 1)
	return
}


Water_Buoyant_Velocity :: proc(current, water_velocity, fraction, gravity, dt: f32) -> f32 {
	return(
		water_velocity +
		(current - water_velocity) * math.exp(-4 * fraction * dt) +
		gravity * 1.6 * fraction * dt \
	)
}

Physics_Apply_Water :: proc(physics: ^Physics, dt: f32) {
	water := Water_Context_Create(physics)
	defer delete(water.parts)
	if len(water.parts) == 0 && (water.terrain == nil || len(water.terrain.chunks) == 0) {return}
	for body in physics.bodies {
		part := cast(^classes.Part)body.object
		if part == nil ||
		   part.destroyed ||
		   body.anchored ||
		   body.remote ||
		   body.body_id == k.JPH_BODY_ID_INVALID {continue}
		cf := part.cframe
		half := datatypes.Vector3 {
			(abs(cf.r00) * part.size.x + abs(cf.r01) * part.size.y + abs(cf.r02) * part.size.z) *
			0.5,
			(abs(cf.r10) * part.size.x + abs(cf.r11) * part.size.y + abs(cf.r12) * part.size.z) *
			0.5,
			(abs(cf.r20) * part.size.x + abs(cf.r21) * part.size.y + abs(cf.r22) * part.size.z) *
			0.5,
		}
		fraction, wave_speed := f32(0), f32(0)
		points := [?]datatypes.Vector3 {
			{cf.x, cf.y, cf.z},
			{cf.x - half.x * .65, cf.y, cf.z - half.z * .65},
			{cf.x + half.x * .65, cf.y, cf.z - half.z * .65},
			{cf.x - half.x * .65, cf.y, cf.z + half.z * .65},
			{cf.x + half.x * .65, cf.y, cf.z + half.z * .65},
		}
		for point in points {
			wet, speed := Water_Submersion(&water, point, half.y)
			fraction += wet / 5; wave_speed += speed * wet / 5
		}
		if fraction <= 0 {continue}
		wave_speed /= fraction
		velocity: k.JPH_Vec3
		k.JPH_BodyInterface_GetLinearVelocity(
			physics.system.body_interface,
			body.body_id,
			&velocity,
		)
		velocity.y = Water_Buoyant_Velocity(velocity.y, wave_speed, fraction, physics.gravity, dt)
		drag := math.exp(-0.8 * fraction * dt)
		velocity.x *= drag; velocity.z *= drag
		k.JPH_BodyInterface_ActivateBody(physics.system.body_interface, body.body_id)
		k.JPH_BodyInterface_SetLinearVelocity(
			physics.system.body_interface,
			body.body_id,
			&velocity,
		)
	}

	replication := cast(^ReplicatorService)DataModel_Get_Service(
		physics.data_model,
		"ReplicatorService",
	)
	if replication != nil && replication.mode == .Client {return}
	players := DataModel_Get_Service(physics.data_model, "Players")
	if players == nil {return}
	for object in players.children {
		if object == nil || object.destroyed || !classes.Is_A(object, "Player") {continue}
		player := cast(^Player)object
		if !player.ragdoll || player.character == nil || player.character.destroyed {continue}
		cc := classes.CharacterController_From_Model(player.character)
		if cc == nil {continue}
		collision := cast(^classes.CollisionController)classes.CharacterController_Find(
			cc,
			"CollisionController",
		)
		if collision == nil || !collision.body_created || !collision.ragdoll {continue}
		cf, ok := Physics_Get_Character_Capsule_CFrame(physics, collision)
		if !ok {continue}
		fraction, wave_speed := Water_Submersion(
			&water,
			{cf.x, cf.y, cf.z},
			collision.half_height + collision.radius,
		)
		if fraction <= 0 {continue}
		velocity: k.JPH_Vec3
		k.JPH_BodyInterface_GetLinearVelocity(
			physics.system.body_interface,
			collision.body_id,
			&velocity,
		)
		velocity.y = Water_Buoyant_Velocity(velocity.y, wave_speed, fraction, physics.gravity, dt)
		k.JPH_BodyInterface_ActivateBody(physics.system.body_interface, collision.body_id)
		k.JPH_BodyInterface_SetLinearVelocity(
			physics.system.body_interface,
			collision.body_id,
			&velocity,
		)
	}
}
