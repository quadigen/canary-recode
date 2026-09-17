package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

Vector3Value_Class := Class_Info{
	name   = "Vector3Value",
	parent = &ValueBase_Class,
}

Vector3Value :: struct {
	using object: Object,

	value: datatypes.Vector3,
}

Vector3Value_Init :: proc() -> Vector3Value {
	return Vector3Value{
		object = Object_Init(&Vector3Value_Class),
	}
}

Vector3Value_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(Vector3Value)
	value^ = Vector3Value_Init()
	value.name = "Vector3Value"
	return &value.object
}

Vector3Value_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^Vector3Value)object)
}

Vector3Value_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	val := cast(^Vector3Value)object

	switch key {
	case "Value":
		datatypes.Push_Vector3(L, val.value)
	case:
		return false
	}
	return true
}

Vector3Value_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	val := cast(^Vector3Value)object

	switch key {
	case "Value":
		val.value = datatypes.Arg_Vector3(L, value_index)
	case:
		return false
	}
	return true
}

Vector3Value_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^Vector3Value)source
	dst := cast(^Vector3Value)destination

	dst.value = src.value
}

Register_Vector3Value :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Vector3Value_Class,
		Vector3Value_construct,
		Vector3Value_destroy,
		get = Vector3Value_get,
		set = Vector3Value_set,
		clone = Vector3Value_clone,
		properties = []string{"Value"},
	)
}