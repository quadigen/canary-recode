package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import jolt "../physics"
import kineffi "../bindings"
import vm "../vm"

Physics_Class := classes.Class_Info{
	name = "Physics",
	parent = &Service_Class,
}

Physics_Body :: struct {
	object:      ^classes.Object,
	body_id:     kineffi.JPH_BodyID,
	size:        datatypes.Vector3,
	shape:       enums.PartType,
	anchored:    bool,
	last_cframe: datatypes.CFrame,
	mesh_id:     string,
	collision_fidelity: enums.CollisionFidelity,
}

Physics :: struct {
	using service: Service,
	system:        jolt.System,
	bodies:        [dynamic]Physics_Body,
	body_to_part:  map[kineffi.JPH_BodyID]^classes.Part,
	contact_listener: kineffi.JPH_ContactListenerRef,
	gravity:       f32,
	pcd_cache:     map[Physics_Shape_Cache_Key]kineffi.JPH_ShapeRef,
	initialized:   bool,
}

Physics_Shape_Cache_Key :: struct {
	mesh_id: string,
	size:    datatypes.Vector3,
}

Physics_Set_Gravity :: proc(service: ^Physics, gravity: f32) {
	if service == nil { return }
	service.gravity = max(gravity, 0)
	jolt.System_Set_Gravity(&service.system, service.gravity)
}

physics_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	service := new(Physics)
	service.service = Service_Init(&Physics_Class, "Physics", data_model)
	service.gravity = 196.2
	service.pcd_cache = make(map[Physics_Shape_Cache_Key]kineffi.JPH_ShapeRef)
	service.system, service.initialized = jolt.System_Create_3D()
	if service.initialized {
		jolt.System_Set_Gravity(&service.system, service.gravity)
		service.contact_listener = kineffi.JPH_ContactListener_Create()
		if service.contact_listener != nil {
			kineffi.JPH_PhysicsSystem_SetContactListener(service.system.handle, service.contact_listener)
		}
	}
	return &service.object
}

physics_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^Physics)object
	for body in service.bodies { physics_destroy_body(service, body) }
	delete(service.body_to_part)
	delete(service.bodies)
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

physics_get :: proc(L: ^vm.State, object: ^classes.Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, key: string) -> bool {
	service := cast(^Physics)object
	switch key {
	case "Enabled": vm.PushBoolean(L, service.initialized)
	case "Gravity": vm.PushNumber(L, f64(service.gravity))
	case "BodyCount": vm.PushNumber(L, f64(len(service.bodies)))
	case: return false
	}
	return true
}

physics_set :: proc(L: ^vm.State, object: ^classes.Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, key: string, value_index: int) -> bool {
	service := cast(^Physics)object
	if key != "Gravity" { return false }
	Physics_Set_Gravity(service, f32(vm.ArgNumber(L, value_index)))
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
	)
}
