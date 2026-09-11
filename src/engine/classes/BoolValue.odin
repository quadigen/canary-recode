package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

BoolValue_Class := Class_Info{
	name   = "BoolValue",
	parent = &Instance_Class,
}

BoolValue :: struct {
	using object: Object,

	value: bool
}

BoolValue_Init :: proc() -> BoolValue {
	return BoolValue{
		object = Object_Init(&BoolValue_Class),
		value = true,
	}
}

BoolValue_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	stroke := new(BoolValue)
	stroke^ = BoolValue_Init()
	stroke.name = "BoolValue"
	return &stroke.object
}

BoolValue_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^BoolValue)object)
}

BoolValue_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	val := cast(^BoolValue)object

	switch key {
	case "Value":
		vm.PushBoolean(L, val.value)
	case:
		return false
	}
	return true
}

BoolValue_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	val := cast(^BoolValue)object

	switch key {
	case "Value":
		val.value = vm.ArgBoolean(L, value_index)
	case:
		return false
	}
	return true
}

BoolValue_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^BoolValue)source
	dst := cast(^BoolValue)destination

	dst.value = src.value
}

Register_BoolValue :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&BoolValue_Class,
		BoolValue_construct,
		BoolValue_destroy,
		get = BoolValue_get,
		set = BoolValue_set,
		clone = BoolValue_clone,
	)
}
