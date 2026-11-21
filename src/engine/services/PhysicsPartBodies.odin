package services

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import jolt "../physics"

physics_hook_service :: proc(ctx: rawptr) -> ^Physics {
	registry := cast(^Registry)ctx
	if registry == nil {return nil}
	descriptor := Find_Service(registry, "Physics")
	if descriptor == nil {return nil}
	return cast(^Physics)descriptor.object
}

physics_hook_body :: proc(ctx: rawptr, object: ^classes.Object) -> (^Physics, ^Physics_Body) {
	physics := physics_hook_service(ctx)
	if physics == nil || object == nil || !physics.initialized {return nil, nil}
	index := physics_find_body_index(physics, object)
	if index < 0 {return nil, nil}
	body := &physics.bodies[index]
	if body.body_id == kineffi.JPH_BODY_ID_INVALID || body.remote {return nil, nil}
	return physics, body
}

physics_hook_remote_velocity :: proc(
	ctx: rawptr,
	object: ^classes.Object,
) -> (
	linear, angular: datatypes.Vector3,
	ok: bool,
) {
	when ODIN_OS != .JS {
		registry := cast(^Registry)ctx
		if registry == nil || object == nil {return}
		descriptor := Find_Service(registry, "ReplicatorService")
		if descriptor == nil || descriptor.object == nil {return}
		replicator := cast(^ReplicatorService)descriptor.object
		if replicator.mode != .Client {return}
		entity := replication_entity(replicator, object)
		if entity == nil ||
		   len(entity.samples) == 0 ||
		   (entity.owner_id != 0 &&
				   entity.owner_id == ownership_local_user_id(replicator)) {return}
		sample := entity.samples[len(entity.samples) - 1]
		if sample.has_velocity {return sample.linear_velocity, sample.angular_velocity, true}
	}
	return
}

physics_hook_get_linear_velocity :: proc(
	ctx: rawptr,
	object: ^classes.Object,
) -> (
	datatypes.Vector3,
	bool,
) {
	physics, body := physics_hook_body(ctx, object)
	if physics == nil {
		linear, _, ok := physics_hook_remote_velocity(ctx, object)
		return linear, ok
	}
	velocity: kineffi.JPH_Vec3
	kineffi.JPH_BodyInterface_GetLinearVelocity(
		physics.system.body_interface,
		body.body_id,
		&velocity,
	)
	return datatypes.Vector3{f64(velocity.x), f64(velocity.y), f64(velocity.z)}, true
}

physics_hook_set_linear_velocity :: proc(
	ctx: rawptr,
	object: ^classes.Object,
	value: datatypes.Vector3,
) {
	physics, body := physics_hook_body(ctx, object)
	if physics == nil {return}
	velocity := kineffi.JPH_Vec3{f32(value.x), f32(value.y), f32(value.z)}
	kineffi.JPH_BodyInterface_SetLinearVelocity(
		physics.system.body_interface,
		body.body_id,
		&velocity,
	)


	kineffi.JPH_BodyInterface_ActivateBody(physics.system.body_interface, body.body_id)
}

physics_hook_get_angular_velocity :: proc(
	ctx: rawptr,
	object: ^classes.Object,
) -> (
	datatypes.Vector3,
	bool,
) {
	physics, body := physics_hook_body(ctx, object)
	if physics == nil {
		_, angular, ok := physics_hook_remote_velocity(ctx, object)
		return angular, ok
	}
	velocity: kineffi.JPH_Vec3
	kineffi.JPH_BodyInterface_GetAngularVelocity(
		physics.system.body_interface,
		body.body_id,
		&velocity,
	)
	return datatypes.Vector3{f64(velocity.x), f64(velocity.y), f64(velocity.z)}, true
}

physics_hook_set_angular_velocity :: proc(
	ctx: rawptr,
	object: ^classes.Object,
	value: datatypes.Vector3,
) {
	physics, body := physics_hook_body(ctx, object)
	if physics == nil {return}
	velocity := kineffi.JPH_Vec3{f32(value.x), f32(value.y), f32(value.z)}
	kineffi.JPH_BodyInterface_SetAngularVelocity(
		physics.system.body_interface,
		body.body_id,
		&velocity,
	)
	kineffi.JPH_BodyInterface_ActivateBody(physics.system.body_interface, body.body_id)
}

physics_hook_apply_impulse :: proc(
	ctx: rawptr,
	object: ^classes.Object,
	impulse: datatypes.Vector3,
) -> bool {
	physics, body := physics_hook_body(ctx, object)
	if physics == nil {return false}
	part := cast(^classes.Part)object
	if part.material == .Water {return false}
	physics_update_body_material(physics, body, part.material)
	value := kineffi.JPH_Vec3{f32(impulse.x), f32(impulse.y), f32(impulse.z)}
	kineffi.JPH_BodyInterface_AddImpulse(physics.system.body_interface, body.body_id, &value)
	kineffi.JPH_BodyInterface_ActivateBody(physics.system.body_interface, body.body_id)
	return true
}

physics_hook_apply_angular_impulse :: proc(
	ctx: rawptr,
	object: ^classes.Object,
	impulse: datatypes.Vector3,
) -> bool {
	physics, body := physics_hook_body(ctx, object)
	if physics == nil ||
	   (cast(^classes.Part)object).anchored ||
	   (cast(^classes.Part)object).material == .Water {return false}
	value := kineffi.JPH_Vec3{f32(impulse.x), f32(impulse.y), f32(impulse.z)}
	kineffi.JPH_BodyInterface_AddAngularImpulse(
		physics.system.body_interface,
		body.body_id,
		&value,
	)
	kineffi.JPH_BodyInterface_ActivateBody(physics.system.body_interface, body.body_id)
	return true
}

physics_hook_apply_impulse_at_position :: proc(
	ctx: rawptr,
	object: ^classes.Object,
	impulse, position: datatypes.Vector3,
) -> bool {
	physics, body := physics_hook_body(ctx, object)
	if physics == nil ||
	   (cast(^classes.Part)object).anchored ||
	   (cast(^classes.Part)object).material == .Water {return false}
	value := kineffi.JPH_Vec3{f32(impulse.x), f32(impulse.y), f32(impulse.z)}
	point := kineffi.JPH_RVec3{position.x, position.y, position.z}
	kineffi.JPH_BodyInterface_AddImpulse2(
		physics.system.body_interface,
		body.body_id,
		&value,
		&point,
	)
	kineffi.JPH_BodyInterface_ActivateBody(physics.system.body_interface, body.body_id)
	return true
}

physics_hook_get_mass :: proc(ctx: rawptr, object: ^classes.Object) -> f64 {
	if object == nil {return 0}
	part := cast(^classes.Part)object
	physics := physics_hook_service(ctx)
	if physics == nil || !physics.initialized {return 0}
	if index := physics_find_body_index(physics, object); index >= 0 {
		body := &physics.bodies[index]
		if body.motion_properties != nil {
			inverse := kineffi.JPH_MotionProperties_GetInverseMass(body.motion_properties)
			if inverse > 0 {return 1 / f64(inverse)}
		}
	}
	shape := physics_shape_for_part(physics, part)
	if shape == nil {return 0}
	defer kineffi.JPH_Shape_Destroy(shape)
	properties := jolt.Material_Get_Properties(part.material)
	return f64(kineffi.JPH_Shape_GetVolume(shape)) * f64(properties.density)
}

physics_hook_can_collide_with :: proc(ctx: rawptr, object, other: ^classes.Object) -> bool {
	if object == nil || other == nil || object == other {return false}
	a, b := cast(^classes.Part)object, cast(^classes.Part)other
	if !a.can_collide || !b.can_collide {return false}
	registry := cast(^Registry)ctx
	if registry == nil {return false}
	if descriptor := classes.Find_Class(registry.classes, "NoCollisionConstraint");
	   descriptor != nil {
		for candidate in descriptor.instances {
			if candidate == nil || candidate.destroyed {continue}
			c := cast(^classes.NoCollisionConstraint)candidate
			if !c.enabled ||
			   !((c.part0 == object && c.part1 == other) ||
					   (c.part1 == object && c.part0 == other)) {continue}
			for parent := candidate.parent; parent != nil; parent = parent.parent {
				if classes.Is_A(parent, "Workspace") {return false}
			}
		}
	}
	groups := physics_service_groups_for(registry.data_model)
	ga := max(physics_service_group_id(groups, a.collision_group), 0)
	gb := max(physics_service_group_id(groups, b.collision_group), 0)
	return groups == nil || !groups.noncolliding[ga][gb]
}


physics_hook_billboard_occluded :: proc(
	ctx: rawptr,
	part: ^classes.Object,
	origin, target: datatypes.Vector3,
) -> bool {
	physics := physics_hook_service(ctx)
	if physics == nil || !physics.initialized || part == nil {return false}
	workspace := part
	for workspace != nil && !classes.Is_A(workspace, "Workspace") {workspace = workspace.parent}
	if workspace == nil {return false}
	direction := datatypes.Vec3_Subtract(target, origin)
	if datatypes.Vec3_Magnitude(direction) < 0.001 {return false}
	params := datatypes.RaycastParams {
		FilterType        = .Exclude,
		BruteForceAllSlow = true,
		ExcludeFilterSet  = true,
	}
	defer delete(params.ExcludeInstances)
	append(&params.ExcludeInstances, datatypes.Raycast_Instance_Reference{object = rawptr(part)})

	for body in physics.bodies {
		object := body.object
		if object != nil && (cast(^classes.Part)object).transparency >= 0.99 {
			append(
				&params.ExcludeInstances,
				datatypes.Raycast_Instance_Reference{object = rawptr(object)},
			)
		}
	}
	_, hit := Physics_Raycast(physics, workspace, origin, direction, &params, false)
	return hit
}

Install_Part_Body_Access :: proc(registry: ^Registry) {
	if registry == nil || registry.classes == nil {return}
	registry.classes.billboard_occluded = physics_hook_billboard_occluded
	classes.Set_Part_Body_Access(
		registry.classes,
		classes.Part_Body_Access {
			get_linear_velocity = physics_hook_get_linear_velocity,
			set_linear_velocity = physics_hook_set_linear_velocity,
			get_angular_velocity = physics_hook_get_angular_velocity,
			set_angular_velocity = physics_hook_set_angular_velocity,
			apply_impulse = physics_hook_apply_impulse,
			get_mass = physics_hook_get_mass,
			can_collide_with = physics_hook_can_collide_with,
			apply_angular_impulse = physics_hook_apply_angular_impulse,
			apply_impulse_at_position = physics_hook_apply_impulse_at_position,
		},
		rawptr(registry),
	)
}
