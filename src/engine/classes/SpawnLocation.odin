package classes

import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"
import "core:strings"

SpawnLocation_Class := Class_Info {
	name   = "SpawnLocation",
	parent = &Part_Class,
}

SpawnLocation :: struct {
	using part: Part,
	enabled:    bool,
	neutral:    bool,
	duration:   f64,
}

spawn_location_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	spawn := new(SpawnLocation)
	spawn.part = Part_Init()
	spawn.object.class = &SpawnLocation_Class
	spawn.name = "SpawnLocation"
	spawn.anchored = true
	spawn.enabled = true
	spawn.neutral = true
	return &spawn.object
}

spawn_location_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	spawn := cast(^SpawnLocation)object
	if spawn.touched != nil &&
	   spawn.object.signal_registry != nil &&
	   spawn.object.signal_registry.signal_registry != nil {
		signals.Destroy(spawn.touched)
		spawn.touched = nil
	}
	if spawn.ownership_changed != nil &&
	   spawn.object.signal_registry != nil &&
	   spawn.object.signal_registry.signal_registry != nil {
		signals.Destroy(spawn.ownership_changed)
		spawn.ownership_changed = nil
	}
	delete(spawn.collision_group)
	delete(spawn.material_variant)
	Object_Destroy(object)
	free(spawn)
}

spawn_location_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	spawn := cast(^SpawnLocation)object
	switch key {
	case "Enabled":
		vm.PushBoolean(L, spawn.enabled)
	case "Neutral":
		vm.PushBoolean(L, spawn.neutral)
	case "Duration":
		vm.PushNumber(L, spawn.duration)
	case:
		return part_get(L, object, datatype_registry, enum_registry, key)
	}
	return true
}

spawn_location_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	spawn := cast(^SpawnLocation)object
	switch key {
	case "Enabled":
		spawn.enabled = vm.ArgBoolean(L, value_index)
	case "Neutral":
		spawn.neutral = vm.ArgBoolean(L, value_index)
	case "Duration":
		spawn.duration = vm.ArgNumber(L, value_index)
	case:
		return part_set(L, object, datatype_registry, enum_registry, key, value_index)
	}
	Hierarchy_Touched()
	return true
}

spawn_location_clone :: proc(source: ^Object, destination: ^Object) {
	part_clone(source, destination)
	src := cast(^SpawnLocation)source
	dst := cast(^SpawnLocation)destination
	dst.enabled = src.enabled
	dst.neutral = src.neutral
	dst.duration = src.duration
}

Register_SpawnLocation :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&SpawnLocation_Class,
		spawn_location_construct,
		spawn_location_destroy,
		get = spawn_location_get,
		set = spawn_location_set,
		clone = spawn_location_clone,
		properties = []string{"Enabled", "Neutral", "Duration"},
	)
}
