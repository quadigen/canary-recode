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
}

Physics :: struct {
	using service: Service,
	system:        jolt.System,
	bodies:        [dynamic]Physics_Body,
	gravity:       f32,
	initialized:   bool,
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
	service.system, service.initialized = jolt.System_Create_3D()
	if service.initialized { jolt.System_Set_Gravity(&service.system, service.gravity) }
	return &service.object
}

physics_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^Physics)object
	for body in service.bodies { physics_destroy_body(service, body) }
	delete(service.bodies)
	jolt.System_Destroy_3D(&service.system)
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
