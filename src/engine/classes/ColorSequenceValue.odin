package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

ColorSequenceValue_Class := Class_Info{
	name   = "ColorSequenceValue",
	parent = &ValueBase_Class,
}

ColorSequenceValue :: struct {
	using object: Object,

	value: datatypes.ColorSequence,
}

ColorSequenceValue_Init :: proc() -> ColorSequenceValue {
	return ColorSequenceValue{
		object = Object_Init(&ColorSequenceValue_Class),
		value = datatypes.ColorSequence_New(datatypes.Color3{R = 1, G = 1, B = 1}),
	}
}

ColorSequenceValue_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(ColorSequenceValue)
	value^ = ColorSequenceValue_Init()
	value.name = "ColorSequenceValue"
	return &value.object
}

ColorSequenceValue_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	val := cast(^ColorSequenceValue)object

	datatypes.ColorSequence_Destroy(val.value)

	Object_Destroy(object)
	free(val)
}

ColorSequenceValue_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	val := cast(^ColorSequenceValue)object

	switch key {
	case "Value":
		if datatype_registry == nil { return false }
		datatypes.Push_ColorSequence(L, datatype_registry, val.value)
	case:
		return false
	}
	return true
}

ColorSequenceValue_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	val := cast(^ColorSequenceValue)object

	switch key {
	case "Value":
		if datatype_registry == nil { return false }
		datatypes.ColorSequence_Destroy(val.value)
		val.value = datatypes.ColorSequence_Clone(
			datatypes.Arg_ColorSequence(L, value_index, datatype_registry),
		)
	case:
		return false
	}
	return true
}

ColorSequenceValue_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^ColorSequenceValue)source
	dst := cast(^ColorSequenceValue)destination

	datatypes.ColorSequence_Destroy(dst.value)
	dst.value = datatypes.ColorSequence_Clone(src.value)
}

Register_ColorSequenceValue :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&ColorSequenceValue_Class,
		ColorSequenceValue_construct,
		ColorSequenceValue_destroy,
		get = ColorSequenceValue_get,
		set = ColorSequenceValue_set,
		clone = ColorSequenceValue_clone,
		properties = []string{"Value"},
	)
}