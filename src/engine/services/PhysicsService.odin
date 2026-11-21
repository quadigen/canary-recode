package services


import ffi "../bindings"
import jolt "../physics"
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
	using service:    Service,
	collision_groups: [jolt.COLLISION_GROUP_COUNT]string,
	noncolliding:     [jolt.COLLISION_GROUP_COUNT][jolt.COLLISION_GROUP_COUNT]bool,
}

physics_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(PhysicsService)
	service.service = Service_Init(&PhysicsService_Class, "PhysicsService", data_model)
	service.collision_groups[0] = strings.clone("Default")
	return &service.object
}

physics_service_group_id :: proc(service: ^PhysicsService, name: string) -> int {
	if service == nil || name == "" {return -1}
	for group, i in service.collision_groups {if group == name {return i}}
	return -1
}

physics_service_has_group :: proc(service: ^PhysicsService, name: string) -> bool {
	return physics_service_group_id(service, name) >= 0
}

physics_service_groups_for :: proc(model: ^DataModel) -> ^PhysicsService {
	if model == nil || model.registry == nil {return nil}
	descriptor := Find_Service(model.registry, "PhysicsService")
	if descriptor == nil {return nil}
	return cast(^PhysicsService)descriptor.object
}

physics_group_layer :: proc(
	physics: ^Physics,
	part: ^classes.Part,
	moving: bool,
) -> ffi.JPH_ObjectLayer {
	id := physics_service_group_id(
		physics_service_groups_for(physics.data_model),
		part.collision_group,
	)
	return jolt.Group_Layer(max(id, 0), moving)
}

physics_group_apply_pair :: proc(physics: ^Physics, a, b: int, collide: bool) {
	if physics == nil || !physics.initialized {return}
	for a_index in 0 ..< 2 {
		for b_index in 0 ..< 2 {
			moving_a, moving_b := a_index != 0, b_index != 0
			if !moving_a && !moving_b {continue}
			la, lb := jolt.Group_Layer(a, moving_a), jolt.Group_Layer(b, moving_b)
			if collide {ffi.JPH_ObjectLayerPairFilterTable_EnableCollision(physics.system.object_pair_filter, la, lb)} else {
				ffi.JPH_ObjectLayerPairFilterTable_DisableCollision(
					physics.system.object_pair_filter,
					la,
					lb,
				)
			}
		}
	}
}

physics_group_physics :: proc(service: ^PhysicsService) -> ^Physics {
	if service.data_model == nil || service.data_model.registry == nil {return nil}
	d := Find_Service(service.data_model.registry, "Physics")
	if d == nil {return nil}
	return cast(^Physics)d.object
}

physics_groups_apply :: proc(physics: ^Physics) {
	groups := physics_service_groups_for(physics.data_model)
	if groups == nil {return}
	for a in 0 ..< len(groups.collision_groups) {
		for b in a ..< len(groups.collision_groups) {
			if groups.noncolliding[a][b] {physics_group_apply_pair(physics, a, b, false)}
		}
	}
}

physics_group_rename_parts :: proc(service: ^PhysicsService, old, new_name: string) {
	registry := service.signal_registry
	if registry == nil {return}
	for descriptor in registry.classes {
		if !classes.Is_Class_A(descriptor.info, &classes.BasePart_Class) ||
		   descriptor.info == &classes.BasePart_Class {continue}
		for object in descriptor.instances {
			if object == nil || object.destroyed {continue}
			part := cast(^classes.Part)object
			if part.collision_group == old {
				delete(part.collision_group)
				part.collision_group = strings.clone(new_name)
			}
		}
	}
	classes.Hierarchy_Touched()
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
	     "CollisionGroupSetCollidable",
	     "CollisionGroupsAreCollidable",
	     "GetMaxCollisionGroups",
	     "RenameCollisionGroup",
	     "UnregisterCollisionGroup",
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
	case "GetMaxCollisionGroups":
		vm.PushNumber(L, jolt.COLLISION_GROUP_COUNT)
		return 1, true
	case "CollisionGroupsAreCollidable", "CollisionGroupSetCollidable":
		a := physics_service_group_id(service, vm.ArgString(L, 2))
		b := physics_service_group_id(service, vm.ArgString(L, 3))
		if a < 0 || b < 0 {return vm.RaiseError(L, "unregistered collision group"), true}
		if method ==
		   "CollisionGroupsAreCollidable" {vm.PushBoolean(L, !service.noncolliding[a][b]); return 1, true}
		collide := vm.ArgBoolean(L, 4)
		service.noncolliding[a][b] = !collide
		service.noncolliding[b][a] = !collide
		physics_group_apply_pair(physics_group_physics(service), a, b, collide)
		return 0, true
	case "RenameCollisionGroup", "UnregisterCollisionGroup":
		name := vm.ArgString(L, 2)
		id := physics_service_group_id(service, name)
		if id <=
		   0 {return vm.RaiseError(L, "cannot modify default or unknown collision group"), true}
		new_name := "Default"
		if method == "RenameCollisionGroup" {
			new_name = vm.ArgString(L, 3)
			if new_name == "" ||
			   physics_service_has_group(
				   service,
				   new_name,
			   ) {return vm.RaiseError(L, "invalid collision group name"), true}
		}
		physics_group_rename_parts(service, name, new_name)
		delete(service.collision_groups[id])
		service.collision_groups[id] = ""
		if method ==
		   "RenameCollisionGroup" {service.collision_groups[id] = strings.clone(new_name)} else {
			for i in 0 ..< len(service.collision_groups) {
				service.noncolliding[id][i] = false
				service.noncolliding[i][id] = false
				physics_group_apply_pair(physics_group_physics(service), id, i, true)
			}
		}
		return 0, true
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
		index := 0
		for group in service.collision_groups {
			if group == "" {continue}
			index += 1
			vm.NewTable(L, 0, 1)
			vm.PushString(L, group)
			vm.SetField(L, -2, "name")
			vm.SetArrayValue(L, -2, index)
		}
		return 1, true
	case "RegisterCollisionGroup":
		name := vm.ArgString(L, 2)
		if name == "" {return vm.RaiseError(L, "collision group name must not be empty"), true}
		if !physics_service_has_group(service, name) {
			for &group in service.collision_groups {
				if group ==
				   "" {group = strings.clone(name); classes.Hierarchy_Touched(); return 0, true}
			}
			return vm.RaiseError(L, "collision group limit reached"), true
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
	classes.Object_Destroy(object)
	free(service)
}

physics_service_parallel_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "IsCollisionGroupDefault",
	     "CollisionGroupExists",
	     "IsCollisionGroupRegistered",
	     "GetRegisteredCollisionGroups",
	     "CollisionGroupsAreCollidable",
	     "GetMaxCollisionGroups":
		return physics_service_get(L, object, d, e, key)
	}
	return false
}

physics_service_parallel_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "IsCollisionGroupDefault",
	     "CollisionGroupExists",
	     "IsCollisionGroupRegistered",
	     "GetRegisteredCollisionGroups",
	     "CollisionGroupsAreCollidable",
	     "GetMaxCollisionGroups":
		return physics_service_namecall(L, object, d, e, method)
	}
	return 0, false
}

Register_PhysicsService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&PhysicsService_Class,
		physics_service_construct,
		physics_service_destroy,
		creatable = false,
		get = physics_service_get,
		parallel_get = physics_service_parallel_get,
		namecall = physics_service_namecall,
		parallel_namecall = physics_service_parallel_namecall,
		properties = []string {
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
		methods = []string {
			"IsCollisionGroupRegistered",
			"GetRegisteredCollisionGroups",
			"RegisterCollisionGroup",
			"CollisionGroupSetCollidable",
			"CollisionGroupsAreCollidable",
			"GetMaxCollisionGroups",
			"RenameCollisionGroup",
			"UnregisterCollisionGroup",
		},
	)
}
