package classes

import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

RayValue_Class := Class_Info {
	name   = "RayValue",
	parent = &ValueBase_Class,
}

RayValue :: struct {
	using object: Object,
	value:        datatypes.Ray,
	changed:      ^signals.Signal,
}

RayValue_Init :: proc() -> RayValue {
	return RayValue {
		object = Object_Init(&RayValue_Class),
		value = datatypes.Ray {
			Origin = datatypes.Vector3{1, 0, 0},
			Direction = datatypes.Vector3{1, 0, 0},
		},
	}
}

RayValue_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(RayValue)
	value^ = RayValue_Init()
	value.name = "RayValue"
	return &value.object
}

RayValue_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	ValueBase_Destroy_Changed_Signal(&(cast(^RayValue)object).changed)
	Object_Destroy(object)
	free(cast(^RayValue)object)
}

RayValue_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	val := cast(^RayValue)object

	switch key {
	case "Changed":
		return ValueBase_Changed_Signal(L, object, &val.changed)
	case "Value":
		if datatype_registry == nil {return false}
		datatypes.Push_Ray(L, datatype_registry, val.value)
	case:
		return false
	}
	return true
}

RayValue_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	val := cast(^RayValue)object

	switch key {
	case "Value":
		if datatype_registry == nil {return false}
		new_value := datatypes.Arg_Ray(L, value_index, datatype_registry)
		if val.value == new_value {return true}
		val.value = new_value
		if val.changed != nil {
			datatypes.Push_Ray(L, datatype_registry, val.value)
			ValueBase_Fire_Changed(L, val.changed)
		}
	case:
		return false
	}
	return true
}

RayValue_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^RayValue)source
	dst := cast(^RayValue)destination

	dst.value = src.value
}

Register_RayValue :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&RayValue_Class,
		RayValue_construct,
		RayValue_destroy,
		get = RayValue_get,
		parallel_get = RayValue_get,
		set = RayValue_set,
		clone = RayValue_clone,
		properties = []string{"Value"},
	)
}
