package services


import "core:strings"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

PhysicsService_Class := classes.Class_Info {
	name   = "PhysicsService",
	parent = &Service_Class,
}

PhysicsService :: struct {
	using service: Service,
}

physics_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(PhysicsService)
	service.service = Service_Init(&PhysicsService_Class, "PhysicsService", data_model)
	return &service.object
}

physics_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "IsCollisionGroupDefault",
	     "IsCollisionGroupDoesNotCollide",
	     "IsCollisionGroupNotCollide",
	     "IsCollisionGroupNotCollideWith",
	     "CollisionGroupExists",
	     "Raycast",
	     "RaycastParams",
	     "OverlapParams":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

physics_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "IsCollisionGroupDefault",
	     "IsCollisionGroupDoesNotCollide",
	     "IsCollisionGroupNotCollide",
	     "IsCollisionGroupNotCollideWith":
		vm.PushBoolean(L, false)
		return 1, true
	case "CollisionGroupExists":
		vm.PushBoolean(L, false)
		return 1, true
	case "Raycast", "RaycastParams", "OverlapParams":
		vm.NewTable(L, 0, 0)
		return 1, true
	}
	return 0, false
}

physics_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^PhysicsService)object)
}

Register_PhysicsService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&PhysicsService_Class,
		physics_service_construct,
		physics_service_destroy,
		creatable = false,
		get = physics_service_get,
		namecall = physics_service_namecall,
		properties = []string{
			"IsCollisionGroupDefault",
			"IsCollisionGroupDoesNotCollide",
			"IsCollisionGroupNotCollide",
			"IsCollisionGroupNotCollideWith",
			"CollisionGroupExists",
			"Raycast",
			"RaycastParams",
			"OverlapParams",
		},
		events = []string{},
		methods = []string{},
	)
}
