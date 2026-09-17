package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

ObjectValue_Class := Class_Info{
	name   = "ObjectValue",
	parent = &ValueBase_Class,
}

ObjectValue :: struct {
	using object: Object,

	value: ^Object,
}

ObjectValue_Init :: proc() -> ObjectValue {
	return ObjectValue{
		object = Object_Init(&ObjectValue_Class),
	}
}

ObjectValue_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(ObjectValue)
	value^ = ObjectValue_Init()
	value.name = "ObjectValue"
	return &value.object
}

ObjectValue_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^ObjectValue)object)
}

ObjectValue_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	val := cast(^ObjectValue)object

	switch key {
	case "Value":
		Push_Object(L, val.value)
	case:
		return false
	}
	return true
}

ObjectValue_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	val := cast(^ObjectValue)object

	switch key {
	case "Value":
		if vm.IsNoneOrNil(L, value_index) {
			val.value = nil
			return true
		}

		reference := object_from_argument(L, value_index)
		if reference == nil {
			_ = vm.RaiseError(L, "ObjectValue Value must be an Instance or nil")
			return true
		}

		val.value = reference
	case:
		return false
	}
	return true
}

ObjectValue_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^ObjectValue)source
	dst := cast(^ObjectValue)destination

	dst.value = src.value
}

Register_ObjectValue :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&ObjectValue_Class,
		ObjectValue_construct,
		ObjectValue_destroy,
		get = ObjectValue_get,
		set = ObjectValue_set,
		clone = ObjectValue_clone,
		properties = []string{"Value"},
	)
}