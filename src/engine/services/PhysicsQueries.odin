package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
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

// terrain_material_at_world reports the material of the voxel a ray stopped in,
// so a terrain hit answers with the surface the caller can actually see rather
// than a default. Air is the fallback for a hit that landed on the boundary
// between a filled voxel and empty space, where either answer is defensible.
terrain_material_at_world :: proc(service: ^Physics, position: datatypes.Vector3) -> enums.Material {
	if service.data_model == nil { return .Air }
	terrain := cast(^Terrain)DataModel_Get_Service(service.data_model, "Terrain")
	if terrain == nil { return .Air }
	x, y, z := terrain_cell_from_world(terrain, position)
	if cell, ok := terrain_get_cell(terrain, x, y, z); ok {
		return cell.material
	}
	return .Air
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
	// A ray that stops on terrain is still a hit, it just has no Instance behind
	// it. Terrain is the one thing in the world a ray can legitimately hit
	// without producing one, so scripts reading result.Instance have to nil-check
	// it here the same way they check it for a ray that hit nothing.
	if service.terrain_valid && native_result.bodyID == service.terrain_body {
		hit_position := datatypes.Vector3{f32(native_result.position.x), f32(native_result.position.y), f32(native_result.position.z)}
		result = datatypes.RaycastResult{
			Position    = hit_position,
			Normal      = {native_result.normal.x, native_result.normal.y, native_result.normal.z},
			Distance    = datatypes.Vec3_Magnitude(direction)*native_result.fraction,
			Material    = terrain_material_at_world(service, hit_position),
			InstanceRef = 0,
			ObjectRef   = nil,
		}
		return result, true
	}
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
		ObjectRef = part,
	}
	return result, true
}

