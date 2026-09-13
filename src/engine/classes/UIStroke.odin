package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

UIStroke_Class := Class_Info{
	name   = "UIStroke",
	parent = &Instance_Class,
}

UIStroke :: struct {
	using object: Object,

	enabled:           bool,
	color:             datatypes.Color3,
	transparency:      f64,
	thickness:         f64,
	apply_stroke_mode: enums.ApplyStrokeMode,
}

UIStroke_Init :: proc() -> UIStroke {
	return UIStroke{
		object = Object_Init(&UIStroke_Class),
		enabled = true,
		color = datatypes.Color3{R = 0, G = 0, B = 0},
		transparency = 0,
		thickness = 1,
		apply_stroke_mode = enums.ApplyStrokeMode.Contextual,
	}
}

UIStroke_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	stroke := new(UIStroke)
	stroke^ = UIStroke_Init()
	stroke.name = "UIStroke"
	return &stroke.object
}

UIStroke_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^UIStroke)object)
}

UIStroke_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	stroke := cast(^UIStroke)object

	switch key {
	case "Enabled":
		vm.PushBoolean(L, stroke.enabled)
	case "Color":
		if datatype_registry == nil { return false }
		datatypes.Push_Color3(L, datatype_registry, stroke.color)
	case "Transparency":
		vm.PushNumber(L, stroke.transparency)
	case "Thickness":
		vm.PushNumber(L, stroke.thickness)
	case "ApplyStrokeMode":
		if enum_registry == nil { return false }
		_ = enums.Push_Item_By_Value(
			L,
			enum_registry,
			"ApplyStrokeMode",
			i64(stroke.apply_stroke_mode),
		)
	case:
		return false
	}
	return true
}

UIStroke_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	stroke := cast(^UIStroke)object

	switch key {
	case "Enabled":
		stroke.enabled = vm.ArgBoolean(L, value_index)
	case "Color":
		if datatype_registry == nil { return false }
		stroke.color = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case "Transparency":
		stroke.transparency = clamp(vm.ArgNumber(L, value_index), 0.0, 1.0)
	case "Thickness":
		stroke.thickness = max(0.0, vm.ArgNumber(L, value_index))
	case "ApplyStrokeMode":
		if enum_registry == nil { return false }
		stroke.apply_stroke_mode = enums.ApplyStrokeMode(
			enums.Arg_Item(L, value_index, enum_registry, "ApplyStrokeMode").value,
		)
	case:
		return false
	}
	return true
}

UIStroke_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^UIStroke)source
	dst := cast(^UIStroke)destination

	dst.enabled           = src.enabled
	dst.color             = src.color
	dst.transparency      = src.transparency
	dst.thickness         = src.thickness
	dst.apply_stroke_mode = src.apply_stroke_mode
}

Register_UIStroke :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&UIStroke_Class,
		UIStroke_construct,
		UIStroke_destroy,
		get = UIStroke_get,
		set = UIStroke_set,
		clone = UIStroke_clone,
		properties = []string{"Color", "Thickness", "ApplyStrokeMode", "Transparency", "Enabled"},
	)
}
