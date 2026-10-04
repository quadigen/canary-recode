package services

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import jolt "../physics"
import tracy "../util/odin-tracy"

DEFAULT_COLLISION_SUBSTEPS :: 1

Physics_Step :: proc(service: ^Physics, delta_time: f32) {
	if service == nil || !service.initialized {return}
	workspace := cast(^Workspace)Service_Get_Service(&service.service, "Workspace")

	if workspace == nil {return}
	
	if !workspace.simulate_physics {return}

	tracy.ZoneNC("Jolt Synchronize", 0xE06C75)
	Physics_Synchronize(service, workspace)

	tracy.ZoneNC("Jolt Step", 0xE06C75)
	jolt.System_Step(&service.system, min(delta_time, 0.1), i32(service.collision_steps))

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
