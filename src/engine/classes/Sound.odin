package classes

import datatypes "../datatypes"
import "core:strings"
import enums "../enum"
import vm "../vm"
import guilib "../gui"

Sound_Class := Class_Info{
    name   = "Sound",
    parent = &Instance_Class,
}

Sound :: struct {
    using object: Object,

    bottom_left_radius: datatypes.UDim,
    bottom_right_radius: datatypes.UDim,
    top_left_radius: datatypes.UDim,
    top_right_radius: datatypes.UDim,
    corner_radius: datatypes.UDim,
}

Sound_Init :: proc() -> Sound {
    return Sound{
        object = Object_Init(&Sound_Class),

        bottom_left_radius = datatypes.UDim{0, 0},
        bottom_right_radius = datatypes.UDim{0, 0},
        top_right_radius = datatypes.UDim{0, 0},
        top_left_radius = datatypes.UDim{0, 0},
        corner_radius = datatypes.UDim{0, 15},
    }
}

Sound_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	corner := cast(^Sound)object

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

Sound_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	corner := cast(^Sound)object

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

Sound_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
    corner := new(Sound)
    corner^ = Sound_Init()
    corner.name = "Sound"

    return &corner.object
}

Sound_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
    Object_Destroy(object)
    free(cast(^Sound)object)
}

Sound_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^Sound)source
	dst := cast(^Sound)destination

	dst.bottom_left_radius  = src.bottom_left_radius
	dst.bottom_right_radius = src.bottom_right_radius
	dst.top_left_radius     = src.top_left_radius
	dst.top_right_radius    = src.top_right_radius
	dst.corner_radius       = src.corner_radius
}

Register_Sound :: proc(registry: ^Registry) {
    Register_Class(
        registry,
        &Sound_Class,
        Sound_construct,
        Sound_destroy,
        clone = Sound_clone,
    )
}
