package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import "core:math"
import "core:math/linalg"

ROPE_TUBE_SIDES :: 12
ROPE_TUBE_STRIDE :: ROPE_TUBE_SIDES + 1

Rope_Points :: [kineffi.JPH_ROPE_MAX_POINTS]kineffi.JPH_RVec3
Rope_Vertices :: [kineffi.JPH_ROPE_MAX_POINTS * ROPE_TUBE_STRIDE][8]f32
Rope_Indices :: [(kineffi.JPH_ROPE_MAX_POINTS - 1) * ROPE_TUBE_SIDES * 6 + (ROPE_TUBE_SIDES - 2) * 6]u32

rope_draw_endpoint :: proc(object, root: ^Object) -> (kineffi.JPH_RVec3, bool) {
	if object == nil || object.destroyed || !Is_A_Class(object, &Attachment_Class) {return {}, false}
	parent := object.parent
	if parent == nil || parent.destroyed || !Is_A_Class(parent, &Part_Class) ||
	   !Is_Descendant_Of(parent, root) {return {}, false}
	attachment := cast(^Attachment)object
	part := cast(^Part)parent
	point := datatypes.CFrame_PointToWorldSpace(part.cframe, attachment.position)
	world := kineffi.JPH_RVec3{f64(point.x), f64(point.y), f64(point.z)}
	return world, rope_valid_point(world)
}

RopeConstraint_Points :: proc(rope: ^RopeConstraint, root: ^Object, points: ^Rope_Points) -> int {
	if !rope.enabled || root == nil {return 0}
	start, start_ok := rope_draw_endpoint(rope.attachment0, root)
	end, end_ok := rope_draw_endpoint(rope.attachment1, root)
	if !start_ok || !end_ok {return 0}
	count := int(kineffi.JPH_Rope_GetPoints(rope.jolt_rope, &points[0], len(points)))
	if count == 0 {
		count = int(kineffi.JPH_Rope_GetRestPoints(&start, &end, rope.length, &points[0], len(points)))
	}
	if count < 2 {return 0}
	points[0], points[count - 1] = start, end
	for point in points[:count] {if !rope_valid_point(point) {return 0}}
	return count
}

rope_direction :: proc(value, fallback: [3]f32) -> [3]f32 {
	length := linalg.length(value)
	return value / length if length > 1e-6 else fallback
}

Rope_Build_Tube :: proc(points: []kineffi.JPH_RVec3, radius: f32, vertices: ^Rope_Vertices, indices: ^Rope_Indices) -> int {
	centers: [kineffi.JPH_ROPE_MAX_POINTS][3]f32
	for p, i in points {centers[i] = {f32(p.x), f32(p.y), f32(p.z)}}
	sides :: ROPE_TUBE_SIDES
	stride :: ROPE_TUBE_STRIDE
	up, tangent := [3]f32{0, 1, 0}, [3]f32{1, 0, 0}
	distance: f32
	for i in 0 ..< len(points) {
		p := centers[i]
		previous, next := max(0, i - 1), min(len(points) - 1, i + 1)
		if i > 0 {distance += linalg.length(p - centers[previous])}
		tangent = rope_direction(centers[next] - centers[previous], tangent)
		// Transport the ring frame along the centerline so it doesn't flip as the rope swings.
		normal := up - tangent * linalg.dot(up, tangent)
		if linalg.dot(normal, normal) < 1e-6 {
			axis := [3]f32{1, 0, 0} if abs(tangent.x) < 0.8 else [3]f32{0, 0, 1}
			normal = axis - tangent * linalg.dot(axis, tangent)
		}
		up = linalg.normalize(normal)
		across := linalg.cross(tangent, up)
		for side in 0 ..= sides {
			u := f32(side) / sides
			angle := 2 * f32(math.PI) * u
			radial := up * math.cos(angle) + across * math.sin(angle)
			v := distance / max(4 * radius, 0.04)
			position := p + radial * (radius * (0.98 + 0.02 * math.cos(3 * angle - 2 * f32(math.PI) * v)))
			vertices[i * stride + side] = {position.x, position.y, position.z, radial.x, radial.y, radial.z, u, v}
		}
	}

	count := 0
	for ring in 0 ..< len(points) - 1 {
		for side in 0 ..< sides {
			a := u32(ring * stride + side)
			b, c := a + 1, a + stride
			copy(indices[count:count + 6], []u32{a, b, c, b, c + 1, c})
			count += 6
		}
	}
	last := u32((len(points) - 1) * stride)
	for side in u32(1) ..< sides - 1 {
		copy(indices[count:count + 6], []u32{0, side + 1, side, last, last + side, last + side + 1})
		count += 6
	}
	return count
}

RopeConstraint_Release_Mesh :: proc(rope: ^RopeConstraint) {
	if rope.mesh != nil {
		kineffi.Kine_Filament_DestroyMesh(rope.mesh_context, rope.mesh)
		rope.mesh = nil
	}
	rope.mesh_context = nil
	rope.mesh_point_count = 0
}

RopeConstraint_Draw_Item :: proc(rope: ^RopeConstraint, root: ^Object, ctx: ^kineffi.KineFilamentContext) -> (kineffi.KineFilamentDrawItem, bool) {
	if !rope.visible || ctx == nil {return {}, false}
	points: Rope_Points
	count := RopeConstraint_Points(rope, root, &points)
	if count == 0 {return {}, false}
	radius := rope.thickness * 0.5
	if rope.mesh_context != ctx || rope.mesh_point_count != count {RopeConstraint_Release_Mesh(rope)}
	if rope.mesh == nil || rope.mesh_radius != radius || rope.mesh_points != points {
		vertices: Rope_Vertices
		indices: Rope_Indices
		local_points := points
		for &p in local_points[:count] {p.x -= points[0].x; p.y -= points[0].y; p.z -= points[0].z}
		index_count := Rope_Build_Tube(local_points[:count], radius, &vertices, &indices)
		vertex_count := i32(count * ROPE_TUBE_STRIDE)
		if rope.mesh == nil {
			rope.mesh = kineffi.Kine_Filament_CreateCustomMesh32(ctx, &vertices[0][0], vertex_count, &indices[0], i32(index_count))
			if rope.mesh == nil {return {}, false}
			rope.mesh_context = ctx
			rope.mesh_point_count = count
		} else if !kineffi.Kine_Filament_UpdateCustomMesh(ctx, rope.mesh, &vertices[0][0], vertex_count) {
			return {}, false
		}
		rope.mesh_points = points
		rope.mesh_radius = radius
		rope.mesh_revision += 1
	}
	return kineffi.KineFilamentDrawItem {
		mesh = rope.mesh,
		transform = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1},
		r = 0.54, g = 0.39, b = 0.24,
		param1 = 0.88, param3 = 1,
		flags = kineffi.KINE_FILAMENT_DRAW_CAST_SHADOWS | kineffi.KINE_FILAMENT_DRAW_RECEIVE_SHADOWS | kineffi.KINE_FILAMENT_DRAW_WORLD_POSITION,
		worldPosition = {points[0].x, points[0].y, points[0].z},
	}, true
}
