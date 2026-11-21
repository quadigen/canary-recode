package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

World2D_Class := Class_Info {
	name   = "World2D",
	parent = &Instance_Class,
}

World2D :: struct {
	using object: Object,
	enabled:      bool,
}

World2D_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	world := new(World2D)
	world.object = Object_Init(&World2D_Class)
	world.name = "World2D"
	world.enabled = true
	return &world.object
}

World2D_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^World2D)object)
}

World2D_get :: proc(
	L: ^vm.State,
	object: ^Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	key: string,
) -> bool {
	if key != "Enabled" {return false}
	vm.PushBoolean(L, (cast(^World2D)object).enabled)
	return true
}
World2D_set :: proc(
	L: ^vm.State,
	object: ^Object,
	dr: ^datatypes.Registry,
	er: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	if key != "Enabled" {return false}
	(cast(^World2D)object).enabled = vm.ArgBoolean(L, index)
	return true
}
World2D_clone :: proc(src, dst: ^Object) {
	(cast(^World2D)dst).enabled = (cast(^World2D)src).enabled
}
Register_World2D :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&World2D_Class,
		World2D_construct,
		World2D_destroy,
		get = World2D_get,
		set = World2D_set,
		clone = World2D_clone,
		properties = []string{"Enabled"},
	)
}
