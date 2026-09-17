package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

Color3Value_Class := Class_Info{
	name   = "Color3Value",
	parent = &ValueBase_Class,
}

Color3Value :: struct {
	using object: Object,

	value: datatypes.Color3,
}

Color3Value_Init :: proc() -> Color3Value {
	return Color3Value{
		object = Object_Init(&Color3Value_Class),
		value = datatypes.Color3{R = 1, G = 1, B = 1},
	}
}

Color3Value_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(Color3Value)
	value^ = Color3Value_Init()
	value.name = "Color3Value"
	return &value.object
}

Color3Value_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^Color3Value)object)
}

Color3Value_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	val := cast(^Color3Value)object

	switch key {
	case "Value":
		if datatype_registry == nil { return false }
		datatypes.Push_Color3(L, datatype_registry, val.value)
	case:
		return false
	}
	return true
}

Color3Value_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	val := cast(^Color3Value)object

	switch key {
	case "Value":
		if datatype_registry == nil { return false }
		val.value = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case:
		return false
	}
	return true
}

Color3Value_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^Color3Value)source
	dst := cast(^Color3Value)destination

	dst.value = src.value
}

Register_Color3Value :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Color3Value_Class,
		Color3Value_construct,
		Color3Value_destroy,
		get = Color3Value_get,
		set = Color3Value_set,
		clone = Color3Value_clone,
		properties = []string{"Value"},
	)
}