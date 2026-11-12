package services
// wire:service


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
	collision_groups: [dynamic]string,
}

physics_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(PhysicsService)
	service.service = Service_Init(&PhysicsService_Class, "PhysicsService", data_model)
	append(&service.collision_groups, strings.clone("Default"))
	return &service.object
}

physics_service_has_group :: proc(service: ^PhysicsService, name: string) -> bool {
	for group in service.collision_groups {
		if group == name {return true}
	}
	return false
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
	     "IsCollisionGroupRegistered",
	     "GetRegisteredCollisionGroups",
	     "RegisterCollisionGroup",
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
	service := cast(^PhysicsService)object
	switch method {
	case "IsCollisionGroupDefault":
		vm.PushBoolean(L, vm.ArgString(L, 2) == "Default")
		return 1, true
	case "IsCollisionGroupDoesNotCollide",
	     "IsCollisionGroupNotCollide",
	     "IsCollisionGroupNotCollideWith":
		vm.PushBoolean(L, false)
		return 1, true
	case "CollisionGroupExists", "IsCollisionGroupRegistered":
		vm.PushBoolean(L, physics_service_has_group(service, vm.ArgString(L, 2)))
		return 1, true
	case "GetRegisteredCollisionGroups":
		vm.NewTable(L, len(service.collision_groups))
		for group, index in service.collision_groups {
			vm.NewTable(L, 0, 1)
			vm.PushString(L, group)
			vm.SetField(L, -2, "name")
			vm.SetArrayValue(L, -2, index + 1)
		}
		return 1, true
	case "RegisterCollisionGroup":
		name := vm.ArgString(L, 2)
		if name == "" {return vm.RaiseError(L, "collision group name must not be empty"), true}
		if !physics_service_has_group(service, name) {
			append(&service.collision_groups, strings.clone(name))
		}
		return 0, true
	case "Raycast", "RaycastParams", "OverlapParams":
		vm.NewTable(L, 0, 0)
		return 1, true
	}
	return 0, false
}

physics_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^PhysicsService)object
	for group in service.collision_groups {delete(group)}
	delete(service.collision_groups)
	classes.Object_Destroy(object)
	free(service)
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
		methods = []string{"IsCollisionGroupRegistered", "GetRegisteredCollisionGroups", "RegisterCollisionGroup"},
	)
}
