package services

import aero "../aerodynamics"
import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import jolt "../physics"
import tracy "../util/odin-tracy"

DEFAULT_COLLISION_SUBSTEPS :: 1

Physics_Cached_Constraint :: struct {
	object: ^classes.Object,
	step:   classes.Constraint_Step,
}


physics_collect_constraint_steps :: proc(
	object: ^classes.Object,
	steps: ^[dynamic]Physics_Cached_Constraint,
) {
	for child in object.children {
		if child == nil ||
		   child.destroyed ||
		   classes.Is_A_Class(child, &classes.ViewportFrame_Class) {continue}
		if classes.Is_A_Class(child, &classes.Constraint_Class) {
			for entry in classes.Constraint_Steps {
				if classes.Is_A_Class(child, entry.class) {
					append(steps, Physics_Cached_Constraint{child, entry.step})
					break
				}
			}
		}
		if len(child.children) != 0 {physics_collect_constraint_steps(child, steps)}
	}
}

Physics_StepConstraints :: proc(object: ^classes.Object, service: ^Physics, delta_time: f32) {
	if object == nil || service == nil {return}
	epoch := classes.Hierarchy_Structure_Epoch()
	if service.constraint_workspace != object || service.constraint_epoch != epoch {
		clear(&service.constraint_steps)
		physics_collect_constraint_steps(object, &service.constraint_steps)
		service.constraint_workspace = object
		service.constraint_epoch = epoch
	}
	for entry in service.constraint_steps {
		if !entry.object.destroyed {
			entry.step(entry.object, service.system.handle, service.body_ids[:], delta_time)
		}
	}
}

Physics_Apply_Aerodynamics :: proc(
	service: ^Physics,
	workspace: ^Workspace,
	aerodynamics: ^Aerodynamics,
	delta_time: f32,
) {
	if service == nil ||
	   !service.initialized ||
	   workspace == nil ||
	   aerodynamics == nil ||
	   !aerodynamics.enabled ||
	   delta_time <= 0 {
		return
	}

	settings := Aerodynamics_Settings(aerodynamics, workspace)
	options := Aerodynamics_Options(aerodynamics)

	for &body in service.bodies {
		if body.body_id == kineffi.JPH_BODY_ID_INVALID || body.anchored || body.remote {
			continue
		}

		body_options := options
		if model := classes.PhysicsModel_For(body.object); model != nil {
			if !model.aerodynamics_enabled {continue}
			body_options.drag_coefficient *= model.drag_multiplier
			body_options.profile_drag *= model.drag_multiplier
			body_options.wave_drag *= model.drag_multiplier
			body_options.lift_multiplier *= model.lift_multiplier
		}
		inverse_mass: f32
		if body.motion_properties != nil {
			inverse_mass = kineffi.JPH_MotionProperties_GetInverseMass(body.motion_properties)
		}
		aero.Apply_Body(
			service.system.handle,
			body.body_id,
			settings,
			body_options,
			delta_time,
			inverse_mass,
		)
	}
}


physics_part_gravity :: proc(part: ^classes.Part) -> datatypes.Vector3 {
	gravity := part.gravity
	if model := classes.PhysicsModel_For(&part.object); model != nil {
		gravity = datatypes.Vector3 {
			gravity.x * f64(model.gravity_scale),
			gravity.y * f64(model.gravity_scale),
			gravity.z * f64(model.gravity_scale),
		}
	}
	return gravity
}

physics_part_gravity_factor :: proc(service: ^Physics, gravity: datatypes.Vector3) -> f32 {
	if service.gravity <= 0 {return 0}
	factor := -gravity.y / f64(service.gravity)
	return f32(physics_finite_f32(f32(factor)) ? factor : 0)
}

physics_apply_part_gravity :: proc(service: ^Physics) {
	bi := service.system.body_interface
	for &body in service.bodies {
		if body.object == nil ||
		   body.object.destroyed ||
		   body.anchored ||
		   body.remote ||
		   body.body_id == kineffi.JPH_BODY_ID_INVALID {continue}
		physics_update_body_speed_limit(&body)
		gravity := physics_part_gravity(cast(^classes.Part)body.object)
		factor := physics_part_gravity_factor(service, gravity)
		if body.gravity_factor != factor {
			kineffi.JPH_BodyInterface_SetGravityFactor(bi, body.body_id, factor)
			body.gravity_factor = factor
		}
		if body.gravity != gravity {
			body.gravity = gravity
			kineffi.JPH_BodyInterface_ActivateBody(bi, body.body_id)
		}
		remaining := datatypes.Vector3 {
			gravity.x,
			gravity.y + f64(factor * service.gravity),
			gravity.z,
		}
		if remaining.x == 0 && abs(remaining.y) < 0.00001 && remaining.z == 0 {continue}


		if kineffi.JPH_BodyInterface_IsActive(bi, body.body_id) == 0 ||
		   body.motion_properties == nil {continue}
		inverse_mass := kineffi.JPH_MotionProperties_GetInverseMass(body.motion_properties)
		if inverse_mass <= 0 || !physics_finite_f32(inverse_mass) {continue}
		force := kineffi.JPH_Vec3 {
			f32(remaining.x / f64(inverse_mass)),
			f32(remaining.y / f64(inverse_mass)),
			f32(remaining.z / f64(inverse_mass)),
		}
		if physics_finite_f32(force.x) &&
		   physics_finite_f32(force.y) &&
		   physics_finite_f32(force.z) {
			kineffi.JPH_BodyInterface_AddForce(bi, body.body_id, &force)
		}
	}
}

Physics_Step :: proc(service: ^Physics, delta_time: f32) {
	if service == nil || !service.initialized {return}
	workspace := cast(^Workspace)Service_Get_Service(&service.service, "Workspace")

	if workspace == nil {return}

	if !workspace.simulate_physics {return}

	tracy.ZoneNC("Jolt Synchronize", 0xE06C75)
	Physics_Synchronize(service, workspace)


	for &body in service.bodies {
		if body.object == nil ||
		   body.object.destroyed ||
		   !body.remote ||
		   body.body_id == kineffi.JPH_BODY_ID_INVALID {continue}
		part := cast(^classes.Part)body.object
		if body.last_cframe == part.cframe || !physics_valid_cframe(part.cframe) {continue}
		position := kineffi.JPH_RVec3{f64(part.cframe.x), f64(part.cframe.y), f64(part.cframe.z)}
		rotation := physics_quaternion_from_cframe(part.cframe)
		kineffi.JPH_BodyInterface_SetPositionAndRotation(
			service.system.body_interface,
			body.body_id,
			&position,
			&rotation,
			.DontActivate,
		)
		body.last_cframe = part.cframe
	}
	step_time := min(delta_time, 0.1)
	physics_collect_character_capsules(service, workspace)
	physics_prepare_softbodies(service, workspace, step_time)

	tracy.ZoneNC("Step Constraints", 0xE06C75)
	if descriptor := classes.Find_Class(service.signal_registry, "HingeConstraint");
	   descriptor != nil {
		for object in descriptor.instances {
			if object != nil && !classes.Is_Descendant_Of(object, workspace) {
				classes.HingeConstraint_release(cast(^classes.HingeConstraint)object)
			}
		}
	}
	if descriptor := classes.Find_Class(service.signal_registry, "SpringConstraint");
	   descriptor != nil {
		for object in descriptor.instances {
			if object != nil && !classes.Is_Descendant_Of(object, workspace) {
				classes.SpringConstraint_release(cast(^classes.SpringConstraint)object)
			}
		}
	}
	if descriptor := classes.Find_Class(service.signal_registry, "RopeConstraint");
	   descriptor != nil {
		for object in descriptor.instances {
			rope := cast(^classes.RopeConstraint)object
			if rope != nil &&
			   rope.jolt_system == service.system.handle &&
			   !workspace_contains_physics_object(workspace, object) {
				classes.RopeConstraint_release(rope)
			}
		}
	}
	for class in classes.Attachment_Joint_Classes {
		descriptor := classes.Find_Class(service.signal_registry, class.name)
		if descriptor == nil {continue}
		for object in descriptor.instances {
			if object != nil && !classes.Is_Descendant_Of(object, workspace) {
				classes.Attachment_Joint_release(cast(^classes.Attachment_Joint)object)
			}
		}
	}
	Physics_StepConstraints(workspace, service, clamp(delta_time, 0, 0.1))
	physics_sync_weld_groups(service, &workspace.object)
	physics_sync_excluded_pairs(service, &workspace.object)
	Physics_Apply_Water(service, step_time)
	if step_time > 0 {physics_apply_part_gravity(service)}

	if aerodynamics := cast(^Aerodynamics)Service_Get_Service(&service.service, "Aerodynamics");
	   aerodynamics != nil && aerodynamics.enabled {
		tracy.ZoneNC("Aerodynamics", 0x61AFEF)
		Physics_Apply_Aerodynamics(service, workspace, aerodynamics, step_time)
	}

	tracy.ZoneNC("Jolt Step", 0xE06C75)
	jolt.System_Step(&service.system, step_time, i32(service.collision_steps))
	physics_read_softbodies(service)

	tracy.ZoneNC("Jolt Drain", 0xE06C75)
	Physics_Drain_Contacts(service)
	workspace_service := cast(^Workspace)workspace
	workspace_service.distributed_game_time += f64(max(delta_time, 0))

	tracy.ZoneNC("Jolt Replicate CFrame", 0xE06C75)
	transform_written := false
	for &body in service.bodies {
		part := cast(^classes.Part)body.object

		if part == nil || body.body_id == kineffi.JPH_BODY_ID_INVALID {continue}
		if part.anchored || body.remote {continue}
		position: kineffi.JPH_RVec3
		rotation: kineffi.JPH_Quat
		kineffi.JPH_BodyInterface_GetPositionAndRotation(
			service.system.body_interface,
			body.body_id,
			&position,
			&rotation,
		)
		if !physics_finite_f64(position.x) ||
		   !physics_finite_f64(position.y) ||
		   !physics_finite_f64(position.z) ||
		   !physics_finite_f32(rotation.x) ||
		   !physics_finite_f32(rotation.y) ||
		   !physics_finite_f32(rotation.z) ||
		   !physics_finite_f32(rotation.w) {
			part.cframe = body.last_cframe
			continue
		}
		part.cframe = datatypes.CFrame_New_Quaternion(
			position.x,
			position.y,
			position.z,
			f64(rotation.x),
			f64(rotation.y),
			f64(rotation.z),
			f64(rotation.w),
		)
		if !physics_valid_cframe(part.cframe) {
			part.cframe = body.last_cframe
			continue
		}
		part.position = datatypes.Vector3{part.cframe.x, part.cframe.y, part.cframe.z}
		body.last_cframe = part.cframe
		transform_written = true
		if workspace_service.fall_height_enabled &&
		   part.cframe.y < f64(workspace_service.fallen_parts_destroy_height) {
			classes.Destroy_Hierarchy(&part.object)
		}
	}
	if transform_written {
		Physics_Part_Transform_Applied()
	}
	Physics_Step_Cloth(service, workspace_service, delta_time)
	physics_drain_deformable_contacts(service)
}

Physics_Get_Num_Awake_Parts :: proc(service: ^Physics) -> int {
	if service == nil || !service.initialized {return 0}
	count := 0
	for body in service.bodies {
		if !body.anchored &&
		   kineffi.JPH_BodyInterface_IsActive(service.system.body_interface, body.body_id) !=
			   0 {count += 1}
	}
	return count
}
