package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

UIMotionBlur_Class := Class_Info {
	name   = "UIMotionBlur",
	parent = &Instance_Class,
}

UIMotionBlur :: struct {
	using object: Object,
	enabled:      bool,
	angle:        f64,
	length:       datatypes.UDim,
}

UIMotionBlur_Init :: proc() -> UIMotionBlur {
	return UIMotionBlur {
		object = Object_Init(&UIMotionBlur_Class),
		enabled = true,
		angle = 0,
		length = datatypes.UDim{Scale = 0, Offset = 12},
	}
}

UIMotionBlur_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	motion_blur := new(UIMotionBlur)
	motion_blur^ = UIMotionBlur_Init()
	motion_blur.name = "UIMotionBlur"
	return &motion_blur.object
}

UIMotionBlur_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^UIMotionBlur)object)
}

UIMotionBlur_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	motion_blur := cast(^UIMotionBlur)object

	switch key {
	case "Enabled":
		vm.PushBoolean(L, motion_blur.enabled)
	case "Angle":
		vm.PushNumber(L, motion_blur.angle)
	case "Length":
		if datatype_registry == nil {return false}
		datatypes.Push_UDim(L, datatype_registry, motion_blur.length)
	case:
		return false
	}
	return true
}

UIMotionBlur_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	motion_blur := cast(^UIMotionBlur)object

	switch key {
	case "Enabled":
		motion_blur.enabled = vm.ArgBoolean(L, value_index)
	case "Angle":
		motion_blur.angle = vm.ArgNumber(L, value_index)
	case "Length":
		if datatype_registry == nil {return false}
		motion_blur.length = datatypes.Arg_UDim(L, value_index, datatype_registry)
	case:
		return false
	}
	return true
}

UIMotionBlur_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^UIMotionBlur)source
	dst := cast(^UIMotionBlur)destination

	dst.enabled = src.enabled
	dst.angle = src.angle
	dst.length = src.length
}

Register_UIMotionBlur :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&UIMotionBlur_Class,
		UIMotionBlur_construct,
		UIMotionBlur_destroy,
		get = UIMotionBlur_get,
		set = UIMotionBlur_set,
		clone = UIMotionBlur_clone,
		properties = []string{"Enabled", "Angle", "Length"},
	)
}
