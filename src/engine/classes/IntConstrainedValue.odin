package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

IntConstrainedValue_Class := Class_Info{
	name   = "IntConstrainedValue",
	parent = &ValueBase_Class,
}

IntConstrainedValue :: struct {
	using object: Object,

	value:     i64,
	min_value: i64,
	max_value: i64,
}

IntConstrainedValue_Init :: proc() -> IntConstrainedValue {
	return IntConstrainedValue{
		object = Object_Init(&IntConstrainedValue_Class),
		value = 0,
		min_value = min(i64),
		max_value = max(i64),
	}
}

IntConstrainedValue_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(IntConstrainedValue)
	value^ = IntConstrainedValue_Init()
	value.name = "IntConstrainedValue"
	return &value.object
}

IntConstrainedValue_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^IntConstrainedValue)object)
}

IntConstrainedValue_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	val := cast(^IntConstrainedValue)object

	switch key {
	case "Value":
		vm.PushNumber(L, f64(val.value))
	case "ConstrainedValue":
		vm.PushNumber(L, f64(clamp(val.value, val.min_value, val.max_value)))
	case "MinValue":
		vm.PushNumber(L, f64(val.min_value))
	case "MaxValue":
		vm.PushNumber(L, f64(val.max_value))
	case:
		return false
	}
	return true
}

IntConstrainedValue_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	val := cast(^IntConstrainedValue)object

	switch key {
	case "Value":
		val.value = clamp(i64(vm.ArgNumber(L, value_index)), val.min_value, val.max_value)
	case "MinValue":
		val.min_value = i64(vm.ArgNumber(L, value_index))
	case "MaxValue":
		val.max_value = i64(vm.ArgNumber(L, value_index))
	case:
		return false
	}
	return true
}

IntConstrainedValue_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^IntConstrainedValue)source
	dst := cast(^IntConstrainedValue)destination

	dst.value = src.value
	dst.min_value = src.min_value
	dst.max_value = src.max_value
}

Register_IntConstrainedValue :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&IntConstrainedValue_Class,
		IntConstrainedValue_construct,
		IntConstrainedValue_destroy,
		get = IntConstrainedValue_get,
		set = IntConstrainedValue_set,
		clone = IntConstrainedValue_clone,
		properties = []string{"Value", "ConstrainedValue", "MinValue", "MaxValue"},
	)
}