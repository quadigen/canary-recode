package physics

import kineffi "../bindings"

OBJECT_LAYER_NON_MOVING :: kineffi.JPH_ObjectLayer(0)
OBJECT_LAYER_MOVING :: kineffi.JPH_ObjectLayer(1)
OBJECT_LAYER_COUNT :: u32(2)

BROAD_PHASE_LAYER_NON_MOVING :: kineffi.JPH_BroadPhaseLayer(0)
BROAD_PHASE_LAYER_MOVING :: kineffi.JPH_BroadPhaseLayer(1)
BROAD_PHASE_LAYER_COUNT :: u32(2)

System_Settings :: struct {
	max_bodies:              u32,
	num_body_mutexes:        u32,
	max_body_pairs:          u32,
	max_contact_constraints: u32,
	num_threads:             u32,
	solver:                  kineffi.JPH_PhysicsSettings,
	observe_threads:         bool,
}

default_job_system_threads :: proc() -> u32 {
	when ODIN_OS == .JS {
		return 1
	} else {
		return max(kineffi.JPH_Get_Num_Cores(), 2) - 1
	}
}

DEFAULT_SOLVER_SETTINGS :: kineffi.JPH_PhysicsSettings {
	num_velocity_steps             = 10,
	num_position_steps             = 2,
	speculative_contact_distance   = 0.02,
	min_velocity_for_restitution   = 1.0,
	point_velocity_sleep_threshold = 4,
	time_before_sleep              = 0.25,
	allow_sleeping                 = 1,
}

DEFAULT_SYSTEM_SETTINGS :: System_Settings {
	max_bodies              = 65_536,
	num_body_mutexes        = 0,
	max_body_pairs          = 65_536,
	max_contact_constraints = 65_536,
	num_threads             = 0,
	solver                  = DEFAULT_SOLVER_SETTINGS,
	observe_threads         = false,
}

System :: struct {
	handle:                 kineffi.JPH_PhysicsSystemRef,
	body_interface:         kineffi.JPH_BodyInterfaceRef,
	job_system:             kineffi.JPH_JobSystemRef,
	num_threads:            u32,
	solver:                 kineffi.JPH_PhysicsSettings,
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
		OBJECT_LAYER_MOVING,
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

	settings := kineffi.JPH_PhysicsSystemSettings {
		maxBodies                     = config.max_bodies,
		numBodyMutexes                = config.num_body_mutexes,
		maxBodyPairs                  = config.max_body_pairs,
		maxContactConstraints         = config.max_contact_constraints,
		broadPhaseLayerInterface      = result.broad_phase_interface,
		objectLayerPairFilter         = result.object_pair_filter,
		objectVsBroadPhaseLayerFilter = result.object_vs_broad_filter,
	}
	result.handle = kineffi.JPH_PhysicsSystem_Create(&settings)
	if result.handle == nil {
		System_Destroy_3D(&result)
		return
	}


	solver := config.solver
	result.solver = solver
	kineffi.JPH_PhysicsSystem_SetPhysicsSettings(result.handle, &solver)

	result.body_interface = kineffi.JPH_PhysicsSystem_GetBodyInterface(result.handle)
	if result.body_interface == nil {
		System_Destroy_3D(&result)
		return
	}


	result.num_threads =
		config.num_threads == 0 ? default_job_system_threads() : config.num_threads
	job_config := kineffi.JPH_JobSystemConfig {
		maxConcurrency = result.num_threads,
		observeThreads = config.observe_threads ? 1 : 0,
	}
	result.job_system = kineffi.JPH_JobSystemThreadPool_Create(&job_config)
	if result.job_system == nil {
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


	if system.job_system != nil {
		kineffi.JPH_JobSystem_Destroy(system.job_system)
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
	if system == nil || system.handle == nil {return}
	value := kineffi.JPH_Vec3{0, -gravity, 0}
	kineffi.JPH_PhysicsSystem_SetGravity(system.handle, &value)
}


System_Step :: proc(system: ^System, delta_time: f32, collision_steps: i32 = 1) {
	if system == nil || system.handle == nil || delta_time <= 0 {return}
	steps := max(collision_steps, 1)
	if system.job_system != nil {
		kineffi.JPH_PhysicsSystem_Update(system.handle, delta_time, steps, system.job_system)
		return
	}


	kineffi.JPH_PhysicsSystem_UpdateSingleThreaded(system.handle, delta_time, steps)
}


System_Apply_Solver :: proc(system: ^System, solver: ^kineffi.JPH_PhysicsSettings) {
	if system == nil || system.handle == nil || solver == nil {return}
	system.solver = solver^
	kineffi.JPH_PhysicsSystem_SetPhysicsSettings(system.handle, solver)
}


System_Solver :: proc(system: ^System) -> kineffi.JPH_PhysicsSettings {
	if system == nil {return DEFAULT_SOLVER_SETTINGS}
	return system.solver
}

System_Num_Threads :: proc(system: ^System) -> int {
	if system == nil || system.job_system == nil {return 1}
	return int(system.num_threads)
}


System_Observed_Threads :: proc(system: ^System) -> int {
	if system == nil || system.job_system == nil {return 0}
	return int(kineffi.JPH_JobSystem_Get_Observed_Thread_Count(system.job_system))
}

System_Cast_Ray :: proc(
	system: ^System,
	origin: kineffi.JPH_RVec3,
	direction: kineffi.JPH_Vec3,
	body_ids: []kineffi.JPH_BodyID = nil,
	filter_mode: kineffi.JPH_RayFilterMode = .None,
) -> (
	result: kineffi.JPH_RayCastResult,
	hit: bool,
) {
	if system == nil || system.handle == nil {return}
	native_origin := origin
	native_direction := direction
	ids: ^kineffi.JPH_BodyID
	if len(body_ids) > 0 {ids = raw_data(body_ids)}
	hit =
		kineffi.JPH_PhysicsSystem_CastRay(
			system.handle,
			&native_origin,
			&native_direction,
			ids,
			u32(len(body_ids)),
			filter_mode,
			&result,
		) !=
		0
	return
}

System_Cast_Shape :: proc(
	system: ^System,
	origin: kineffi.JPH_RVec3,
	displacement: kineffi.JPH_Vec3,
	shape: kineffi.JPH_ShapeRef,
	candidate_bodies: []kineffi.JPH_BodyID = nil,
	filter_mode: kineffi.JPH_RayFilterMode = .None,
	max_distance: f32 = 1000,
) -> (
	result: kineffi.JPH_RayCastResult,
	hit: bool,
) {
	if system == nil || system.handle == nil || shape == nil {return}
	native_origin := origin
	native_displacement := displacement
	ids: ^kineffi.JPH_BodyID
	if len(candidate_bodies) > 0 {ids = raw_data(candidate_bodies)}
	hit =
		kineffi.JPH_PhysicsSystem_CastShape(
			system.handle,
			&native_origin,
			&native_displacement,
			shape,
			ids,
			u32(len(candidate_bodies)),
			filter_mode,
			max_distance,
			&result,
		) !=
		0
	if hit {
		result.normal = kineffi.JPH_Vec3{-result.normal.x, -result.normal.y, -result.normal.z}
	}
	return
}

System_Create :: proc(config := DEFAULT_SYSTEM_SETTINGS) -> (System, bool) {
	return System_Create_3D(config)
}

System_Destroy :: proc(system: ^System) {
	System_Destroy_3D(system)
}
