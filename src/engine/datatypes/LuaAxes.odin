package datatypes

import "base:runtime"
import "core:fmt"
import engine_enums "../enum"
import vm "../vm"

push_axes :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding, value: Axes) {
	push_value(L, binding, value)
}

Push_Axes :: proc(L: ^vm.State, registry: ^Registry, value: Axes) {
	push_axes(L, &registry.axes, value)
}

Arg_Axes :: proc(L: ^vm.State, index: int, registry: ^Registry) -> Axes {
	return require_axes(L, index, &registry.axes)^
}

require_axes :: proc(
	L: ^vm.State,
	index: int,
	binding: ^vm.Userdata_Binding,
) -> ^Axes {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected Axes")
		return nil
	}
	return cast(^Axes)vm.UserdataValue(L, index)
}

axes_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	binding := binding_from_upvalue(L)
	registry := registry_from_binding(binding)
	if registry == nil || registry.enums == nil {
		return vm.RaiseError(L, "Axes enum registry is unavailable")
	}

	result := Axes{}

	for index in 1 ..= 3 {
		if vm.IsNoneOrNil(L, index) {
			break
		}

		item := engine_enums.Arg_Item(L, index, registry.enums, "Axis")
		switch engine_enums.Axis(item.value) {
		case .X:
			result.X = true
		case .Y:
			result.Y = true
		case .Z:
			result.Z = true
		}
	}

	push_axes(L, binding, result)
	return 1
}

axes_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	axes := cast(^Axes)value

	switch key {
	case "X":
		vm.PushBoolean(L, axes.X)
	case "Y":
		vm.PushBoolean(L, axes.Y)
	case "Z":
		vm.PushBoolean(L, axes.Z)
	case:
		return false
	}

	return true
}

axes_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^Axes)value)^ == (cast(^Axes)other)^
}

axes_string :: proc(value, ctx: rawptr) -> string {
	axes := cast(^Axes)value
	return fmt.tprintf("X=%v, Y=%v, Z=%v", axes.X, axes.Y, axes.Z)
}

axes_destroy :: proc(value, ctx: rawptr) {
	free(cast(^Axes)value)
}

Axes_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name    = "Axes",
		get     = axes_get,
		string  = axes_string,
		destroy = axes_destroy,
		equal   = axes_equal,
	}
}

Axes_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "new", axes_new)

	push_axes(L, binding, Axes_None)
	vm.SetField(L, -2, "none")

	push_axes(L, binding, Axes_All)
	vm.SetField(L, -2, "all")
}
