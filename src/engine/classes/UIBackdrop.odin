package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

UIBackdrop_Class := Class_Info{
	name   = "UIBackdrop",
	parent = &Instance_Class,
}

UIBackdrop :: struct {
	using object: Object,

	enabled:           bool,
	blur_radius:       f64,
	tint_color:        datatypes.Color3,
	tint_transparency: f64,
}

UIBackdrop_Init :: proc() -> UIBackdrop {
	return UIBackdrop{
		object = Object_Init(&UIBackdrop_Class),
		enabled = true,
		blur_radius = 18,
		tint_color = datatypes.Color3{R = 1, G = 1, B = 1},
		tint_transparency = 0.85,
	}
}

UIBackdrop_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	backdrop := new(UIBackdrop)
	backdrop^ = UIBackdrop_Init()
	backdrop.name = "UIBackdrop"
	return &backdrop.object
}

UIBackdrop_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^UIBackdrop)object)
}

UIBackdrop_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	backdrop := cast(^UIBackdrop)object

	switch key {
	case "Enabled":
		vm.PushBoolean(L, backdrop.enabled)
	case "BlurRadius":
		vm.PushNumber(L, backdrop.blur_radius)
	case "TintColor3":
		if datatype_registry == nil { return false }
		datatypes.Push_Color3(L, datatype_registry, backdrop.tint_color)
	case "TintTransparency":
		vm.PushNumber(L, backdrop.tint_transparency)
	case:
		return false
	}
	return true
}

UIBackdrop_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	backdrop := cast(^UIBackdrop)object

	switch key {
	case "Enabled":
		backdrop.enabled = vm.ArgBoolean(L, value_index)
	case "BlurRadius":
		backdrop.blur_radius = max(0.0, vm.ArgNumber(L, value_index))
	case "TintColor3":
		if datatype_registry == nil { return false }
		backdrop.tint_color = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case "TintTransparency":
		backdrop.tint_transparency = clamp(vm.ArgNumber(L, value_index), 0.0, 1.0)
	case:
		return false
	}
	return true
}

UIBackdrop_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^UIBackdrop)source
	dst := cast(^UIBackdrop)destination

	dst.enabled           = src.enabled
	dst.blur_radius       = src.blur_radius
	dst.tint_color        = src.tint_color
	dst.tint_transparency = src.tint_transparency
}

Register_UIBackdrop :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&UIBackdrop_Class,
		UIBackdrop_construct,
		UIBackdrop_destroy,
		get = UIBackdrop_get,
		set = UIBackdrop_set,
		clone = UIBackdrop_clone,
		properties = []string{"TintColor3", "BlurRadius", "Enabled", "TintTransparency"},
	)
}
