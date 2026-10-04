package classes

import "core:strings"

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

UIPadding_Class := Class_Info{
	name   = "UIPadding",
	parent = &Instance_Class,
}

UIPadding :: struct {
	using object: Object,

	padding_left:    datatypes.UDim,
	padding_right:   datatypes.UDim,
	padding_top:     datatypes.UDim,
	padding_bottom:  datatypes.UDim,
}

UIPadding_Init :: proc() -> UIPadding {
	return UIPadding{
		object = Object_Init(&UIPadding_Class),
		padding_left   = datatypes.UDim{0, 0},
		padding_right  = datatypes.UDim{0, 0},
		padding_top    = datatypes.UDim{0, 0},
		padding_bottom = datatypes.UDim{0, 0},
	}
}

ui_padding_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	padding := cast(^UIPadding)object

	switch key {
	case "PaddingLeft":
		datatypes.Push_UDim(L, datatype_registry, padding.padding_left)
		return true
	case "PaddingRight":
		datatypes.Push_UDim(L, datatype_registry, padding.padding_right)
		return true
	case "PaddingTop":
		datatypes.Push_UDim(L, datatype_registry, padding.padding_top)
		return true
	case "PaddingBottom":
		datatypes.Push_UDim(L, datatype_registry, padding.padding_bottom)
		return true
	}

	return false
}

ui_padding_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	padding := cast(^UIPadding)object

	switch key {
	case "PaddingLeft":
		padding.padding_left = datatypes.Arg_UDim(L, value_index, datatype_registry)
		return true
	case "PaddingRight":
		padding.padding_right = datatypes.Arg_UDim(L, value_index, datatype_registry)
		return true
	case "PaddingTop":
		padding.padding_top = datatypes.Arg_UDim(L, value_index, datatype_registry)
		return true
	case "PaddingBottom":
		padding.padding_bottom = datatypes.Arg_UDim(L, value_index, datatype_registry)
		return true
	}

	return false
}

ui_padding_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	padding := new(UIPadding)
	padding^ = UIPadding_Init()
	padding.name = strings.clone("UIPadding")

	return &padding.object
}

ui_padding_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^UIPadding)object)
}

ui_padding_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^UIPadding)source
	dst := cast(^UIPadding)destination

	dst.padding_left   = src.padding_left
	dst.padding_right  = src.padding_right
	dst.padding_top    = src.padding_top
	dst.padding_bottom = src.padding_bottom
}

Register_UIPadding :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&UIPadding_Class,
		ui_padding_construct,
		ui_padding_destroy,
		get = ui_padding_get,
		set = ui_padding_set,
		clone = ui_padding_clone,
		properties = []string{
			"PaddingLeft",
			"PaddingRight",
			"PaddingTop",
			"PaddingBottom",
		},
	)
}