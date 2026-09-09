package services

import classes "../classes"
import datatypes "../datatypes"
import jolt "../physics"
import kineffi "../bindings"

Physics_Step :: proc(service: ^Physics, delta_time: f32) {
	if service == nil || !service.initialized { return }
	workspace := Service_Get_Service(&service.service, "Workspace")
	if workspace == nil { return }
	Physics_Synchronize(service, workspace)
	jolt.System_Step(&service.system, min(delta_time, 0.1))
	workspace_service := cast(^Workspace)workspace
	workspace_service.distributed_game_time += f64(max(delta_time, 0))
	for &body in service.bodies {
		part := cast(^classes.Part)body.object
		if part.anchored { continue }
		position: kineffi.JPH_RVec3
		rotation: kineffi.JPH_Quat
		kineffi.JPH_BodyInterface_GetPositionAndRotation(service.system.body_interface, body.body_id, &position, &rotation)
		part.cframe = datatypes.CFrame_New_Quaternion(
			f32(position.x), f32(position.y), f32(position.z),
			rotation.x, rotation.y, rotation.z, rotation.w,
		)
		body.last_cframe = part.cframe
		if workspace_service.fall_height_enabled && part.cframe.y < workspace_service.fallen_parts_destroy_height {
			classes.Destroy_Hierarchy(&part.object)
		}
	}
}

Physics_Get_Num_Awake_Parts :: proc(service: ^Physics) -> int {
	if service == nil || !service.initialized { return 0 }
	count := 0
	for body in service.bodies {
		if !body.anchored && kineffi.JPH_BodyInterface_IsActive(service.system.body_interface, body.body_id) != 0 { count += 1 }
	}
	return count
}
