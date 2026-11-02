package datatypes

import engine_enums "../enum"
import vm "../vm"
import "base:runtime"
import "core:fmt"

push_font :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding, value: Font) {
	push_value(L, binding, Font_Clone(value))
}

Push_Font :: proc(L: ^vm.State, registry: ^Registry, value: Font) {
	push_font(L, &registry.font, value)
}

Arg_Font :: proc(L: ^vm.State, index: int, registry: ^Registry) -> Font {
	return require_font(L, index, &registry.font)^
}

require_font :: proc(L: ^vm.State, index: int, binding: ^vm.Userdata_Binding) -> ^Font {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected Font")
		return nil
	}
	return cast(^Font)vm.UserdataValue(L, index)
}

font_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	binding := binding_from_upvalue(L)
	registry := registry_from_binding(binding)
	if registry == nil || registry.enums == nil {
		return vm.RaiseError(L, "Font enum registry is unavailable")
	}

	family := vm.ArgString(L, 1)

	weight := engine_enums.FontWeight.Regular
	if !vm.IsNoneOrNil(L, 2) {
		item := engine_enums.Arg_Item(L, 2, registry.enums, "FontWeight")
		weight = engine_enums.FontWeight(item.value)
	}

	style := engine_enums.FontStyle.Normal
	if !vm.IsNoneOrNil(L, 3) {
		item := engine_enums.Arg_Item(L, 3, registry.enums, "FontStyle")
		style = engine_enums.FontStyle(item.value)
	}

	value := Font_New(family, weight, style)
	defer Font_Destroy(&value)

	push_font(L, binding, value)
	return 1
}

font_from_enum :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	binding := binding_from_upvalue(L)
	registry := registry_from_binding(binding)
	if registry == nil || registry.enums == nil {
		return vm.RaiseError(L, "Font enum registry is unavailable")
	}

	item := engine_enums.Arg_Item(L, 1, registry.enums, "Font")
	if item == nil {
		return vm.RaiseError(L, "expected Enum.Font")
	}

	push_font(L, binding, Font_From_Enum(engine_enums.Font(item.value)))
	return 1
}

font_from_name :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	binding := binding_from_upvalue(L)
	registry := registry_from_binding(binding)
	if registry == nil || registry.enums == nil {
		return vm.RaiseError(L, "Font enum registry is unavailable")
	}

	family := vm.ArgString(L, 1)
	if item := engine_enums.Enum_Item_By_Name(registry.enums, "Font", family); item != nil {
		push_font(L, binding, Font_From_Enum(engine_enums.Font(item.value)))
		return 1
	}

	push_font(L, binding, Font_New(family))
	return 1
}


font_from_memory :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	binding := binding_from_upvalue(L)

	data: []u8
	if vm.IsBuffer(L, 1) {
		data = vm.ArgBuffer(L, 1)
	} else if !vm.IsNoneOrNil(L, 1) {
		text := vm.ArgString(L, 1)
		data = transmute([]u8)text
	} else {
		return vm.RaiseError(L, "Font.fromMemory expects a buffer or string of font data")
	}

	if len(data) == 0 {
		return vm.RaiseError(L, "Font.fromMemory expects non-empty font data")
	}

	registry := registry_from_binding(binding)

	weight := engine_enums.FontWeight.Regular
	if !vm.IsNoneOrNil(L, 2) {
		if registry == nil || registry.enums == nil {
			return vm.RaiseError(L, "Font enum registry is unavailable")
		}
		item := engine_enums.Arg_Item(L, 2, registry.enums, "FontWeight")
		if item == nil {
			return vm.RaiseError(L, "expected an Enum.FontWeight")
		}
		weight = engine_enums.FontWeight(item.value)
	}

	style := engine_enums.FontStyle.Normal
	if !vm.IsNoneOrNil(L, 3) {
		if registry == nil || registry.enums == nil {
			return vm.RaiseError(L, "Font enum registry is unavailable")
		}
		item := engine_enums.Arg_Item(L, 3, registry.enums, "FontStyle")
		if item == nil {
			return vm.RaiseError(L, "expected an Enum.FontStyle")
		}
		style = engine_enums.FontStyle(item.value)
	}

	value, ok := Font_From_Memory(data, weight, style)
	if !ok {
		return vm.RaiseError(L, "Font.fromMemory could not copy the font data")
	}
	defer Font_Destroy(&value)

	push_font(L, binding, value)
	return 1
}

font_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	font := cast(^Font)value
	binding := cast(^vm.Userdata_Binding)ctx
	registry := registry_from_binding(binding)

	switch key {
	case "Family":
		vm.PushString(L, font.Family)

	case "FromMemory":
		vm.PushBoolean(L, Font_Has_Memory(font^))

	case "Weight":
		if registry == nil || registry.enums == nil {
			return false
		}
		_ = engine_enums.Push_Item_By_Value(L, registry.enums, "FontWeight", i64(font.Weight))

	case "Style":
		if registry == nil || registry.enums == nil {
			return false
		}
		_ = engine_enums.Push_Item_By_Value(L, registry.enums, "FontStyle", i64(font.Style))

	case "Bold":
		vm.PushBoolean(L, i64(font.Weight) >= 600)

	case:
		return false
	}

	return true
}

font_equal :: proc(value, other, ctx: rawptr) -> bool {
	a := cast(^Font)value
	b := cast(^Font)other

	return a.Family == b.Family && a.Weight == b.Weight && a.Style == b.Style
}

font_string :: proc(value, ctx: rawptr) -> string {
	font := cast(^Font)value


	if Font_Has_Memory(font^) {
		return fmt.tprintf(
			"Font.fromMemory(%d bytes, %v, %v)",
			len(font.Data),
			font.Weight,
			font.Style,
		)
	}
	return fmt.tprintf("%s", font.Family)
}

font_destroy :: proc(value, ctx: rawptr) {
	font := cast(^Font)value
	Font_Destroy(font)
	free(font)
}

Font_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding {
		name = "Font",
		get = font_get,
		string = font_string,
		destroy = font_destroy,
		equal = font_equal,
	}
}

Font_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "new", font_new)
	add_library_function(L, binding, "fromEnum", font_from_enum)
	add_library_function(L, binding, "fromName", font_from_name)
	add_library_function(L, binding, "fromMemory", font_from_memory)
}
