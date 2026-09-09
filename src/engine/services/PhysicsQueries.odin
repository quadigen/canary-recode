package services

import classes "../classes"
import datatypes "../datatypes"
import jolt "../physics"
import kineffi "../bindings"

physics_filter_matches :: proc(object: ^classes.Object, filters: []datatypes.Raycast_Instance_Reference) -> bool {
	for filter in filters {
		root := cast(^classes.Object)filter.object
		if root != nil && (object == root || classes.Is_Descendant_Of(object, root)) { return true }
	}
	return false
}

physics_is_raycast_candidate :: proc(part: ^classes.Part, params: ^datatypes.RaycastParams) -> bool {
	if params == nil { return part.can_query }
	if !params.BruteForceAllSlow {
		if params.RespectCanCollide {
			if !part.can_collide { return false }
		} else if !part.can_query { return false }
	}
	object := &part.object
	if params.ExcludeFilterSet && physics_filter_matches(object, params.ExcludeInstances[:]) { return false }
	if params.IncludeFilterSet && !physics_filter_matches(object, params.IncludeInstances[:]) { return false }
	if params.LegacyFilterSet {
		matches := physics_filter_matches(object, params.FilterDescendantsInstances[:])
		if params.FilterType == .Exclude && matches { return false }
		if params.FilterType == .Include && !matches { return false }
	}
	return true
}

Physics_Raycast :: proc(service: ^Physics, workspace: ^classes.Object, origin, direction: datatypes.Vector3, params: ^datatypes.RaycastParams = nil) -> (result: datatypes.RaycastResult, hit: bool) {
	if service == nil || !service.initialized || datatypes.Vec3_Magnitude(direction) == 0 { return }
	Physics_Synchronize(service, workspace)
	candidates: [dynamic]kineffi.JPH_BodyID
	defer delete(candidates)
	for body in service.bodies {
		part := cast(^classes.Part)body.object
		if physics_is_raycast_candidate(part, params) { append(&candidates, body.body_id) }
	}
	if len(candidates) == 0 { return }
	native_result, did_hit := jolt.System_Cast_Ray(
		&service.system,
		kineffi.JPH_RVec3{f64(origin.x), f64(origin.y), f64(origin.z)},
		kineffi.JPH_Vec3{direction.x, direction.y, direction.z},
		candidates[:],
		.Include,
	)
	if !did_hit { return }
	body_index := -1
	for body, i in service.bodies { if body.body_id == native_result.bodyID { body_index = i; break } }
	if body_index < 0 { return }
	part := cast(^classes.Part)service.bodies[body_index].object
	result = datatypes.RaycastResult{
		Position = {f32(native_result.position.x), f32(native_result.position.y), f32(native_result.position.z)},
		Normal = {native_result.normal.x, native_result.normal.y, native_result.normal.z},
		Distance = datatypes.Vec3_Magnitude(direction)*native_result.fraction,
		Material = part.material,
		InstanceRef = part.lua_ref,
	}
	return result, true
}
