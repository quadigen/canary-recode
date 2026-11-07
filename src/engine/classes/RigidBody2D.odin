package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"

RigidBody2D_Class := Class_Info {
	name   = "RigidBody2D",
	parent = &Instance_Class,
}

RigidBody2D :: struct {
	using object: Object,
	pivot:        datatypes.CFrame,
	pivot_set:    bool,
}

RigidBody2D_Init :: proc() -> RigidBody2D {
	return RigidBody2D{object = Object_Init(&RigidBody2D_Class), pivot = datatypes.CFrame_Identity}
}

RigidBody2D_construct :: proc(renderer: ^Renderer_Object, data_RigidBody2D: rawptr) -> ^Object {
	corner := new(RigidBody2D)
	corner^ = RigidBody2D_Init()
	corner.name = "RigidBody2D"

	return &corner.object
}

RigidBody2D_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^RigidBody2D)object)
}

RigidBody2D_clone :: proc(source: ^Object, destination: ^Object) {
	src, dst := cast(^RigidBody2D)source, cast(^RigidBody2D)destination
	dst.pivot, dst.pivot_set = src.pivot, src.pivot_set
}

RigidBody2D_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "PivotTo", "GetPivot":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

RigidBody2D_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "PivotTo":
		return 0, true
	case "GetPivot":
		return 1, true
	}
	return 0, false
}

Register_RigidBody2D :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&RigidBody2D_Class,
		RigidBody2D_construct,
		RigidBody2D_destroy,
		clone = RigidBody2D_clone,
		get = RigidBody2D_get,
		namecall = RigidBody2D_namecall,
		methods = []string{"PivotTo", "GetPivot"},
	)
}
