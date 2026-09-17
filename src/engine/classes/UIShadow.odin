package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

UIShadow_Class := Class_Info{
	name   = "UIShadow",
	parent = &Instance_Class,
}

UIShadow :: struct {
	using object: Object,

	blur_radius:  datatypes.UDim,
	color:        datatypes.Color3,
	enabled:      bool,
	offset:       datatypes.UDim2,
	spread:       datatypes.UDim2,
	transparency: f64,
	zindex:       f64,
	exponent:     f64,
	showfortext:  bool
}

UIShadow_Init :: proc() -> UIShadow {
	return UIShadow{
		object = Object_Init(&UIShadow_Class),
		blur_radius = datatypes.UDim{Scale = 0, Offset = 12},
		color = datatypes.Color3{R = 0, G = 0, B = 0},
		enabled = true,
		offset = datatypes.UDim2{
			X_Scale = 0, X_Offset = 0,
			Y_Scale = 0, Y_Offset = 4,
		},
		spread = datatypes.UDim2{},
		transparency = 0.35,
		zindex = 0,
		exponent = 2,
		showfortext = false,
	}
}

UIShadow_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	shadow := new(UIShadow)
	shadow^ = UIShadow_Init()
	shadow.name = "UIShadow"
	return &shadow.object
}

UIShadow_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^UIShadow)object)
}

UIShadow_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	shadow := cast(^UIShadow)object

	switch key {
	case "BlurRadius":
		if datatype_registry == nil { return false }
		datatypes.Push_UDim(L, datatype_registry, shadow.blur_radius)
	case "Offset":
		if datatype_registry == nil { return false }
		datatypes.Push_UDim2(L, datatype_registry, shadow.offset)
	case "Spread":
		if datatype_registry == nil { return false }
		datatypes.Push_UDim2(L, datatype_registry, shadow.spread)
	case "Color3":
		if datatype_registry == nil { return false }
		datatypes.Push_Color3(L, datatype_registry, shadow.color)
	case "Transparency":
		vm.PushNumber(L, shadow.transparency)
	case "Exponent":
		vm.PushNumber(L, shadow.exponent)
	case "ZIndex":
		vm.PushNumber(L, shadow.zindex)
	case "Enabled":
		vm.PushBoolean(L, shadow.enabled)
	case "ShowForText":
		vm.PushBoolean(L, shadow.showfortext)
	case:
		return false
	}
	return true
}

UIShadow_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	shadow := cast(^UIShadow)object

	switch key {
	case "BlurRadius":
		if datatype_registry == nil { return false }
		shadow.blur_radius = datatypes.Arg_UDim(L, value_index, datatype_registry)
	case "Offset":
		if datatype_registry == nil { return false }
		shadow.offset = datatypes.Arg_UDim2(L, value_index, datatype_registry)
	case "Spread":
		if datatype_registry == nil { return false }
		shadow.spread = datatypes.Arg_UDim2(L, value_index, datatype_registry)
	case "Color3":
		if datatype_registry == nil { return false }
		shadow.color = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case "Transparency":
		shadow.transparency = clamp(vm.ArgNumber(L, value_index), 0.0, 1.0)
	case "Exponent":
		shadow.exponent = max(1.0, vm.ArgNumber(L, value_index))
	case "ZIndex":
		shadow.zindex = vm.ArgNumber(L, value_index)
	case "Enabled":
		shadow.enabled = vm.ArgBoolean(L, value_index)
	case "ShowForText":
		shadow.showfortext = vm.ArgBoolean(L, value_index)
	case:
		return false
	}
	return true
}

UIShadow_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^UIShadow)source
	dst := cast(^UIShadow)destination

	dst.blur_radius  = src.blur_radius
	dst.color        = src.color
	dst.enabled      = src.enabled
	dst.offset       = src.offset
	dst.spread       = src.spread
	dst.transparency = src.transparency
	dst.zindex       = src.zindex
	dst.exponent     = src.exponent
}

Register_UIShadow :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&UIShadow_Class,
		UIShadow_construct,
		UIShadow_destroy,
		get = UIShadow_get,
		set = UIShadow_set,
		clone = UIShadow_clone,
		properties = []string{"ShowForText", "Offset", "Exponent", "BlurRadius", "Spread", "ZIndex", "Transparency", "Color3", "Enabled"},
	)
}