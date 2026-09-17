package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

CFrameValue_Class := Class_Info{
	name   = "CFrameValue",
	parent = &ValueBase_Class,
}

CFrameValue :: struct {
	using object: Object,

	value: datatypes.CFrame,
}

CFrameValue_Init :: proc() -> CFrameValue {
	return CFrameValue{
		object = Object_Init(&CFrameValue_Class),
		value = datatypes.CFrame_Identity,
	}
}

CFrameValue_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(CFrameValue)
	value^ = CFrameValue_Init()
	value.name = "CFrameValue"
	return &value.object
}

CFrameValue_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^CFrameValue)object)
}

CFrameValue_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	val := cast(^CFrameValue)object

	switch key {
	case "Value":
		if datatype_registry == nil { return false }
		datatypes.Push_CFrame(L, datatype_registry, val.value)
	case:
		return false
	}
	return true
}

CFrameValue_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	val := cast(^CFrameValue)object

	switch key {
	case "Value":
		if datatype_registry == nil { return false }
		val.value = datatypes.Arg_CFrame(L, value_index, datatype_registry)
	case:
		return false
	}
	return true
}

CFrameValue_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^CFrameValue)source
	dst := cast(^CFrameValue)destination

	dst.value = src.value
}

Register_CFrameValue :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&CFrameValue_Class,
		CFrameValue_construct,
		CFrameValue_destroy,
		get = CFrameValue_get,
		set = CFrameValue_set,
		clone = CFrameValue_clone,
		properties = []string{"Value"},
	)
}