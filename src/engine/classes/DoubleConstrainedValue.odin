package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

DoubleConstrainedValue_Class := Class_Info{
	name   = "DoubleConstrainedValue",
	parent = &ValueBase_Class,
}

DoubleConstrainedValue :: struct {
	using object: Object,

	value:     f64,
	min_value: f64,
	max_value: f64,
}

DoubleConstrainedValue_Init :: proc() -> DoubleConstrainedValue {
	return DoubleConstrainedValue{
		object = Object_Init(&DoubleConstrainedValue_Class),
		value = 0,
		min_value = min(f64),
		max_value = max(f64),
	}
}

DoubleConstrainedValue_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(DoubleConstrainedValue)
	value^ = DoubleConstrainedValue_Init()
	value.name = "DoubleConstrainedValue"
	return &value.object
}

DoubleConstrainedValue_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^DoubleConstrainedValue)object)
}

DoubleConstrainedValue_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	val := cast(^DoubleConstrainedValue)object

	switch key {
	case "Value":
		vm.PushNumber(L, val.value)
	case "ConstrainedValue":
		vm.PushNumber(L, clamp(val.value, val.min_value, val.max_value))
	case "MinValue":
		vm.PushNumber(L, val.min_value)
	case "MaxValue":
		vm.PushNumber(L, val.max_value)
	case:
		return false
	}
	return true
}

DoubleConstrainedValue_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	val := cast(^DoubleConstrainedValue)object

	switch key {
	case "Value":
		val.value = clamp(vm.ArgNumber(L, value_index), val.min_value, val.max_value)
	case "MinValue":
		val.min_value = vm.ArgNumber(L, value_index)
	case "MaxValue":
		val.max_value = vm.ArgNumber(L, value_index)
	case:
		return false
	}
	return true
}

DoubleConstrainedValue_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^DoubleConstrainedValue)source
	dst := cast(^DoubleConstrainedValue)destination

	dst.value = src.value
	dst.min_value = src.min_value
	dst.max_value = src.max_value
}

Register_DoubleConstrainedValue :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&DoubleConstrainedValue_Class,
		DoubleConstrainedValue_construct,
		DoubleConstrainedValue_destroy,
		get = DoubleConstrainedValue_get,
		set = DoubleConstrainedValue_set,
		clone = DoubleConstrainedValue_clone,
		properties = []string{"Value", "ConstrainedValue", "MinValue", "MaxValue"},
	)
}