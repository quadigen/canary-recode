package classes

import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

NumberValue_Class := Class_Info {
	name   = "NumberValue",
	parent = &ValueBase_Class,
}

NumberValue :: struct {
	using object: Object,
	value:        f64,
	changed:      ^signals.Signal,
}

NumberValue_Init :: proc() -> NumberValue {
	return NumberValue{object = Object_Init(&NumberValue_Class), value = 0}
}

NumberValue_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	stroke := new(NumberValue)
	stroke^ = NumberValue_Init()
	stroke.name = "NumberValue"
	return &stroke.object
}

NumberValue_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	ValueBase_Destroy_Changed_Signal(&(cast(^NumberValue)object).changed)
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
	case "Changed":
		return ValueBase_Changed_Signal(L, object, &val.changed)
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
		new_value := vm.ArgNumber(L, value_index)
		if val.value == new_value {return true}
		val.value = new_value
		if val.changed != nil {
			vm.PushNumber(L, val.value)
			ValueBase_Fire_Changed(L, val.changed)
		}
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
		parallel_get = NumberValue_get,
		set = NumberValue_set,
		clone = NumberValue_clone,
		properties = []string{"Value"},
	)
}
