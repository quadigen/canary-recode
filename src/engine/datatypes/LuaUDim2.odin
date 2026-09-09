package datatypes

import "base:runtime"
import "core:fmt"
import vm "../vm"

push_udim2 :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding, value: UDim2) {
	push_value(L, binding, value)
}

Push_UDim2 :: proc(L: ^vm.State, registry: ^Registry, value: UDim2) {
	push_udim2(L, &registry.u_dim2, value)
}

Arg_UDim2 :: proc(L: ^vm.State, index: int, registry: ^Registry) -> UDim2 {
	return require_udim2(L, index, &registry.u_dim2)^
}

require_udim2 :: proc(L: ^vm.State, index: int, binding: ^vm.Userdata_Binding) -> ^UDim2 {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected UDim2")
		return nil
	}
	return cast(^UDim2)vm.UserdataValue(L, index)
}

udim2_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_udim2(L, binding_from_upvalue(L), UDim2_New(
		f32(vm.ArgOptionalNumber(L, 1)),
		f32(vm.ArgOptionalNumber(L, 2)),
		f32(vm.ArgOptionalNumber(L, 3)),
		f32(vm.ArgOptionalNumber(L, 4)),
	))
	return 1
}

udim2_from_scale :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_udim2(L, binding_from_upvalue(L), UDim2_FromScale(
		f32(vm.ArgNumber(L, 1)),
		f32(vm.ArgNumber(L, 2)),
	))
	return 1
}

udim2_from_offset :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_udim2(L, binding_from_upvalue(L), UDim2_FromOffset(
		f32(vm.ArgNumber(L, 1)),
		f32(vm.ArgNumber(L, 2)),
	))
	return 1
}

push_udim_component :: proc(L: ^vm.State, scale, offset: f32) {
	vm.NewTable(L, 0, 2)
	vm.PushNumber(L, f64(scale))
	vm.SetField(L, -2, "Scale")
	vm.PushNumber(L, f64(offset))
	vm.SetField(L, -2, "Offset")
	vm.SetReadOnly(L, -1)
}

udim2_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	udim := cast(^UDim2)value
	switch key {
	case "X":
		push_udim_component(L, udim.X_Scale, udim.X_Offset)
	case "Y":
		push_udim_component(L, udim.Y_Scale, udim.Y_Offset)
	case "XScale":
		vm.PushNumber(L, f64(udim.X_Scale))
	case "XOffset":
		vm.PushNumber(L, f64(udim.X_Offset))
	case "YScale":
		vm.PushNumber(L, f64(udim.Y_Scale))
	case "YOffset":
		vm.PushNumber(L, f64(udim.Y_Offset))
	case "Width":
		push_udim_component(L, udim.X_Scale, udim.X_Offset)
	case "Height":
		push_udim_component(L, udim.Y_Scale, udim.Y_Offset)
	case "Lerp", "FuzzyEq":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

udim2_namecall :: proc(L: ^vm.State, value, ctx: rawptr, method: string) -> (i32, bool) {
	udim := cast(^UDim2)value
	binding := cast(^vm.Userdata_Binding)ctx
	switch method {
	case "Lerp":
		goal := require_udim2(L, 2, binding)
		push_udim2(L, binding, UDim2_Lerp(udim^, goal^, f32(vm.ArgNumber(L, 3))))
		return 1, true
	case "FuzzyEq":
		other := require_udim2(L, 2, binding)
		vm.PushBoolean(L, UDim2_FuzzyEq(udim^, other^, f32(vm.ArgOptionalNumber(L, 3, 1.0e-5))))
		return 1, true
	}
	return 0, false
}

udim2_add :: proc(L: ^vm.State, value, ctx: rawptr, self_index, other_index: int) -> bool {
	binding := cast(^vm.Userdata_Binding)ctx
	push_udim2(L, binding, UDim2_Add((cast(^UDim2)value)^, require_udim2(L, other_index, binding)^))
	return true
}

udim2_subtract :: proc(L: ^vm.State, value, ctx: rawptr, self_index, other_index: int) -> bool {
	binding := cast(^vm.Userdata_Binding)ctx
	other := require_udim2(L, other_index, binding)^
	self := (cast(^UDim2)value)^
	if self_index == 1 {
		push_udim2(L, binding, UDim2_Subtract(self, other))
	} else {
		push_udim2(L, binding, UDim2_Subtract(other, self))
	}
	return true
}

udim2_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^UDim2)value)^ == (cast(^UDim2)other)^
}

udim2_string :: proc(value, ctx: rawptr) -> string {
	udim := cast(^UDim2)value
	return fmt.tprintf("{%g, %g}, {%g, %g}", udim.X_Scale, udim.X_Offset, udim.Y_Scale, udim.Y_Offset)
}

udim2_destroy :: proc(value, ctx: rawptr) {
	free(cast(^UDim2)value)
}

UDim2_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name     = "UDim2",
		get      = udim2_get,
		namecall = udim2_namecall,
		string   = udim2_string,
		destroy  = udim2_destroy,
		add      = udim2_add,
		subtract = udim2_subtract,
		equal    = udim2_equal,
	}
}

UDim2_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "new", udim2_new)
	add_library_function(L, binding, "fromScale", udim2_from_scale)
	add_library_function(L, binding, "fromOffset", udim2_from_offset)
	push_udim2(L, binding, UDim2_Zero)
	vm.SetField(L, -2, "zero")
}
