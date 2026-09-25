package main

import "core:fmt"
import kineffi "../src/engine/bindings"
import physics "../src/engine/physics"

cube_verts := [8]kineffi.JPH_Vec3{
	{-1, -1, -1},
	{ 1, -1, -1},
	{-1,  1, -1},
	{ 1,  1, -1},
	{-1, -1,  1},
	{ 1, -1,  1},
	{-1,  1,  1},
	{ 1,  1,  1},
}

cube_triangles := [36]u32{
	0, 2, 1, 1, 2, 3, // -Z
	4, 5, 6, 5, 7, 6, // +Z
	0, 1, 4, 1, 5, 4, // -Y
	2, 6, 3, 3, 6, 7, // +Y
	0, 4, 2, 2, 4, 6, // -X
	1, 3, 5, 3, 7, 5, // +X
}

// Two overlapping cubes: a concave union that V-HACD must split into
// multiple convex hulls. Second cube is anchored diagonally.
double_cube_verts := [16]kineffi.JPH_Vec3{
	{-1, -1, -1}, { 1, -1, -1}, {-1,  1, -1}, { 1,  1, -1},
	{-1, -1,  1}, { 1, -1,  1}, {-1,  1,  1}, { 1,  1,  1},
	{ 0,  0,  0}, { 2,  0,  0}, { 0,  2,  0}, { 2,  2,  0},
	{ 0,  0,  2}, { 2,  0,  2}, { 0,  2,  2}, { 2,  2,  2},
}

double_cube_triangles := []u32{
	0, 2, 1, 1, 2, 3,
	4, 5, 6, 5, 7, 6,
	0, 1, 4, 1, 5, 4,
	2, 6, 3, 3, 6, 7,
	0, 4, 2, 2, 4, 6,
	1, 3, 5, 3, 7, 5,
	8, 10, 9, 9, 10, 11,
	12, 13, 14, 13, 15, 14,
	8, 9, 12, 9, 13, 12,
	10, 14, 11, 11, 14, 15,
	8, 12, 10, 10, 12, 14,
	9, 11, 13, 11, 15, 13,
}

main :: proc() {
	system, ok := physics.System_Create()
	assert(ok)
	defer physics.System_Destroy(&system)

	scale := kineffi.JPH_Vec3{0.25, 0.25, 0.25}

	cube_compound := kineffi.JPH_VHACD_Compound_Create(
		raw_data(cube_verts[:]),
		u32(len(cube_verts)),
		raw_data(cube_triangles[:]),
		u32(len(cube_triangles)),
		&scale,
	)
	assert(cube_compound != nil)
	defer kineffi.JPH_Shape_Destroy(cube_compound)

	concave_compound := kineffi.JPH_VHACD_Compound_Create(
		raw_data(double_cube_verts[:]),
		u32(len(double_cube_verts)),
		raw_data(double_cube_triangles[:]),
		u32(len(double_cube_triangles)),
		&scale,
	)
	assert(concave_compound != nil)
	defer kineffi.JPH_Shape_Destroy(concave_compound)

	position := kineffi.JPH_RVec3{0, 4, 0}
	rotation := kineffi.JPH_Quat{0, 0, 0, 1}
	body_settings := kineffi.JPH_BodyCreationSettings_Create3(
		concave_compound,
		&position,
		&rotation,
		.Dynamic,
		physics.OBJECT_LAYER_MOVING,
	)
	assert(body_settings != nil)

	// C-ABI edge cases must be rejected, not crash.
	assert(kineffi.JPH_VHACD_Compound_Create(nil, 8, raw_data(cube_triangles[:]), 12, &scale) == nil)
	assert(kineffi.JPH_VHACD_Compound_Create(raw_data(cube_verts[:]), 8, nil, 12, &scale) == nil)
	assert(kineffi.JPH_VHACD_Compound_Create(raw_data(cube_verts[:]), 8, raw_data(cube_triangles[:]), 12, nil) == nil)

	body := kineffi.JPH_BodyInterface_CreateBody(system.body_interface, body_settings)
	kineffi.JPH_BodyCreationSettings_Destroy(body_settings)
	assert(body != nil)

	body_id := kineffi.JPH_Body_GetID(body)
	assert(body_id != kineffi.JPH_BODY_ID_INVALID)
	kineffi.JPH_BodyInterface_AddBody(system.body_interface, body_id, .Activate)
	for i in 0 ..< 30 {
		physics.System_Step(&system, 1.0/60.0)
	}
	stepped_position: kineffi.JPH_RVec3
	kineffi.JPH_BodyInterface_GetPosition(system.body_interface, body_id, &stepped_position)
	assert(stepped_position.y < position.y)
	kineffi.JPH_BodyInterface_RemoveAndDestroyBody(system.body_interface, body_id)

	fmt.println("PHYSICS_COLLIDER_SMOKE_PASSED")
}