package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

InputObject_Class := Class_Info{
	name = "InputObject",
	parent = &Instance_Class,
}

InputObject :: struct {
	using object: Object,
	UserInputType:  enums.UserInputType,
	UserInputState: enums.UserInputState,
	KeyCode:        enums.KeyCode,
	Position:       datatypes.Vector3,
	Delta:          datatypes.Vector3,
}

InputObject_Value :: struct {
	UserInputType:  enums.UserInputType,
	UserInputState: enums.UserInputState,
	KeyCode:        enums.KeyCode,
	Position:       datatypes.Vector3,
	Delta:          datatypes.Vector3,
}

input_object_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	input := new(InputObject)
	input.object = Object_Init(&InputObject_Class, "InputObject")
	return &input.object
}

input_object_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^InputObject)object)
}

input_object_get :: proc(L: ^vm.State, object: ^Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, key: string) -> bool {
	input := cast(^InputObject)object
	switch key {
	case "UserInputType":
		if enum_registry == nil { return false }
		_ = enums.Push_Item_By_Value(L, enum_registry, "UserInputType", i64(input.UserInputType))
	case "UserInputState":
		if enum_registry == nil { return false }
		_ = enums.Push_Item_By_Value(L, enum_registry, "UserInputState", i64(input.UserInputState))
	case "KeyCode":
		if enum_registry == nil { return false }
		_ = enums.Push_Item_By_Value(L, enum_registry, "KeyCode", i64(input.KeyCode))
	case "Position": vm.PushVector3(L, input.Position.x, input.Position.y, input.Position.z)
	case "Delta": vm.PushVector3(L, input.Delta.x, input.Delta.y, input.Delta.z)
	case: return false
	}
	return true
}

Push_InputObject :: proc(L: ^vm.State, registry: ^Registry, value: InputObject_Value) -> ^InputObject {
	if L == nil || registry == nil { return nil }
	object, ok := Push_New(registry, &vm.VM{L = L}, "InputObject", false)
	if !ok || object == nil { return nil }
	input := cast(^InputObject)object
	input.UserInputType = value.UserInputType
	input.UserInputState = value.UserInputState
	input.KeyCode = value.KeyCode
	input.Position = value.Position
	input.Delta = value.Delta
	return input
}

Register_InputObject :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&InputObject_Class,
		input_object_construct,
		input_object_destroy,
		creatable = false,
		get = input_object_get,
	)
}
