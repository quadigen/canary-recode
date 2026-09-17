package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

Vector2Value_Class := Class_Info{
	name   = "Vector2Value",
	parent = &ValueBase_Class,
}

Vector2Value :: struct {
	using object: Object,

	value: datatypes.Vector2,
}

Vector2Value_Init :: proc() -> Vector2Value {
	return Vector2Value{
		object = Object_Init(&Vector2Value_Class),
	}
}

Vector2Value_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(Vector2Value)
	value^ = Vector2Value_Init()
	value.name = "Vector2Value"
	return &value.object
}

Vector2Value_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^Vector2Value)object)
}

Vector2Value_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	val := cast(^Vector2Value)object

	switch key {
	case "Value":
		if datatype_registry == nil { return false }
		datatypes.Push_Vector2(L, datatype_registry, val.value)
	case:
		return false
	}
	return true
}

Vector2Value_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	val := cast(^Vector2Value)object

	switch key {
	case "Value":
		if datatype_registry == nil { return false }
		val.value = datatypes.Arg_Vector2(L, value_index, datatype_registry)
	case:
		return false
	}
	return true
}

Vector2Value_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^Vector2Value)source
	dst := cast(^Vector2Value)destination

	dst.value = src.value
}

Register_Vector2Value :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Vector2Value_Class,
		Vector2Value_construct,
		Vector2Value_destroy,
		get = Vector2Value_get,
		set = Vector2Value_set,
		clone = Vector2Value_clone,
		properties = []string{"Value"},
	)
}