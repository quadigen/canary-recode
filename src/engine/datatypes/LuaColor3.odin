package datatypes

import "base:runtime"
import "core:fmt"
import vm "../vm"

push_color3 :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding, value: Color3) {
	push_value(L, binding, value)
}

Push_Color3 :: proc(L: ^vm.State, registry: ^Registry, value: Color3) {
	push_color3(L, &registry.color3, value)
}

Arg_Color3 :: proc(L: ^vm.State, index: int, registry: ^Registry) -> Color3 {
	return require_color3(L, index, &registry.color3)^
}

require_color3 :: proc(L: ^vm.State, index: int, binding: ^vm.Userdata_Binding) -> ^Color3 {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected Color3")
		return nil
	}
	return cast(^Color3)vm.UserdataValue(L, index)
}

color3_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	binding := binding_from_upvalue(L)
	push_color3(L, binding, New(
		f32(vm.ArgOptionalNumber(L, 1)),
		f32(vm.ArgOptionalNumber(L, 2)),
		f32(vm.ArgOptionalNumber(L, 3)),
	))
	return 1
}

color3_from_rgb :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_color3(L, binding_from_upvalue(L), FromRGB(
		f32(vm.ArgNumber(L, 1)),
		f32(vm.ArgNumber(L, 2)),
		f32(vm.ArgNumber(L, 3)),
	))
	return 1
}

color3_from_hsv :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_color3(L, binding_from_upvalue(L), FromHSV(
		f32(vm.ArgNumber(L, 1)),
		f32(vm.ArgNumber(L, 2)),
		f32(vm.ArgNumber(L, 3)),
	))
	return 1
}

color3_from_hex :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	value, ok := FromHex(vm.ArgString(L, 1))
	if !ok {
		return vm.RaiseError(L, "invalid Color3 hex string")
	}
	push_color3(L, binding_from_upvalue(L), value)
	return 1
}

color3_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	color := cast(^Color3)value
	switch key {
	case "R":
		vm.PushNumber(L, f64(color.R))
	case "G":
		vm.PushNumber(L, f64(color.G))
	case "B":
		vm.PushNumber(L, f64(color.B))
	case "Lerp", "ToHSV", "ToHex", "ToRGB":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

color3_namecall :: proc(L: ^vm.State, value, ctx: rawptr, method: string) -> (i32, bool) {
	color := cast(^Color3)value
	binding := cast(^vm.Userdata_Binding)ctx
	switch method {
	case "Lerp":
		goal := require_color3(L, 2, binding)
		push_color3(L, binding, Lerp(color^, goal^, f32(vm.ArgNumber(L, 3))))
		return 1, true
	case "ToHSV":
		h, s, v := ToHSV(color^)
		vm.PushNumber(L, f64(h))
		vm.PushNumber(L, f64(s))
		vm.PushNumber(L, f64(v))
		return 3, true
	case "ToHex":
		vm.PushString(L, ToHex(color^))
		return 1, true
	case "ToRGB":
		r, g, b := ToRGB(color^)
		vm.PushNumber(L, f64(r))
		vm.PushNumber(L, f64(g))
		vm.PushNumber(L, f64(b))
		return 3, true
	}
	return 0, false
}

color3_add :: proc(L: ^vm.State, value, ctx: rawptr, self_index, other_index: int) -> bool {
	binding := cast(^vm.Userdata_Binding)ctx
	other := require_color3(L, other_index, binding)
	a := cast(^Color3)value
	push_color3(L, binding, Color3{a.R+other.R, a.G+other.G, a.B+other.B})
	return true
}

color3_subtract :: proc(L: ^vm.State, value, ctx: rawptr, self_index, other_index: int) -> bool {
	binding := cast(^vm.Userdata_Binding)ctx
	other := require_color3(L, other_index, binding)
	a := cast(^Color3)value
	push_color3(L, binding, Color3{a.R-other.R, a.G-other.G, a.B-other.B})
	return true
}

color3_multiply :: proc(L: ^vm.State, value, ctx: rawptr, self_index, other_index: int) -> bool {
	binding := cast(^vm.Userdata_Binding)ctx
	a := cast(^Color3)value
	if vm.IsNumber(L, other_index) {
		scalar := f32(vm.ArgNumber(L, other_index))
		push_color3(L, binding, Color3{a.R*scalar, a.G*scalar, a.B*scalar})
		return true
	}
	other := require_color3(L, other_index, binding)
	push_color3(L, binding, Color3{a.R*other.R, a.G*other.G, a.B*other.B})
	return true
}

color3_divide :: proc(L: ^vm.State, value, ctx: rawptr, self_index, other_index: int) -> bool {
	binding := cast(^vm.Userdata_Binding)ctx
	a := cast(^Color3)value
	if vm.IsNumber(L, other_index) {
		scalar := f32(vm.ArgNumber(L, other_index))
		if self_index == 1 {
			push_color3(L, binding, Color3{a.R/scalar, a.G/scalar, a.B/scalar})
		} else {
			push_color3(L, binding, Color3{scalar/a.R, scalar/a.G, scalar/a.B})
		}
		return true
	}
	other := require_color3(L, other_index, binding)
	push_color3(L, binding, Color3{a.R/other.R, a.G/other.G, a.B/other.B})
	return true
}

color3_negate :: proc(L: ^vm.State, value, ctx: rawptr) -> bool {
	a := cast(^Color3)value
	push_color3(L, cast(^vm.Userdata_Binding)ctx, Color3{-a.R, -a.G, -a.B})
	return true
}

color3_equal :: proc(value, other, ctx: rawptr) -> bool {
	a, b := cast(^Color3)value, cast(^Color3)other
	return a^ == b^
}

color3_string :: proc(value, ctx: rawptr) -> string {
	color := cast(^Color3)value
	return fmt.tprintf("%g, %g, %g", color.R, color.G, color.B)
}

color3_destroy :: proc(value, ctx: rawptr) {
	free(cast(^Color3)value)
}

Color3_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name     = "Color3",
		get      = color3_get,
		namecall = color3_namecall,
		string   = color3_string,
		destroy  = color3_destroy,
		add      = color3_add,
		subtract = color3_subtract,
		multiply = color3_multiply,
		divide   = color3_divide,
		negate   = color3_negate,
		equal    = color3_equal,
	}
}

Color3_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "new", color3_new)
	add_library_function(L, binding, "fromRGB", color3_from_rgb)
	add_library_function(L, binding, "fromHSV", color3_from_hsv)
	add_library_function(L, binding, "fromHex", color3_from_hex)
	push_color3(L, binding, Color3{1, 1, 1})
	vm.SetField(L, -2, "white")
	push_color3(L, binding, Color3{})
	vm.SetField(L, -2, "black")
}

