package datatypes

import "base:runtime"
import "core:fmt"
import vm "../vm"

push_rect :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding, value: Rect) {
	push_value(L, binding, value)
}

Push_Rect :: proc(L: ^vm.State, registry: ^Registry, value: Rect) {
	push_rect(L, &registry.rect, value)
}

rect_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	binding := binding_from_upvalue(L)
	registry := registry_from_binding(binding)
	result: Rect
	switch vm.StackTop(L) {
	case 0:
	case 2:
		if registry == nil { return vm.RaiseError(L, "Rect registry is unavailable") }
		result.Min = require_vector2(L, 1, &registry.vector2)^
		result.Max = require_vector2(L, 2, &registry.vector2)^
	case 4:
		result.Min = Vector2{f32(vm.ArgNumber(L, 1)), f32(vm.ArgNumber(L, 2))}
		result.Max = Vector2{f32(vm.ArgNumber(L, 3)), f32(vm.ArgNumber(L, 4))}
	case:
		return vm.RaiseError(L, "Rect.new expects zero, two, or four arguments")
	}
	push_rect(L, binding, result)
	return 1
}

rect_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	rect := cast(^Rect)value
	registry := registry_from_binding(cast(^vm.Userdata_Binding)ctx)
	switch key {
	case "Min":
		if registry == nil { return false }
		push_vector2(L, &registry.vector2, rect.Min)
	case "Max":
		if registry == nil { return false }
		push_vector2(L, &registry.vector2, rect.Max)
	case "Width": vm.PushNumber(L, f64(Rect_Width(rect^)))
	case "Height": vm.PushNumber(L, f64(Rect_Height(rect^)))
	case: return false
	}
	return true
}

rect_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^Rect)value)^ == (cast(^Rect)other)^
}

rect_string :: proc(value, ctx: rawptr) -> string {
	rect := cast(^Rect)value
	return fmt.tprintf("%g, %g, %g, %g", rect.Min.X, rect.Min.Y, rect.Max.X, rect.Max.Y)
}

rect_destroy :: proc(value, ctx: rawptr) {
	free(cast(^Rect)value)
}

Rect_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name    = "Rect",
		get     = rect_get,
		string  = rect_string,
		destroy = rect_destroy,
		equal   = rect_equal,
	}
}

Rect_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "new", rect_new)
}

