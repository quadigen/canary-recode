package services

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import vm "../vm"

Workspace_Query_Box :: struct {
	center: datatypes.Vector3,
	axes:   [3]datatypes.Vector3,
	half:   [3]f32,
}

workspace_contains_physics_object :: proc(workspace, object: ^classes.Object) -> bool {
	for node := object; node != nil; node = node.parent {
		if node == workspace {return true}
		if classes.Is_A_Class(node, &classes.ViewportFrame_Class) {return false}
	}
	return false
}

workspace_query_box :: proc(cf: datatypes.CFrame, size: datatypes.Vector3) -> Workspace_Query_Box {
	return Workspace_Query_Box {
		center = datatypes.CFrame_Position(cf),
		axes = {
			datatypes.CFrame_RightVector(cf),
			datatypes.CFrame_UpVector(cf),
			datatypes.CFrame_ZVector(cf),
		},
		half = {size.x * 0.5, size.y * 0.5, size.z * 0.5},
	}
}

workspace_box_projection :: proc(box: Workspace_Query_Box, axis: datatypes.Vector3) -> f32 {
	radius: f32
	for basis, i in box.axes {
		radius += box.half[i] * abs(datatypes.Vec3_Dot(basis, axis))
	}
	return radius
}

workspace_boxes_overlap :: proc(a, b: Workspace_Query_Box) -> bool {
	// Test the face normals and the axes perpendicular to each pair of edges.
	delta := datatypes.Vec3_Subtract(b.center, a.center)
	axes: [15]datatypes.Vector3
	for axis_a, i in a.axes {
		axes[i] = axis_a
		axes[i + 3] = b.axes[i]
		for axis_b, j in b.axes {
			axes[6 + 3 * i + j] = datatypes.Vec3_Cross(axis_a, axis_b)
		}
	}
	for axis in axes {
		if abs(datatypes.Vec3_Dot(delta, axis)) >
		   workspace_box_projection(a, axis) + workspace_box_projection(b, axis) {
			return false
		}
	}
	return true
}

workspace_box_overlaps_sphere :: proc(
	box: Workspace_Query_Box,
	center: datatypes.Vector3,
	radius: f32,
) -> bool {
	delta := datatypes.Vec3_Subtract(center, box.center)
	distance_squared: f64
	for axis, i in box.axes {
		distance := f64(max(abs(datatypes.Vec3_Dot(delta, axis)) - box.half[i], 0))
		distance_squared += distance * distance
	}
	return distance_squared <= f64(radius) * f64(radius)
}

workspace_optional_overlap_params :: proc(
	L: ^vm.State,
	index: int,
	registry: ^datatypes.Registry,
) -> ^datatypes.OverlapParams {
	if vm.IsNoneOrNil(L, index) {return nil}
	return datatypes.Arg_OverlapParams(L, index, registry)
}

workspace_get_part_bounds :: proc(
	L: ^vm.State,
	workspace: ^classes.Object,
	registry: ^datatypes.Registry,
	in_box: bool,
) -> i32 {
	box: Workspace_Query_Box
	center: datatypes.Vector3
	radius: f32
	if in_box {
		cf := datatypes.Arg_CFrame(L, 2, registry)
		size := datatypes.Arg_Vector3(L, 3)
		if !physics_valid_cframe(cf) ||
		   !physics_finite_f32(size.x) ||
		   !physics_finite_f32(size.y) ||
		   !physics_finite_f32(size.z) ||
		   size.x < 0 ||
		   size.y < 0 ||
		   size.z < 0 {
			return vm.RaiseError(L, "expected a finite CFrame and nonnegative box size")
		}
		box = workspace_query_box(cf, size)
	} else {
		center = datatypes.Arg_Vector3(L, 2)
		radius = f32(vm.ArgNumber(L, 3))
		if !physics_finite_f32(center.x) ||
		   !physics_finite_f32(center.y) ||
		   !physics_finite_f32(center.z) ||
		   !physics_finite_f32(radius) ||
		   radius < 0 {
			return vm.RaiseError(L, "expected a finite center and nonnegative radius")
		}
	}
	params := workspace_optional_overlap_params(L, 4, registry)
	limit := 0
	if params != nil {
		limit = int(params.MaxParts)
		radius += params.Tolerance
		for &half in box.half {half += params.Tolerance}
	}

	parts: [dynamic]^classes.Part
	defer delete(parts)
	physics_collect_parts(workspace, &parts)
	replicator := cast(^ReplicatorService)Service_Get_Service(
		&(cast(^Workspace)workspace).service,
		"ReplicatorService",
	)
	vm.NewTable(L)
	count := 0
	for part in parts {
		if !physics_is_query_candidate(part, params) ||
		   replication_part_awaiting_transform(replicator, part) ||
		   !classes.Object_Is_Accessible(L, &part.object) ||
		   part.lua_ref <= 0 ||
		   !physics_valid_cframe(part.cframe) {
			continue
		}
		bounds := workspace_query_box(part.cframe, part.size)
		overlaps :=
			in_box ? workspace_boxes_overlap(box, bounds) : workspace_box_overlaps_sphere(bounds, center, radius)
		if !overlaps {continue}
		count += 1
		classes.Push_Object(L, &part.object)
		vm.RawSetIndex(L, -2, count)
		if count == limit {break}
	}
	return 1
}

workspace_get_parts_in_part :: proc(
	L: ^vm.State,
	workspace: ^classes.Object,
	physics: ^Physics,
	registry: ^datatypes.Registry,
) -> i32 {
	object := classes.Object_From_Argument(L, 2)
	if object == nil ||
	   object.destroyed ||
	   !classes.Is_A_Class(object, &classes.Part_Class) ||
	   !workspace_contains_physics_object(workspace, object) {
		return vm.RaiseError(L, "expected a BasePart in this Workspace")
	}
	params := workspace_optional_overlap_params(L, 3, registry)
	vm.NewTable(L)
	if physics == nil || !physics.initialized {return 1}
	Physics_Synchronize(physics, workspace)

	candidates := &physics.scratch_ray_candidates
	physics_reset_scratch_ids(candidates)
	for body in physics.bodies {
		part := cast(^classes.Part)body.object
		if body.object != object &&
		   physics_is_query_candidate(part, params) &&
		   workspace_contains_physics_object(workspace, body.object) &&
		   classes.Object_Is_Accessible(L, body.object) &&
		   part.lua_ref > 0 {
			append(candidates, body.body_id)
		}
	}
	limit := len(candidates^)
	tolerance: f32
	if params != nil {
		tolerance = params.Tolerance
		if params.MaxParts > 0 {limit = min(limit, int(params.MaxParts))}
	}
	results := make([]kineffi.JPH_BodyID, limit)
	defer delete(results)
	for id, i in physics_overlap_part(physics, cast(^classes.Part)object, candidates[:], results, tolerance) {
		classes.Push_Object(L, &physics_part_for_body(physics, id).object)
		vm.RawSetIndex(L, -2, i + 1)
	}
	return 1
}
