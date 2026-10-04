package services

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import jolt "../physics"
import vm "../vm"

Physics_Class := classes.Class_Info {
	name   = "Physics",
	parent = &Service_Class,
}

Physics_Body :: struct {
	object:                ^classes.Object,
	body_id:               kineffi.JPH_BodyID,
	size:                  datatypes.Vector3,
	shape:                 enums.PartType,
	anchored:              bool,
	remote:                bool,
	last_cframe:           datatypes.CFrame,
	mesh_id:               string,
	editable_mesh_id:      u32,
	editable_mesh_version: u64,
	collision_fidelity:    enums.CollisionFidelity,
}

Physics :: struct {
	using service:            Service,
	system:                   jolt.System,
	bodies:                   [dynamic]Physics_Body,
	body_to_part:             map[kineffi.JPH_BodyID]^classes.Part,
	contact_listener:         kineffi.JPH_ContactListenerRef,
	gravity:                  f32,
	pcd_cache:                map[Physics_Shape_Cache_Key]kineffi.JPH_ShapeRef,
	terrain_valid:            bool,
	terrain_body:             kineffi.JPH_BodyID,
	terrain_version:          u64,
	terrain_triangles:        int,
	collision_steps:          int,
	broadphase_dirty:         bool,
	scratch_parts:            [dynamic]^classes.Part,
	scratch_ray_candidates:   [dynamic]kineffi.JPH_BodyID,
	scratch_sweep_candidates: [dynamic]kineffi.JPH_BodyID,
	sync_epoch:               u64,
	synced_epoch:             u64,
	has_synced:               bool,
	sync_bumped:              bool,
	initialized:              bool,
}

MAX_COLLISION_SUBSTEPS :: 8

Physics_Shape_Cache_Key :: struct {
	mesh_id:               string,
	editable_mesh_id:      u32,
	editable_mesh_version: u64,
	size:                  datatypes.Vector3,
}

Physics_Set_Gravity :: proc(service: ^Physics, gravity: f32) {
	if service == nil {return}
	service.gravity = max(gravity, 0)
	jolt.System_Set_Gravity(&service.system, service.gravity)
}


Physics_Set_Collision_Substeps :: proc(service: ^Physics, substeps: int) {
	if service == nil {return}
	service.collision_steps = clamp(substeps, 1, MAX_COLLISION_SUBSTEPS)
}


MAX_SLEEP_THRESHOLD :: 2.0
MAX_SLEEP_DELAY :: 10.0


Physics_Set_Sleep_Threshold :: proc(service: ^Physics, velocity: f64) {
	if service == nil {return}
	value := f32(clamp(velocity, 0, MAX_SLEEP_THRESHOLD))
	solver := service.system.solver
	if solver.point_velocity_sleep_threshold == value {return}
	solver.point_velocity_sleep_threshold = value
	service.system.solver = solver
	jolt.System_Apply_Solver(&service.system, &solver)
}


Physics_Set_Sleep_Delay :: proc(service: ^Physics, seconds: f64) {
	if service == nil {return}
	value := f32(clamp(seconds, 0, MAX_SLEEP_DELAY))
	solver := service.system.solver
	if solver.time_before_sleep == value {return}
	solver.time_before_sleep = value
	service.system.solver = solver
	jolt.System_Apply_Solver(&service.system, &solver)
}

physics_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Physics)
	service.service = Service_Init(&Physics_Class, "Physics", data_model)
	service.gravity = 196.2
	service.pcd_cache = make(map[Physics_Shape_Cache_Key]kineffi.JPH_ShapeRef)
	service.collision_steps = DEFAULT_COLLISION_SUBSTEPS
	service.system, service.initialized = jolt.System_Create_3D()
	if service.initialized {
		jolt.System_Set_Gravity(&service.system, service.gravity)
		service.contact_listener = kineffi.JPH_ContactListener_Create()
		if service.contact_listener != nil {
			kineffi.JPH_PhysicsSystem_SetContactListener(
				service.system.handle,
				service.contact_listener,
			)
		}
	}
	return &service.object
}

physics_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^Physics)object

	for body in service.bodies {physics_destroy_body(service, body, false)}

	physics_destroy_terrain_body(service)
	delete(service.body_to_part)
	delete(service.bodies)

	delete(service.scratch_parts)
	delete(service.scratch_ray_candidates)
	delete(service.scratch_sweep_candidates)
	for _, shape in service.pcd_cache {
		kineffi.JPH_Shape_Destroy(shape)
	}
	delete(service.pcd_cache)
	jolt.System_Destroy_3D(&service.system)
	if service.contact_listener != nil {
		kineffi.JPH_ContactListener_Destroy(service.contact_listener)
		service.contact_listener = nil
	}
	classes.Object_Destroy(object)
	free(service)
}

physics_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^Physics)object
	switch key {
	case "Enabled":
		vm.PushBoolean(L, service.initialized)
	case "Gravity":
		vm.PushNumber(L, f64(service.gravity))
	case "BodyCount":
		vm.PushNumber(L, f64(len(service.bodies)))
	case "PhysicsThreadCount":
		vm.PushNumber(L, f64(jolt.System_Num_Threads(&service.system)))
	case "CollisionSubsteps":
		vm.PushNumber(L, f64(service.collision_steps))
	case "SleepThreshold":
		vm.PushNumber(L, f64(service.system.solver.point_velocity_sleep_threshold))
	case "SleepDelay":
		vm.PushNumber(L, f64(service.system.solver.time_before_sleep))
	case:
		return false
	}
	return true
}

physics_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	service := cast(^Physics)object
	switch key {
	case "Gravity":
		Physics_Set_Gravity(service, f32(vm.ArgNumber(L, value_index)))
		return true
	case "CollisionSubsteps":
		Physics_Set_Collision_Substeps(service, int(vm.ArgNumber(L, value_index)))
		return true
	case "SleepThreshold":
		Physics_Set_Sleep_Threshold(service, vm.ArgNumber(L, value_index))
		return true
	case "SleepDelay":
		Physics_Set_Sleep_Delay(service, vm.ArgNumber(L, value_index))
		return true
	case:
		return false
	}
	return true
}

Register_Physics_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Physics_Class,
		physics_construct,
		physics_destroy,
		creatable = false,
		get = physics_get,
		set = physics_set,
		properties = []string{
			"Enabled",
			"Gravity",
			"BodyCount",
			"PhysicsThreadCount",
			"CollisionSubsteps",
			"SleepThreshold",
			"SleepDelay",
		},
		events = []string{},
		methods = []string{},
	)
}
