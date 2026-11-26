package classes

import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

IntValue_Class := Class_Info {
	name   = "IntValue",
	parent = &ValueBase_Class,
}

IntValue :: struct {
	using object: Object,
	value:        i64,
	changed:      ^signals.Signal,
}

IntValue_Init :: proc() -> IntValue {
	return IntValue{object = Object_Init(&IntValue_Class), value = 0}
}

IntValue_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(IntValue)
	value^ = IntValue_Init()
	value.name = "IntValue"
	return &value.object
}

IntValue_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	ValueBase_Destroy_Changed_Signal(&(cast(^IntValue)object).changed)
	Object_Destroy(object)
	free(cast(^IntValue)object)
}

IntValue_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	val := cast(^IntValue)object

	switch key {
	case "Changed":
		return ValueBase_Changed_Signal(L, object, &val.changed)
	case "Value":
		vm.PushNumber(L, f64(val.value))
	case:
		return false
	}
	return true
}

IntValue_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	val := cast(^IntValue)object

	switch key {
	case "Value":
		new_value := i64(vm.ArgNumber(L, value_index))
		if val.value == new_value {return true}
		val.value = new_value
		if val.changed != nil {
			vm.PushNumber(L, f64(val.value))
			ValueBase_Fire_Changed(L, val.changed)
		}
	case:
		return false
	}
	return true
}

IntValue_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^IntValue)source
	dst := cast(^IntValue)destination

	dst.value = src.value
}

Register_IntValue :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&IntValue_Class,
		IntValue_construct,
		IntValue_destroy,
		get = IntValue_get,
		parallel_get = IntValue_get,
		set = IntValue_set,
		clone = IntValue_clone,
		properties = []string{"Value"},
	)
}
