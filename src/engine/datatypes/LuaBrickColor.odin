package datatypes

import "base:runtime"
import "core:fmt"

import vm "../vm"

push_brick_color :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding, value: BrickColor) {
	push_value(L, binding, value)
}

Push_BrickColor :: proc(L: ^vm.State, registry: ^Registry, value: BrickColor) {
	push_brick_color(L, &registry.brick_color, value)
}

Arg_BrickColor :: proc(L: ^vm.State, index: int, registry: ^Registry) -> BrickColor {
	if !vm.IsUserdataType(L, index, &registry.brick_color) {
		_ = vm.RaiseError(L, "expected BrickColor")
		return BrickColor_Gray
	}
	return (cast(^BrickColor)vm.UserdataValue(L, index))^
}

brick_color_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	binding := binding_from_upvalue(L)

	#partial switch vm.TypeOf(L, 1) {
	case .String:
		push_brick_color(L, binding, BrickColor_From_Name(vm.ArgString(L, 1)))
	case .Number, .Integer:
		push_brick_color(L, binding, BrickColor_From_Number(i32(vm.ArgNumber(L, 1))))
	case .Userdata:
		push_brick_color(L, binding, Arg_BrickColor(L, 1, registry_from_binding(binding)))
	case:
		return vm.RaiseError(L, "BrickColor.new expects a number, name, or BrickColor")
	}
	return 1
}

brick_color_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	brick_color := cast(^BrickColor)value
	registry := registry_from_binding(cast(^vm.Userdata_Binding)ctx)

	switch key {
	case "Number":
		vm.PushInteger(L, i64(brick_color.number))
	case "Name":
		vm.PushString(L, brick_color.name)
	case "Color":
		if registry == nil { return false }
		Push_Color3(L, registry, brick_color.color)
	case:
		return false
	}
	return true
}

brick_color_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^BrickColor)value).number == (cast(^BrickColor)other).number
}

brick_color_string :: proc(value, ctx: rawptr) -> string {
	return fmt.tprintf("%s", (cast(^BrickColor)value).name)
}

brick_color_destroy :: proc(value, ctx: rawptr) {
	free(cast(^BrickColor)value)
}

BrickColor_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name    = "BrickColor",
		get     = brick_color_get,
		string  = brick_color_string,
		destroy = brick_color_destroy,
		equal   = brick_color_equal,
	}
}

BrickColor_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "new", brick_color_new)

	push_brick_color(L, binding, BrickColor_White)
	vm.SetField(L, -2, "White")
	push_brick_color(L, binding, BrickColor_Black)
	vm.SetField(L, -2, "Black")
	push_brick_color(L, binding, BrickColor_Red)
	vm.SetField(L, -2, "Bright red")
	push_brick_color(L, binding, BrickColor_Blue)
	vm.SetField(L, -2, "Bright blue")
	push_brick_color(L, binding, BrickColor_Green)
	vm.SetField(L, -2, "Bright green")
	push_brick_color(L, binding, BrickColor_Gray)
	vm.SetField(L, -2, "Medium stone grey")
}
