package classes

import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

BoolValue_Class := Class_Info {
	name   = "BoolValue",
	parent = &ValueBase_Class,
}

BoolValue :: struct {
	using object: Object,
	value:        bool,
	changed:      ^signals.Signal,
}

BoolValue_Init :: proc() -> BoolValue {
	return BoolValue{object = Object_Init(&BoolValue_Class), value = false}
}

BoolValue_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	stroke := new(BoolValue)
	stroke^ = BoolValue_Init()
	stroke.name = "BoolValue"
	return &stroke.object
}

BoolValue_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	ValueBase_Destroy_Changed_Signal(&(cast(^BoolValue)object).changed)
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
	case "Changed":
		return ValueBase_Changed_Signal(L, object, &val.changed)
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
		new_value := vm.ArgBoolean(L, value_index)
		if val.value == new_value {return true}
		val.value = new_value
		if val.changed != nil {
			vm.PushBoolean(L, val.value)
			ValueBase_Fire_Changed(L, val.changed)
		}
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
		parallel_get = BoolValue_get,
		set = BoolValue_set,
		clone = BoolValue_clone,
		properties = []string{"Value"},
	)
}
