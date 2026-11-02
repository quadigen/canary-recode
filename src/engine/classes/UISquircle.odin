package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

UISquircle_Class := Class_Info {
	name   = "UISquircle",
	parent = &Instance_Class,
}

UISquircle :: struct {
	using object:        Object,
	radius:              datatypes.UDim,
	top_left_radius:     datatypes.UDim,
	top_right_radius:    datatypes.UDim,
	bottom_left_radius:  datatypes.UDim,
	bottom_right_radius: datatypes.UDim,
	exponent:            f64,
}

UISquircle_Init :: proc() -> UISquircle {
	return UISquircle {
		object = Object_Init(&UISquircle_Class),
		radius = datatypes.UDim{0, 15},
		top_left_radius = datatypes.UDim{0, 0},
		top_right_radius = datatypes.UDim{0, 0},
		bottom_left_radius = datatypes.UDim{0, 0},
		bottom_right_radius = datatypes.UDim{0, 0},
		exponent = 4,
	}
}

UISquircle_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	squircle := cast(^UISquircle)object

	switch key {
	case "Radius":
		datatypes.Push_UDim(L, datatype_registry, squircle.radius)
		return true
	case "Exponent":
		vm.PushNumber(L, squircle.exponent)
		return true
	case "TopLeftRadius":
		datatypes.Push_UDim(L, datatype_registry, squircle.top_left_radius)
		return true
	case "TopRightRadius":
		datatypes.Push_UDim(L, datatype_registry, squircle.top_right_radius)
		return true
	case "BottomLeftRadius":
		datatypes.Push_UDim(L, datatype_registry, squircle.bottom_left_radius)
		return true
	case "BottomRightRadius":
		datatypes.Push_UDim(L, datatype_registry, squircle.bottom_right_radius)
		return true
	}

	return false
}

UISquircle_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	squircle := cast(^UISquircle)object

	switch key {
	case "Radius":
		squircle.radius = datatypes.Arg_UDim(L, value_index, datatype_registry)
		return true
	case "Exponent":
		squircle.exponent = max(2.0, vm.ArgNumber(L, value_index))
		return true
	case "TopLeftRadius":
		squircle.top_left_radius = datatypes.Arg_UDim(L, value_index, datatype_registry)
		return true
	case "TopRightRadius":
		squircle.top_right_radius = datatypes.Arg_UDim(L, value_index, datatype_registry)
		return true
	case "BottomLeftRadius":
		squircle.bottom_left_radius = datatypes.Arg_UDim(L, value_index, datatype_registry)
		return true
	case "BottomRightRadius":
		squircle.bottom_right_radius = datatypes.Arg_UDim(L, value_index, datatype_registry)
		return true
	}

	return false
}

ui_squircle_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	squircle := new(UISquircle)
	squircle^ = UISquircle_Init()
	squircle.name = "UISquircle"

	return &squircle.object
}

ui_squircle_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^UISquircle)object)
}

ui_squircle_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^UISquircle)source
	dst := cast(^UISquircle)destination

	dst.radius = src.radius
	dst.top_left_radius = src.top_left_radius
	dst.top_right_radius = src.top_right_radius
	dst.bottom_left_radius = src.bottom_left_radius
	dst.bottom_right_radius = src.bottom_right_radius
	dst.exponent = src.exponent
}

Register_UISquircle :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&UISquircle_Class,
		ui_squircle_construct,
		ui_squircle_destroy,
		get = UISquircle_get,
		set = UISquircle_set,
		clone = ui_squircle_clone,
		properties = []string {
			"Radius",
			"Exponent",
			"TopLeftRadius",
			"TopRightRadius",
			"BottomLeftRadius",
			"BottomRightRadius",
		},
	)
}
