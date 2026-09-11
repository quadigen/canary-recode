package datatypes

import "base:runtime"
import "core:fmt"
import engine_enums "../enum"
import vm "../vm"

push_font :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
	value: Font,
) {
	push_value(L, binding, Font_Clone(value))
}

Push_Font :: proc(
	L: ^vm.State,
	registry: ^Registry,
	value: Font,
) {
	push_font(L, &registry.font, value)
}

Arg_Font :: proc(
	L: ^vm.State,
	index: int,
	registry: ^Registry,
) -> Font {
	return require_font(L, index, &registry.font)^
}

require_font :: proc(
	L: ^vm.State,
	index: int,
	binding: ^vm.Userdata_Binding,
) -> ^Font {
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
		item := engine_enums.Arg_Item(
			L,
			2,
			registry.enums,
			"FontWeight",
		)
		weight = engine_enums.FontWeight(item.value)
	}

	style := engine_enums.FontStyle.Normal
	if !vm.IsNoneOrNil(L, 3) {
		item := engine_enums.Arg_Item(
			L,
			3,
			registry.enums,
			"FontStyle",
		)
		style = engine_enums.FontStyle(item.value)
	}

	value := Font_New(family, weight, style)
	defer Font_Destroy(&value)

	push_font(L, binding, value)
	return 1
}

font_get :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	key: string,
) -> bool {
	font := cast(^Font)value
	binding := cast(^vm.Userdata_Binding)ctx
	registry := registry_from_binding(binding)

	switch key {
	case "Family":
		vm.PushString(L, font.Family)

	case "Weight":
		if registry == nil || registry.enums == nil {
			return false
		}
		_ = engine_enums.Push_Item_By_Value(
			L,
			registry.enums,
			"FontWeight",
			i64(font.Weight),
		)

	case "Style":
		if registry == nil || registry.enums == nil {
			return false
		}
		_ = engine_enums.Push_Item_By_Value(
			L,
			registry.enums,
			"FontStyle",
			i64(font.Style),
		)

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

	return a.Family == b.Family &&
	       a.Weight == b.Weight &&
	       a.Style == b.Style
}

font_string :: proc(value, ctx: rawptr) -> string {
	font := cast(^Font)value
	return fmt.tprintf("%s", font.Family)
}

font_destroy :: proc(value, ctx: rawptr) {
	font := cast(^Font)value
	Font_Destroy(font)
	free(font)
}

Font_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name    = "Font",
		get     = font_get,
		string  = font_string,
		destroy = font_destroy,
		equal   = font_equal,
	}
}

Font_Install_Fields :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
) {
	add_library_function(L, binding, "new", font_new)
}
