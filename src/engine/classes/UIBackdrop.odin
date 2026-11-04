package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

UIBackdrop_Class := Class_Info {
	name   = "UIBackdrop",
	parent = &Instance_Class,
}

UIBackdrop :: struct {
	using object:      Object,
	enabled:           bool,
	blur_radius:       f64,
	transparency:      f64,
	exponent:          f64,
	tint_color:        datatypes.Color3,
	tint_transparency: f64,
	brightness:        f64,
	contrast:          f64,
	saturation:        f64,
	hue_shift:         f64,
	morphology:        f64,
	displacement:      f64,
	pixelate:          f64,
	zoom:              f64,
	offset:            datatypes.UDim2,
	parallax:          datatypes.Vector2,
}

UIBackdrop_Init :: proc() -> UIBackdrop {
	return UIBackdrop {
		object = Object_Init(&UIBackdrop_Class),
		enabled = true,
		blur_radius = 18,
		exponent = 2,
		tint_color = datatypes.Color3{R = 1, G = 1, B = 1},
		tint_transparency = 0.85,
		brightness = 0,
		contrast = 1,
		saturation = 1,
		hue_shift = 0,
		morphology = 0,
		displacement = 0,
		pixelate = 0,
		zoom = 1,
		offset = datatypes.UDim2{},
		parallax = datatypes.Vector2{X = 0, Y = 0},
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
	case "Transparency":
		vm.PushNumber(L, backdrop.transparency)
	case "Exponent":
		vm.PushNumber(L, backdrop.exponent)
	case "TintColor3":
		if datatype_registry == nil {return false}
		datatypes.Push_Color3(L, datatype_registry, backdrop.tint_color)
	case "TintTransparency":
		vm.PushNumber(L, backdrop.tint_transparency)
	case "Brightness":
		vm.PushNumber(L, backdrop.brightness)
	case "Contrast":
		vm.PushNumber(L, backdrop.contrast)
	case "Saturation":
		vm.PushNumber(L, backdrop.saturation)
	case "HueShift":
		vm.PushNumber(L, backdrop.hue_shift)
	case "Morphology":
		vm.PushNumber(L, backdrop.morphology)
	case "Displacement":
		vm.PushNumber(L, backdrop.displacement)
	case "Pixelate":
		vm.PushNumber(L, backdrop.pixelate)
	case "Zoom":
		vm.PushNumber(L, backdrop.zoom)
	case "Offset":
		if datatype_registry == nil {return false}
		datatypes.Push_UDim2(L, datatype_registry, backdrop.offset)
	case "Parallax":
		if datatype_registry == nil {return false}
		datatypes.Push_Vector2(L, datatype_registry, backdrop.parallax)
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
	case "Transparency":
		backdrop.transparency = clamp(vm.ArgNumber(L, value_index), 0.0, 1.0)
	case "Exponent":
		backdrop.exponent = max(2.0, vm.ArgNumber(L, value_index))
	case "TintColor3":
		if datatype_registry == nil {return false}
		backdrop.tint_color = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case "TintTransparency":
		backdrop.tint_transparency = clamp(vm.ArgNumber(L, value_index), 0.0, 1.0)
	case "Brightness":
		backdrop.brightness = clamp(vm.ArgNumber(L, value_index), -1.0, 1.0)
	case "Contrast":
		backdrop.contrast = max(0.0, vm.ArgNumber(L, value_index))
	case "Saturation":
		backdrop.saturation = max(0.0, vm.ArgNumber(L, value_index))
	case "HueShift":
		backdrop.hue_shift = vm.ArgNumber(L, value_index)
	case "Morphology":
		backdrop.morphology = vm.ArgNumber(L, value_index)
	case "Displacement":
		backdrop.displacement = max(0.0, vm.ArgNumber(L, value_index))
	case "Pixelate":
		backdrop.pixelate = max(0.0, vm.ArgNumber(L, value_index))
	case "Zoom":
		backdrop.zoom = max(0.01, vm.ArgNumber(L, value_index))
	case "Offset":
		if datatype_registry == nil {return false}
		backdrop.offset = datatypes.Arg_UDim2(L, value_index, datatype_registry)
	case "Parallax":
		if datatype_registry == nil {return false}
		backdrop.parallax = datatypes.Arg_Vector2(L, value_index, datatype_registry)
	case:
		return false
	}
	return true
}

UIBackdrop_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^UIBackdrop)source
	dst := cast(^UIBackdrop)destination

	dst.enabled = src.enabled
	dst.blur_radius = src.blur_radius
	dst.transparency = src.transparency
	dst.exponent = src.exponent
	dst.tint_color = src.tint_color
	dst.tint_transparency = src.tint_transparency
	dst.brightness = src.brightness
	dst.contrast = src.contrast
	dst.saturation = src.saturation
	dst.hue_shift = src.hue_shift
	dst.morphology = src.morphology
	dst.displacement = src.displacement
	dst.pixelate = src.pixelate
	dst.zoom = src.zoom
	dst.offset = src.offset
	dst.parallax = src.parallax
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
		properties = []string {
			"TintColor3",
			"BlurRadius",
			"Transparency",
			"Exponent",
			"Enabled",
			"TintTransparency",
			"Brightness",
			"Contrast",
			"Saturation",
			"HueShift",
			"Morphology",
			"Displacement",
			"Pixelate",
			"Zoom",
			"Offset",
			"Parallax",
		},
	)
}
