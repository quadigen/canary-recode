package services

// wire:service

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import profiling "../profiling"
import vm "../vm"

Stats_Class := classes.Class_Info {
	name   = "Stats",
	parent = &Service_Class,
}

stats_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Service)
	service^ = Service_Init(&Stats_Class, "Stats", data_model)
	return &service.object
}

stats_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^Service)object)
}

stats_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	types: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	if key != "GetTotalMemoryUsageMb" {return false}
	vm.PushUserdataMethod(L, key)
	return true
}

stats_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	types: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	if method != "GetTotalMemoryUsageMb" {return 0, false}
	// Use the Luau heap for this runtime, which is available on every target.
	vm.PushNumber(L, f64(profiling.heap_bytes(L)) / (1024 * 1024))
	return 1, true
}

Register_Stats_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Stats_Class,
		stats_construct,
		stats_destroy,
		creatable = false,
		get = stats_get,
		namecall = stats_namecall,
		methods = []string{"GetTotalMemoryUsageMb"},
	)
}
