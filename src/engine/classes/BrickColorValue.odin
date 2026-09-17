package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

BrickColorValue_Class := Class_Info{
	name   = "BrickColorValue",
	parent = &ValueBase_Class,
}

BrickColorValue :: struct {
	using object: Object,

	value: datatypes.BrickColor,
}

BrickColorValue_Init :: proc() -> BrickColorValue {
	return BrickColorValue{
		object = Object_Init(&BrickColorValue_Class),
		value = datatypes.BrickColor_Gray,
	}
}

BrickColorValue_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(BrickColorValue)
	value^ = BrickColorValue_Init()
	value.name = "BrickColorValue"
	return &value.object
}

BrickColorValue_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^BrickColorValue)object)
}

BrickColorValue_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	val := cast(^BrickColorValue)object

	switch key {
	case "Value":
		if datatype_registry == nil { return false }
		datatypes.Push_BrickColor(L, datatype_registry, val.value)
	case:
		return false
	}
	return true
}

BrickColorValue_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	val := cast(^BrickColorValue)object

	switch key {
	case "Value":
		if datatype_registry == nil { return false }
		val.value = datatypes.Arg_BrickColor(L, value_index, datatype_registry)
	case:
		return false
	}
	return true
}

BrickColorValue_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^BrickColorValue)source
	dst := cast(^BrickColorValue)destination

	dst.value = src.value
}

Register_BrickColorValue :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&BrickColorValue_Class,
		BrickColorValue_construct,
		BrickColorValue_destroy,
		get = BrickColorValue_get,
		set = BrickColorValue_set,
		clone = BrickColorValue_clone,
		properties = []string{"Value"},
	)
}