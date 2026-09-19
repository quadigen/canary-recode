package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

BlurImageFilter_Class := Class_Info{
	name   = "BlurImageFilter",
	parent = &Instance_Class,
}

BlurImageFilter :: struct {
	using object: Object,

	blur_radius: datatypes.UDim,
	enabled:     bool,
}

BlurImageFilter_Init :: proc() -> BlurImageFilter {
	return BlurImageFilter{
		object      = Object_Init(&BlurImageFilter_Class),
		blur_radius = datatypes.UDim{
			Scale  = 0,
			Offset = 8,
		},
		enabled = true,
	}
}

BlurImageFilter_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	filter := new(BlurImageFilter)
	filter^ = BlurImageFilter_Init()

	filter.name = "BlurImageFilter"

	return &filter.object
}

BlurImageFilter_destroy :: proc(
	object: ^Object,
	renderer: ^Renderer_Object,
) {
	Object_Destroy(object)
	free(cast(^BlurImageFilter)object)
}

BlurImageFilter_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	filter := cast(^BlurImageFilter)object

	switch key {
	case "BlurRadius":
		datatypes.Push_UDim(
			L,
			datatype_registry,
			filter.blur_radius,
		)

	case "Enabled":
		vm.PushBoolean(
			L,
			filter.enabled,
		)

	case:
		return false
	}

	return true
}

BlurImageFilter_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	filter := cast(^BlurImageFilter)object

	switch key {
	case "BlurRadius":
		filter.blur_radius = datatypes.Arg_UDim(
			L,
			value_index,
			datatype_registry,
		)

	case "Enabled":
		filter.enabled = vm.ArgBoolean(
			L,
			value_index,
		)

	case:
		return false
	}

	return true
}

Register_BlurImageFilter :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&BlurImageFilter_Class,
		BlurImageFilter_construct,
		BlurImageFilter_destroy,
		get = BlurImageFilter_get,
		set = BlurImageFilter_set,
	)
}