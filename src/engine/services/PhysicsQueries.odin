package services

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import jolt "../physics"
import tracy "../util/odin-tracy"

physics_filter_matches :: proc(
	object: ^classes.Object,
	filters: []datatypes.Raycast_Instance_Reference,
) -> bool {
	for filter in filters {
		root := cast(^classes.Object)filter.object
		if root != nil && (object == root || classes.Is_Descendant_Of(object, root)) {return true}
	}
	return false
}

physics_is_raycast_candidate :: proc(
	part: ^classes.Part,
	params: ^datatypes.RaycastParams,
) -> bool {
	if params == nil {return part.can_query}
	if !params.BruteForceAllSlow {
		if params.RespectCanCollide {
			if !part.can_collide {return false}
		} else if !part.can_query {return false}
	}
	object := &part.object
	if params.ExcludeFilterSet &&
	   physics_filter_matches(object, params.ExcludeInstances[:]) {return false}
	if params.IncludeFilterSet &&
	   !physics_filter_matches(object, params.IncludeInstances[:]) {return false}
	if params.LegacyFilterSet {
		matches := physics_filter_matches(object, params.FilterDescendantsInstances[:])
		if params.FilterType == .Exclude && matches {return false}
		if params.FilterType == .Include && !matches {return false}
	}
	return true
}


terrain_material_at_world :: proc(
	service: ^Physics,
	position: datatypes.Vector3,
) -> enums.Material {
	if service.data_model == nil {return .Air}
	terrain := cast(^Terrain)DataModel_Get_Service(service.data_model, "Terrain")
	if terrain == nil {return .Air}
	x, y, z := terrain_cell_from_world(terrain, position)
	if cell, ok := terrain_get_cell(terrain, x, y, z); ok {
		return cell.material
	}
	return .Air
}

Physics_Raycast :: proc(
	service: ^Physics,
	workspace: ^classes.Object,
	origin, direction: datatypes.Vector3,
	params: ^datatypes.RaycastParams = nil,
) -> (
	result: datatypes.RaycastResult,
	hit: bool,
) {
	if service == nil || !service.initialized || datatypes.Vec3_Magnitude(direction) == 0 {return}
	Physics_Synchronize(service, workspace)


	candidates := &service.scratch_ray_candidates
	physics_reset_scratch_ids(candidates)
	// Terrain is a single aggregate body rather than a Part, so it cannot come
	// from the loop below. It has to be added explicitly or a terrain-only world
	// (no Parts at all) produces an empty candidate set and every ray misses the
	// one surface that is actually there.
	if service.terrain_valid && service.terrain_body != kineffi.JPH_BODY_ID_INVALID {
		append(candidates, service.terrain_body)
	}
	for body in service.bodies {
		part := cast(^classes.Part)body.object
		if physics_is_raycast_candidate(part, params) {append(candidates, body.body_id)}
	}
	if len(candidates^) == 0 {return}

	tracy.ZoneNC("Jolt Raycast", 0xE06C75)
	native_result, did_hit := jolt.System_Cast_Ray(
		&service.system,
		kineffi.JPH_RVec3{f64(origin.x), f64(origin.y), f64(origin.z)},
		kineffi.JPH_Vec3{direction.x, direction.y, direction.z},
		candidates[:],
		.Include,
	)
	if !did_hit {return}


	if service.terrain_valid && native_result.bodyID == service.terrain_body {
		hit_position := datatypes.Vector3 {
			f32(native_result.position.x),
			f32(native_result.position.y),
			f32(native_result.position.z),
		}
		result = datatypes.RaycastResult {
			Position    = hit_position,
			Normal      = {native_result.normal.x, native_result.normal.y, native_result.normal.z},
			Distance    = datatypes.Vec3_Magnitude(direction) * native_result.fraction,
			Material    = terrain_material_at_world(service, hit_position),
			InstanceRef = 0,
			ObjectRef   = nil,
		}
		return result, true
	}


	part := physics_part_for_body(service, native_result.bodyID)
	if part == nil {return}
	result = datatypes.RaycastResult {
		Position    = {
			f32(native_result.position.x),
			f32(native_result.position.y),
			f32(native_result.position.z),
		},
		Normal      = {native_result.normal.x, native_result.normal.y, native_result.normal.z},
		Distance    = datatypes.Vec3_Magnitude(direction) * native_result.fraction,
		Material    = part.material,
		InstanceRef = part.lua_ref,
		ObjectRef   = part,
	}
	return result, true
}
