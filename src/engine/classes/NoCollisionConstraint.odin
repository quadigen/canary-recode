package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

NoCollisionConstraint_Class := Class_Info {
	name   = "NoCollisionConstraint",
	parent = &Instance_Class,
}

NoCollisionConstraint :: struct {
	using object:    Object,
	part0, part1:    ^Object,
	enabled, active: bool,
}

NoCollisionConstraint_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	c := new(NoCollisionConstraint)
	c.object = Object_Init(&NoCollisionConstraint_Class, "NoCollisionConstraint")
	c.enabled = true
	return &c.object
}

NoCollisionConstraint_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^NoCollisionConstraint)object)
}

NoCollisionConstraint_get :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
) -> bool {
	c := cast(^NoCollisionConstraint)object
	switch key {
	case "Part0":
		Push_Object(L, c.part0)
	case "Part1":
		Push_Object(L, c.part1)
	case "Enabled":
		vm.PushBoolean(L, c.enabled)
	case "Active":
		vm.PushBoolean(L, c.active)
	case:
		return false
	}
	return true
}

NoCollisionConstraint_set :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	c := cast(^NoCollisionConstraint)object
	switch key {
	case "Part0", "Part1":
		part := Object_From_Argument(L, index)
		if !vm.IsNil(L, index) && (part == nil || !Is_A_Class(part, &Part_Class)) {return false}
		if key == "Part0" {c.part0 = part} else {c.part1 = part}
	case "Enabled":
		c.enabled = vm.ArgBoolean(L, index)
	case:
		return false
	}
	c.active = false
	return true
}

NoCollisionConstraint_clone :: proc(source, destination: ^Object) {
	src, dst := cast(^NoCollisionConstraint)source, cast(^NoCollisionConstraint)destination
	dst.part0, dst.part1, dst.enabled = src.part0, src.part1, src.enabled
}

Register_NoCollisionConstraint :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&NoCollisionConstraint_Class,
		NoCollisionConstraint_construct,
		NoCollisionConstraint_destroy,
		get = NoCollisionConstraint_get,
		set = NoCollisionConstraint_set,
		clone = NoCollisionConstraint_clone,
		properties = []string{"Part0", "Part1", "Enabled", "Active"},
	)
}
