package physics

import kineffi "../bindings"

OBJECT_LAYER_NON_MOVING :: kineffi.JPH_ObjectLayer(0)
OBJECT_LAYER_MOVING     :: kineffi.JPH_ObjectLayer(1)
OBJECT_LAYER_COUNT      :: u32(2)

BROAD_PHASE_LAYER_NON_MOVING :: kineffi.JPH_BroadPhaseLayer(0)
BROAD_PHASE_LAYER_MOVING     :: kineffi.JPH_BroadPhaseLayer(1)
BROAD_PHASE_LAYER_COUNT      :: u32(2)

System_Settings :: struct {
	max_bodies:              u32,
	num_body_mutexes:        u32,
	max_body_pairs:          u32,
	max_contact_constraints: u32,
}

DEFAULT_SYSTEM_SETTINGS :: System_Settings{
	max_bodies = 65_536,
	num_body_mutexes = 0,
	max_body_pairs = 65_536,
	max_contact_constraints = 65_536,
}

System :: struct {
	handle:                 kineffi.JPH_PhysicsSystemRef,
	body_interface:         kineffi.JPH_BodyInterfaceRef,
	broad_phase_interface:  kineffi.JPH_BroadPhaseLayerInterfaceRef,
	object_pair_filter:     kineffi.JPH_ObjectLayerPairFilterRef,
	object_vs_broad_filter: kineffi.JPH_ObjectVsBroadPhaseLayerFilterRef,
	initialized:            bool,
}

System_Create_3D :: proc(config := DEFAULT_SYSTEM_SETTINGS) -> (result: System, ok: bool) {
	if kineffi.JPH_Init() == 0 {
		return
	}
	result.initialized = true

	result.object_pair_filter = kineffi.JPH_ObjectLayerPairFilterTable_Create(OBJECT_LAYER_COUNT)
	if result.object_pair_filter == nil {
		System_Destroy_3D(&result)
		return
	}

	kineffi.JPH_ObjectLayerPairFilterTable_EnableCollision(
		result.object_pair_filter,
		OBJECT_LAYER_NON_MOVING,
		OBJECT_LAYER_MOVING,
	)
	kineffi.JPH_ObjectLayerPairFilterTable_EnableCollision(
		result.object_pair_filter,
		OBJECT_LAYER_MOVING,
		OBJECT_LAYER_NON_MOVING,
	)

	result.broad_phase_interface = kineffi.JPH_BroadPhaseLayerInterfaceTable_Create(
		OBJECT_LAYER_COUNT,
		BROAD_PHASE_LAYER_COUNT,
	)
	if result.broad_phase_interface == nil {
		System_Destroy_3D(&result)
		return
	}
	kineffi.JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(
		result.broad_phase_interface,
		OBJECT_LAYER_NON_MOVING,
		BROAD_PHASE_LAYER_NON_MOVING,
	)
	kineffi.JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(
		result.broad_phase_interface,
		OBJECT_LAYER_MOVING,
		BROAD_PHASE_LAYER_MOVING,
	)

	result.object_vs_broad_filter = kineffi.JPH_ObjectVsBroadPhaseLayerFilterTable_Create(
		result.broad_phase_interface,
		BROAD_PHASE_LAYER_COUNT,
		result.object_pair_filter,
		OBJECT_LAYER_COUNT,
	)
	if result.object_vs_broad_filter == nil {
		System_Destroy_3D(&result)
		return
	}

	settings := kineffi.JPH_PhysicsSystemSettings{
		maxBodies = config.max_bodies,
		numBodyMutexes = config.num_body_mutexes,
		maxBodyPairs = config.max_body_pairs,
		maxContactConstraints = config.max_contact_constraints,
		broadPhaseLayerInterface = result.broad_phase_interface,
		objectLayerPairFilter = result.object_pair_filter,
		objectVsBroadPhaseLayerFilter = result.object_vs_broad_filter,
	}
	result.handle = kineffi.JPH_PhysicsSystem_Create(&settings)
	if result.handle == nil {
		System_Destroy_3D(&result)
		return
	}

	result.body_interface = kineffi.JPH_PhysicsSystem_GetBodyInterface(result.handle)
	if result.body_interface == nil {
		System_Destroy_3D(&result)
		return
	}

	ok = true
	return
}

System_Destroy_3D :: proc(system: ^System) {
	if system == nil {
		return
	}
	if system.handle != nil {
		kineffi.JPH_PhysicsSystem_Destroy(system.handle)
	}
	if system.object_vs_broad_filter != nil {
		kineffi.JPH_ObjectVsBroadPhaseLayerFilterTable_Destroy(system.object_vs_broad_filter)
	}
	if system.object_pair_filter != nil {
		kineffi.JPH_ObjectLayerPairFilterTable_Destroy(system.object_pair_filter)
	}
	if system.broad_phase_interface != nil {
		kineffi.JPH_BroadPhaseLayerInterfaceTable_Destroy(system.broad_phase_interface)
	}
	if system.initialized {
		kineffi.JPH_Shutdown()
	}

	system^ = System{}
}

System_Set_Gravity :: proc(system: ^System, gravity: f32) {
	if system == nil || system.handle == nil { return }
	value := kineffi.JPH_Vec3{0, -gravity, 0}
	kineffi.JPH_PhysicsSystem_SetGravity(system.handle, &value)
}

System_Step :: proc(system: ^System, delta_time: f32, collision_steps: i32 = 1) {
	if system == nil || system.handle == nil || delta_time <= 0 { return }
	kineffi.JPH_PhysicsSystem_UpdateSingleThreaded(system.handle, delta_time, collision_steps)
}

System_Cast_Ray :: proc(
	system: ^System,
	origin: kineffi.JPH_RVec3,
	direction: kineffi.JPH_Vec3,
	body_ids: []kineffi.JPH_BodyID = nil,
	filter_mode: kineffi.JPH_RayFilterMode = .None,
) -> (result: kineffi.JPH_RayCastResult, hit: bool) {
	if system == nil || system.handle == nil { return }
	native_origin := origin
	native_direction := direction
	ids: ^kineffi.JPH_BodyID
	if len(body_ids) > 0 { ids = raw_data(body_ids) }
	hit = kineffi.JPH_PhysicsSystem_CastRay(
		system.handle,
		&native_origin,
		&native_direction,
		ids,
		u32(len(body_ids)),
		filter_mode,
		&result,
	) != 0
	return
}

// Compatibility names for callers that do not need to distinguish 2D and 3D physics.
System_Create :: proc(config := DEFAULT_SYSTEM_SETTINGS) -> (System, bool) {
	return System_Create_3D(config)
}

System_Destroy :: proc(system: ^System) {
	System_Destroy_3D(system)
}

