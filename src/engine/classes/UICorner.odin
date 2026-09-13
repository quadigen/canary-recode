package classes

import datatypes "../datatypes"
import "core:strings"
import enums "../enum"
import vm "../vm"
import guilib "../gui"

UICorner_Class := Class_Info{
    name   = "UICorner",
    parent = &Instance_Class,
}

UICorner :: struct {
    using object: Object,

    bottom_left_radius: datatypes.UDim,
    bottom_right_radius: datatypes.UDim,
    top_left_radius: datatypes.UDim,
    top_right_radius: datatypes.UDim,
    corner_radius: datatypes.UDim,
}

UICorner_Init :: proc() -> UICorner {
    return UICorner{
        object = Object_Init(&UICorner_Class),

        bottom_left_radius = datatypes.UDim{0, 0},
        bottom_right_radius = datatypes.UDim{0, 0},
        top_right_radius = datatypes.UDim{0, 0},
        top_left_radius = datatypes.UDim{0, 0},
        corner_radius = datatypes.UDim{0, 15},
    }
}

UICorner_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	corner := cast(^UICorner)object

	switch key {
	case "BottomLeftRadius":
		datatypes.Push_UDim(L, datatype_registry, corner.bottom_left_radius)
		return true
	case "BottomRightRadius":
		datatypes.Push_UDim(L, datatype_registry, corner.bottom_right_radius)
		return true
    case "TopLeftRadius":
		datatypes.Push_UDim(L, datatype_registry, corner.top_left_radius)
		return true
    case "TopRightRadius":
		datatypes.Push_UDim(L, datatype_registry, corner.top_right_radius)
		return true
    case "CornerRadius":
		datatypes.Push_UDim(L, datatype_registry, corner.corner_radius)
		return true
	}

	return false
}

UICorner_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	corner := cast(^UICorner)object

	switch key {
	case "BottomLeftRadius":
		corner.bottom_left_radius = datatypes.Arg_UDim(L, value_index, datatype_registry)
		return true
	case "BottomRightRadius":
		corner.bottom_right_radius = datatypes.Arg_UDim(L, value_index, datatype_registry)
		return true
    case "TopLeftRadius":
		corner.top_left_radius = datatypes.Arg_UDim(L, value_index, datatype_registry)
		return true
    case "TopRightRadius":
		corner.top_right_radius = datatypes.Arg_UDim(L, value_index, datatype_registry)
		return true
    case "CornerRadius":
		corner.corner_radius = datatypes.Arg_UDim(L, value_index, datatype_registry)
		return true
	}

	return false
}

ui_corner_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
    corner := new(UICorner)
    corner^ = UICorner_Init()
    corner.name = "UICorner"

    return &corner.object
}

ui_corner_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
    Object_Destroy(object)
    free(cast(^UICorner)object)
}

ui_corner_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^UICorner)source
	dst := cast(^UICorner)destination

	dst.bottom_left_radius  = src.bottom_left_radius
	dst.bottom_right_radius = src.bottom_right_radius
	dst.top_left_radius     = src.top_left_radius
	dst.top_right_radius    = src.top_right_radius
	dst.corner_radius       = src.corner_radius
}

Register_UICorner :: proc(registry: ^Registry) {
    Register_Class(
        registry,
        &UICorner_Class,
        ui_corner_construct,
        ui_corner_destroy,
		get = UICorner_get,
		set = UICorner_set,
        clone = ui_corner_clone,
		properties = []string{"CornerRadius", "TopLeftRadius", "TopRightRadius", "BottomLeftRadius", "BottomRightRadius"},
    )
}
