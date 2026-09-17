package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

NumberRangeValue_Class := Class_Info{
	name   = "NumberRangeValue",
	parent = &ValueBase_Class,
}

NumberRangeValue :: struct {
	using object: Object,

	value: datatypes.NumberRange,
}

NumberRangeValue_Init :: proc() -> NumberRangeValue {
	return NumberRangeValue{
		object = Object_Init(&NumberRangeValue_Class),
	}
}

NumberRangeValue_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(NumberRangeValue)
	value^ = NumberRangeValue_Init()
	value.name = "NumberRangeValue"
	return &value.object
}

NumberRangeValue_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^NumberRangeValue)object)
}

NumberRangeValue_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	val := cast(^NumberRangeValue)object

	switch key {
	case "Value":
		if datatype_registry == nil { return false }
		datatypes.Push_NumberRange(L, datatype_registry, val.value)
	case:
		return false
	}
	return true
}

NumberRangeValue_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	val := cast(^NumberRangeValue)object

	switch key {
	case "Value":
		if datatype_registry == nil { return false }
		val.value = datatypes.Arg_NumberRange(L, value_index, datatype_registry)
	case:
		return false
	}
	return true
}

NumberRangeValue_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^NumberRangeValue)source
	dst := cast(^NumberRangeValue)destination

	dst.value = src.value
}

Register_NumberRangeValue :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&NumberRangeValue_Class,
		NumberRangeValue_construct,
		NumberRangeValue_destroy,
		get = NumberRangeValue_get,
		set = NumberRangeValue_set,
		clone = NumberRangeValue_clone,
		properties = []string{"Value"},
	)
}