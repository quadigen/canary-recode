package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

NumberSequenceValue_Class := Class_Info{
	name   = "NumberSequenceValue",
	parent = &ValueBase_Class,
}

NumberSequenceValue :: struct {
	using object: Object,

	value: datatypes.NumberSequence,
}

NumberSequenceValue_Init :: proc() -> NumberSequenceValue {
	return NumberSequenceValue{
		object = Object_Init(&NumberSequenceValue_Class),
		value = datatypes.NumberSequence_New(1),
	}
}

NumberSequenceValue_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(NumberSequenceValue)
	value^ = NumberSequenceValue_Init()
	value.name = "NumberSequenceValue"
	return &value.object
}

NumberSequenceValue_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	val := cast(^NumberSequenceValue)object

	datatypes.NumberSequence_Destroy(val.value)

	Object_Destroy(object)
	free(val)
}

NumberSequenceValue_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	val := cast(^NumberSequenceValue)object

	switch key {
	case "Value":
		if datatype_registry == nil { return false }
		datatypes.Push_NumberSequence(L, datatype_registry, val.value)
	case:
		return false
	}
	return true
}

NumberSequenceValue_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	val := cast(^NumberSequenceValue)object

	switch key {
	case "Value":
		if datatype_registry == nil { return false }
		datatypes.NumberSequence_Destroy(val.value)
		val.value = datatypes.NumberSequence_Clone(
			datatypes.Arg_NumberSequence(L, value_index, datatype_registry),
		)
	case:
		return false
	}
	return true
}

NumberSequenceValue_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^NumberSequenceValue)source
	dst := cast(^NumberSequenceValue)destination

	datatypes.NumberSequence_Destroy(dst.value)
	dst.value = datatypes.NumberSequence_Clone(src.value)
}

Register_NumberSequenceValue :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&NumberSequenceValue_Class,
		NumberSequenceValue_construct,
		NumberSequenceValue_destroy,
		get = NumberSequenceValue_get,
		set = NumberSequenceValue_set,
		clone = NumberSequenceValue_clone,
		properties = []string{"Value"},
	)
}