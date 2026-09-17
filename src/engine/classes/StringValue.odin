package classes

import "core:strings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

StringValue_Class := Class_Info{
	name   = "StringValue",
	parent = &ValueBase_Class,
}

StringValue :: struct {
	using object: Object,

	value: string,
}

StringValue_Init :: proc() -> StringValue {
	return StringValue{
		object = Object_Init(&StringValue_Class),
		value = strings.clone(""),
	}
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
		delete(val.value)
		val.value = strings.clone(vm.ArgString(L, value_index))
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
		set = StringValue_set,
		clone = StringValue_clone,
		properties = []string{"Value"},
	)
}