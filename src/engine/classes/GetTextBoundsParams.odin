package classes

import "core:strings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

GetTextBoundsParams_Class := Class_Info{name = "GetTextBoundsParams", parent = &Instance_Class}

GetTextBoundsParams :: struct {
	using object: Object,
	text: string,
	font: datatypes.Font,
	size, width: f32,
	rich_text: bool,
}

text_bounds_params_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	params := new(GetTextBoundsParams)
	params.object = Object_Init(&GetTextBoundsParams_Class, "GetTextBoundsParams")
	params.font = datatypes.Font_New(DEFAULT_FONT)
	params.size = 14
	return &params.object
}

text_bounds_params_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	params := cast(^GetTextBoundsParams)object
	delete(params.text)
	datatypes.Font_Destroy(&params.font)
	Object_Destroy(object)
	free(params)
}

text_bounds_params_get :: proc(L: ^vm.State, object: ^Object, dt: ^datatypes.Registry, en: ^enums.Registry, key: string) -> bool {
	params := cast(^GetTextBoundsParams)object
	switch key {
	case "Text": vm.PushString(L, params.text)
	case "Font": datatypes.Push_Font(L, dt, params.font)
	case "Size": vm.PushNumber(L, f64(params.size))
	case "Width": vm.PushNumber(L, f64(params.width))
	case "RichText": vm.PushBoolean(L, params.rich_text)
	case: return false
	}
	return true
}

text_bounds_params_set :: proc(L: ^vm.State, object: ^Object, dt: ^datatypes.Registry, en: ^enums.Registry, key: string, index: int) -> bool {
	params := cast(^GetTextBoundsParams)object
	switch key {
	case "Text":
		value := strings.clone(vm.ArgString(L, index))
		delete(params.text)
		params.text = value
	case "Font":
		font := datatypes.Font_Clone(datatypes.Arg_Font(L, index, dt))
		datatypes.Font_Destroy(&params.font)
		params.font = font
	case "Size": params.size = f32(vm.ArgNumber(L, index))
	case "Width": params.width = f32(vm.ArgNumber(L, index))
	case "RichText": params.rich_text = vm.ArgBoolean(L, index)
	case: return false
	}
	return true
}

Register_GetTextBoundsParams :: proc(registry: ^Registry) {
	Register_Class(
		registry, &GetTextBoundsParams_Class, text_bounds_params_construct, text_bounds_params_destroy,
		get = text_bounds_params_get,
		set = text_bounds_params_set,
		properties = []string{"Text", "Font", "Size", "Width", "RichText"},
	)
}
