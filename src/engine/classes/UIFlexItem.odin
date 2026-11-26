package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"

UIBase_Class := Class_Info {
	name   = "UIBase",
	parent = &Instance_Class,
}
UIComponent_Class := Class_Info {
	name   = "UIComponent",
	parent = &UIBase_Class,
}
UIFlexItem_Class := Class_Info {
	name   = "UIFlexItem",
	parent = &UIComponent_Class,
}

UIFlexItem :: struct {
	using object:        Object,
	flex_mode:           enums.UIFlexMode,
	grow_ratio:          f32,
	shrink_ratio:        f32,
	item_line_alignment: enums.ItemLineAlignment,
}

ui_flex_item_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	item := new(UIFlexItem)
	item^ = UIFlexItem {
		object       = Object_Init(&UIFlexItem_Class, "UIFlexItem"),
		grow_ratio   = 1,
		shrink_ratio = 1,
	}
	return &item.object
}

ui_flex_item_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^UIFlexItem)object)
}

ui_flex_item_get :: proc(
	L: ^vm.State,
	object: ^Object,
	dt: ^datatypes.Registry,
	registry: ^enums.Registry,
	key: string,
) -> bool {
	item := cast(^UIFlexItem)object
	switch key {
	case "FlexMode":
		_ = enums.Push_Item_By_Value(L, registry, "UIFlexMode", i64(item.flex_mode))
	case "GrowRatio":
		vm.PushNumber(L, f64(item.grow_ratio))
	case "ShrinkRatio":
		vm.PushNumber(L, f64(item.shrink_ratio))
	case "ItemLineAlignment":
		_ = enums.Push_Item_By_Value(
			L,
			registry,
			"ItemLineAlignment",
			i64(item.item_line_alignment),
		)
	case:
		return false
	}
	return true
}

ui_flex_item_set :: proc(
	L: ^vm.State,
	object: ^Object,
	dt: ^datatypes.Registry,
	registry: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	item := cast(^UIFlexItem)object
	switch key {
	case "FlexMode":
		item.flex_mode = enums.UIFlexMode(enums.Arg_Item(L, index, registry, "UIFlexMode").value)
	case "GrowRatio", "ShrinkRatio":
		value := vm.ArgNumber(L, index)
		if !(value >= 0 && value <= f64(math.F32_MAX)) {
			_ = vm.RaiseError(L, "flex ratios must be finite and non-negative")
			return true
		}
		if key == "GrowRatio" {item.grow_ratio = f32(value)} else {item.shrink_ratio = f32(value)}
	case "ItemLineAlignment":
		item.item_line_alignment = enums.ItemLineAlignment(
			enums.Arg_Item(L, index, registry, "ItemLineAlignment").value,
		)
	case:
		return false
	}
	gui_mark_layout_for(object)
	return true
}

ui_flex_item_clone :: proc(source, destination: ^Object) {
	src, dst := cast(^UIFlexItem)source, cast(^UIFlexItem)destination
	dst.flex_mode = src.flex_mode
	dst.grow_ratio = src.grow_ratio
	dst.shrink_ratio = src.shrink_ratio
	dst.item_line_alignment = src.item_line_alignment
}

Register_UIFlexItem :: proc(registry: ^Registry) {
	register_abstract_gui_class(registry, &UIBase_Class)
	register_abstract_gui_class(registry, &UIComponent_Class)
	Register_Class(
		registry,
		&UIFlexItem_Class,
		ui_flex_item_construct,
		ui_flex_item_destroy,
		get = ui_flex_item_get,
		set = ui_flex_item_set,
		clone = ui_flex_item_clone,
		properties = []string{"FlexMode", "GrowRatio", "ShrinkRatio", "ItemLineAlignment"},
	)
}
