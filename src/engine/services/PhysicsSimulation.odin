package services

import aero "../aerodynamics"
import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import jolt "../physics"
import tracy "../util/odin-tracy"

DEFAULT_COLLISION_SUBSTEPS :: 1

Physics_StepConstraints :: proc(object: ^classes.Object, service: ^Physics, delta_time: f32) {
	for child in object.children {
		if child == nil ||
		   child.destroyed ||
		   classes.Is_A_Class(child, &classes.ViewportFrame_Class) {continue}

		for entry in classes.Constraint_Steps {
			if classes.Is_A_Class(child, entry.class) {
				entry.step(child, service.system.handle, service.body_ids[:], delta_time)
				break
			}
		}
		if len(child.children) != 0 {
			Physics_StepConstraints(child, service, delta_time)
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
		aero.Apply_Body(service.system.handle, body.body_id, settings, body_options)
	}
}

Physics_Step :: proc(service: ^Physics, delta_time: f32) {
	if service == nil || !service.initialized {return}
	workspace := cast(^Workspace)Service_Get_Service(&service.service, "Workspace")

	if workspace == nil {return}

	if !workspace.simulate_physics {return}

	tracy.ZoneNC("Jolt Synchronize", 0xE06C75)
	Physics_Synchronize(service, workspace)
	// The hierarchy epoch doesn't change for interpolated poses. Update remote
	// colliders directly, so raycasts and local physics see the streamed pose.
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
	// Apply changed or reparented model gravity settings without rebuilding bodies.
	for &body in service.bodies {
		if body.object == nil ||
		   body.object.destroyed ||
		   body.anchored ||
		   body.remote ||
		   body.body_id == kineffi.JPH_BODY_ID_INVALID {continue}
		scale: f32 = 1
		if model := classes.PhysicsModel_For(body.object);
		   model != nil {scale = model.gravity_scale}
		if body.gravity_scale != scale {
			kineffi.JPH_BodyInterface_SetGravityFactor(
				service.system.body_interface,
				body.body_id,
				scale,
			)
			kineffi.JPH_BodyInterface_ActivateBody(service.system.body_interface, body.body_id)
			body.gravity_scale = scale
		}
	}
	Physics_Apply_Water(service, step_time)

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
		if !physics_finite_f32(f32(position.x)) ||
		   !physics_finite_f32(f32(position.y)) ||
		   !physics_finite_f32(f32(position.z)) ||
		   !physics_finite_f32(rotation.x) ||
		   !physics_finite_f32(rotation.y) ||
		   !physics_finite_f32(rotation.z) ||
		   !physics_finite_f32(rotation.w) {
			part.cframe = body.last_cframe
			continue
		}
		part.cframe = datatypes.CFrame_New_Quaternion(
			f32(position.x),
			f32(position.y),
			f32(position.z),
			rotation.x,
			rotation.y,
			rotation.z,
			rotation.w,
		)
		if !physics_valid_cframe(part.cframe) {
			part.cframe = body.last_cframe
			continue
		}
		part.position = datatypes.Vector3{part.cframe.x, part.cframe.y, part.cframe.z}
		body.last_cframe = part.cframe
		transform_written = true
		if workspace_service.fall_height_enabled &&
		   part.cframe.y < workspace_service.fallen_parts_destroy_height {
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
