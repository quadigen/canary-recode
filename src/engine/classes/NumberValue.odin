package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

NumberValue_Class := Class_Info{
	name   = "NumberValue",
	parent = &ValueBase_Class,
}

NumberValue :: struct {
	using object: Object,

	value: f64,
}

NumberValue_Init :: proc() -> NumberValue {
	return NumberValue{
		object = Object_Init(&NumberValue_Class),
		value = 1,
	}
}

NumberValue_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	stroke := new(NumberValue)
	stroke^ = NumberValue_Init()
	stroke.name = "NumberValue"
	return &stroke.object
}

NumberValue_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^NumberValue)object)
}

NumberValue_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	val := cast(^NumberValue)object

	switch key {
	case "Value":
		vm.PushNumber(L, val.value)
	case:
		return false
	}
	return true
}

NumberValue_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	val := cast(^NumberValue)object

	switch key {
	case "Value":
		val.value = vm.ArgNumber(L, value_index)
	case:
		return false
	}
	return true
}

NumberValue_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^NumberValue)source
	dst := cast(^NumberValue)destination

	dst.value = src.value
}

Register_NumberValue :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&NumberValue_Class,
		NumberValue_construct,
		NumberValue_destroy,
		get = NumberValue_get,
		set = NumberValue_set,
		clone = NumberValue_clone,
		properties = []string{"Value"},
	)
}
