package classes

import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"
import "core:strings"

StringValue_Class := Class_Info {
	name   = "StringValue",
	parent = &ValueBase_Class,
}

StringValue :: struct {
	using object: Object,
	value:        string,
	changed:      ^signals.Signal,
}

StringValue_Init :: proc() -> StringValue {
	return StringValue{object = Object_Init(&StringValue_Class), value = strings.clone("")}
}

StringValue_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(StringValue)
	value^ = StringValue_Init()
	value.name = "StringValue"
	return &value.object
}

StringValue_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	val := cast(^StringValue)object

	delete(val.value)

	ValueBase_Destroy_Changed_Signal(&(cast(^StringValue)object).changed)
	Object_Destroy(object)
	free(val)
}

StringValue_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	val := cast(^StringValue)object

	switch key {
	case "Changed":
		return ValueBase_Changed_Signal(L, object, &val.changed)
	case "Value":
		vm.PushString(L, val.value)
	case:
		return false
	}
	return true
}

StringValue_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	val := cast(^StringValue)object

	switch key {
	case "Value":
		new_value := vm.ArgString(L, value_index)
		if val.value == new_value {return true}
		delete(val.value)
		val.value = strings.clone(new_value)
		if val.changed != nil {
			vm.PushString(L, val.value)
			ValueBase_Fire_Changed(L, val.changed)
		}
	case:
		return false
	}
	return true
}

StringValue_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^StringValue)source
	dst := cast(^StringValue)destination

	delete(dst.value)
	dst.value = strings.clone(src.value)
}

Register_StringValue :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&StringValue_Class,
		StringValue_construct,
		StringValue_destroy,
		get = StringValue_get,
		parallel_get = StringValue_get,
		set = StringValue_set,
		clone = StringValue_clone,
		properties = []string{"Value"},
	)
}
