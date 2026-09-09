package main

import "core:fmt"
import kineffi "../src/engine/bindings"
import physics "../src/engine/physics"

main :: proc() {
	assert(kineffi.JPH_BODY_ID_INVALID == 0xffffffff)
	assert(i32(kineffi.JPH_MotionType.Static) == 0)
	assert(i32(kineffi.JPH_MotionType.Kinematic) == 1)
	assert(i32(kineffi.JPH_MotionType.Dynamic) == 2)
	assert(i32(kineffi.JPH_ActivationMode.Activate) == 0)
	assert(i32(kineffi.JPH_ActivationMode.DontActivate) == 1)
	assert(u32(kineffi.JPH_SpringMode.MassNormalizedStiffnessAndDamping) == 2)
	assert(i32(kineffi.JPH_MotorState.PositionAndVelocity) == 3)
	assert(u32(kineffi.JPH_SixDOFAxis.RotationZ) == 5)

	system, ok := physics.System_Create()
	assert(ok)
	defer physics.System_Destroy(&system)

	assert(system.handle != nil)
	assert(system.body_interface != nil)
	assert(kineffi.JPH_ObjectLayerPairFilterTable_ShouldCollide(
		system.object_pair_filter,
		physics.OBJECT_LAYER_NON_MOVING,
		physics.OBJECT_LAYER_NON_MOVING,
	) == 0)
	assert(kineffi.JPH_ObjectLayerPairFilterTable_ShouldCollide(
		system.object_pair_filter,
		physics.OBJECT_LAYER_NON_MOVING,
		physics.OBJECT_LAYER_MOVING,
	) == 1)
	assert(kineffi.JPH_ObjectLayerPairFilterTable_ShouldCollide(
		system.object_pair_filter,
		physics.OBJECT_LAYER_MOVING,
		physics.OBJECT_LAYER_MOVING,
	) == 0)
	assert(kineffi.JPH_ObjectVsBroadPhaseLayerFilterTable_ShouldCollide(
		system.object_vs_broad_filter,
		physics.OBJECT_LAYER_NON_MOVING,
		physics.BROAD_PHASE_LAYER_MOVING,
	) == 1)
	assert(kineffi.JPH_ObjectVsBroadPhaseLayerFilterTable_ShouldCollide(
		system.object_vs_broad_filter,
		physics.OBJECT_LAYER_MOVING,
		physics.BROAD_PHASE_LAYER_NON_MOVING,
	) == 1)

	half_extent := kineffi.JPH_Vec3{0.5, 0.5, 0.5}
	shape := kineffi.JPH_BoxShape_Create(&half_extent, 0.05)
	assert(shape != nil)
	defer kineffi.JPH_Shape_Destroy(shape)

	position := kineffi.JPH_RVec3{0, 2, 0}
	rotation := kineffi.JPH_Quat{0, 0, 0, 1}
	body_settings := kineffi.JPH_BodyCreationSettings_Create3(
		shape,
		&position,
		&rotation,
		.Dynamic,
		physics.OBJECT_LAYER_MOVING,
	)
	assert(body_settings != nil)
	body := kineffi.JPH_BodyInterface_CreateBody(system.body_interface, body_settings)
	kineffi.JPH_BodyCreationSettings_Destroy(body_settings)
	assert(body != nil)

	body_id := kineffi.JPH_Body_GetID(body)
	assert(body_id != kineffi.JPH_BODY_ID_INVALID)
	kineffi.JPH_BodyInterface_AddBody(system.body_interface, body_id, .Activate)
	assert(kineffi.JPH_BodyInterface_IsAdded(system.body_interface, body_id) == 1)
	physics.System_Step(&system, 1.0/60.0)
	stepped_position: kineffi.JPH_RVec3
	kineffi.JPH_BodyInterface_GetPosition(system.body_interface, body_id, &stepped_position)
	assert(stepped_position.y < position.y)
	kineffi.JPH_BodyInterface_RemoveAndDestroyBody(system.body_interface, body_id)

	fmt.println("JOLT_BINDINGS_SMOKE_PASSED")
}
