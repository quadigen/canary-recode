package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

UIGradient_Class := Class_Info{
	name   = "UIGradient",
	parent = &Instance_Class,
}

UIGradient :: struct {
	using object: Object,
	color: datatypes.ColorSequence,
	rotation: f64,
	transparency: datatypes.NumberSequence,
	offset: datatypes.Vector2,
}

UIGradient_Init :: proc() -> UIGradient {
	return UIGradient{
		object = Object_Init(&UIGradient_Class),
		color = datatypes.ColorSequence_New(datatypes.Color3{1, 1, 1}),
		rotation = 0,
		transparency = datatypes.NumberSequence_New(0),
		offset = datatypes.Vector2{0, 0},
	}
}

UIGradient_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	gradient := new(UIGradient)
	gradient^ = UIGradient_Init()
	gradient.name = "UIGradient"
	return &gradient.object
}

UIGradient_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	gradient := cast(^UIGradient)object
	datatypes.ColorSequence_Destroy(gradient.color)
	datatypes.NumberSequence_Destroy(gradient.transparency)
	Object_Destroy(object)
	free(gradient)
}

UIGradient_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	gradient := cast(^UIGradient)object
	switch key {
	case "Color":
		if datatype_registry == nil { return false }
		datatypes.Push_ColorSequence(L, datatype_registry, gradient.color)
	case "Rotation":
		vm.PushNumber(L, gradient.rotation)
	case "Transparency":
		if datatype_registry == nil { return false }
		datatypes.Push_NumberSequence(L, datatype_registry, gradient.transparency)
	case "Offset":
		if datatype_registry == nil { return false }
		datatypes.Push_Vector2(L, datatype_registry, gradient.offset)
	case:
		return false
	}
	return true
}

UIGradient_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	gradient := cast(^UIGradient)object
	switch key {
	case "Color":
		if datatype_registry == nil { return false }
		next := datatypes.Arg_ColorSequence(L, value_index, datatype_registry)
		datatypes.ColorSequence_Destroy(gradient.color)
		gradient.color = datatypes.ColorSequence_Clone(next)
	case "Rotation":
		gradient.rotation = vm.ArgNumber(L, value_index)
	case "Transparency":
		if datatype_registry == nil { return false }
		next := datatypes.Arg_NumberSequence(L, value_index, datatype_registry)
		datatypes.NumberSequence_Destroy(gradient.transparency)
		gradient.transparency = datatypes.NumberSequence_Clone(next)
	case "Offset":
		if datatype_registry == nil { return false }
		gradient.offset = datatypes.Arg_Vector2(L, value_index, datatype_registry)
	case:
		return false
	}
	return true
}

UIGradient_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^UIGradient)source
	dst := cast(^UIGradient)destination
	datatypes.ColorSequence_Destroy(dst.color)
	datatypes.NumberSequence_Destroy(dst.transparency)
	dst.color = datatypes.ColorSequence_Clone(src.color)
	dst.rotation = src.rotation
	dst.transparency = datatypes.NumberSequence_Clone(src.transparency)
	dst.offset = src.offset
}

Register_UIGradient :: proc(registry: ^Registry) {
	Register_Class(registry, &UIGradient_Class, UIGradient_construct, UIGradient_destroy,
		get = UIGradient_get, set = UIGradient_set, clone = UIGradient_clone,
		properties = []string{"Color", "Rotation", "Transparency", "Offset"})
}
