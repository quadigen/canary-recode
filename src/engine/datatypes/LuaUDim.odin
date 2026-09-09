package datatypes

import "base:runtime"
import "core:fmt"
import vm "../vm"

push_udim :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding, value: UDim) {
	push_value(L, binding, value)
}

Push_UDim :: proc(L: ^vm.State, registry: ^Registry, value: UDim) {
	push_udim(L, &registry.u_dim, value)
}

Arg_UDim :: proc(L: ^vm.State, index: int, registry: ^Registry) -> UDim {
	return require_udim(L, index, &registry.u_dim)^
}

require_udim :: proc(L: ^vm.State, index: int, binding: ^vm.Userdata_Binding) -> ^UDim {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected UDim")
		return nil
	}
	return cast(^UDim)vm.UserdataValue(L, index)
}

udim_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_udim(L, binding_from_upvalue(L), UDim_New(
		f32(vm.ArgOptionalNumber(L, 1)),
		f32(vm.ArgOptionalNumber(L, 2)),
	))
	return 1
}

udim_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	udim := cast(^UDim)value
	switch key {
	case "Scale":
		vm.PushNumber(L, f64(udim.Scale))
	case "Offset":
		vm.PushNumber(L, f64(udim.Offset))
	case "Lerp", "FuzzyEq":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

udim_namecall :: proc(L: ^vm.State, value, ctx: rawptr, method: string) -> (i32, bool) {
	udim := cast(^UDim)value
	binding := cast(^vm.Userdata_Binding)ctx
	switch method {
	case "Lerp":
		goal := require_udim(L, 2, binding)
		push_udim(L, binding, UDim_Lerp(udim^, goal^, f32(vm.ArgNumber(L, 3))))
		return 1, true
	case "FuzzyEq":
		other := require_udim(L, 2, binding)
		vm.PushBoolean(L, UDim_FuzzyEq(udim^, other^, f32(vm.ArgOptionalNumber(L, 3, 1.0e-5))))
		return 1, true
	}
	return 0, false
}

udim_add :: proc(L: ^vm.State, value, ctx: rawptr, self_index, other_index: int) -> bool {
	binding := cast(^vm.Userdata_Binding)ctx
	push_udim(L, binding, UDim_Add((cast(^UDim)value)^, require_udim(L, other_index, binding)^))
	return true
}

udim_subtract :: proc(L: ^vm.State, value, ctx: rawptr, self_index, other_index: int) -> bool {
	binding := cast(^vm.Userdata_Binding)ctx
	other := require_udim(L, other_index, binding)^
	self := (cast(^UDim)value)^
	if self_index == 1 {
		push_udim(L, binding, UDim_Subtract(self, other))
	} else {
		push_udim(L, binding, UDim_Subtract(other, self))
	}
	return true
}

udim_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^UDim)value)^ == (cast(^UDim)other)^
}

udim_string :: proc(value, ctx: rawptr) -> string {
	udim := cast(^UDim)value
	return fmt.tprintf("{%g, %g}", udim.Scale, udim.Offset)
}

udim_destroy :: proc(value, ctx: rawptr) {
	free(cast(^UDim)value)
}

UDim_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name     = "UDim",
		get      = udim_get,
		namecall = udim_namecall,
		string   = udim_string,
		destroy  = udim_destroy,
		add      = udim_add,
		subtract = udim_subtract,
		equal    = udim_equal,
	}
}

UDim_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "new", udim_new)
	push_udim(L, binding, UDim_Zero)
	vm.SetField(L, -2, "zero")
}
