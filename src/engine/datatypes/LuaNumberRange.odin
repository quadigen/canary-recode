package datatypes

import "base:runtime"
import "core:fmt"
import vm "../vm"

push_number_range :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding, value: NumberRange) {
	push_value(L, binding, value)
}

Push_NumberRange :: proc(L: ^vm.State, registry: ^Registry, value: NumberRange) {
	push_number_range(L, &registry.number_range, value)
}

number_range_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	minimum := f32(vm.ArgNumber(L, 1))
	maximum := minimum
	if !vm.IsNoneOrNil(L, 2) {
		maximum = f32(vm.ArgNumber(L, 2))
	}
	value, ok := NumberRange_New2(minimum, maximum)
	if !ok {
		return vm.RaiseError(L, "NumberRange minimum must be less than or equal to maximum")
	}
	push_number_range(L, binding_from_upvalue(L), value)
	return 1
}

number_range_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	range := cast(^NumberRange)value
	switch key {
	case "Min": vm.PushNumber(L, f64(range.Min))
	case "Max": vm.PushNumber(L, f64(range.Max))
	case: return false
	}
	return true
}

number_range_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^NumberRange)value)^ == (cast(^NumberRange)other)^
}

number_range_string :: proc(value, ctx: rawptr) -> string {
	range := cast(^NumberRange)value
	return fmt.tprintf("%g, %g", range.Min, range.Max)
}

number_range_destroy :: proc(value, ctx: rawptr) {
	free(cast(^NumberRange)value)
}

NumberRange_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name    = "NumberRange",
		get     = number_range_get,
		string  = number_range_string,
		destroy = number_range_destroy,
		equal   = number_range_equal,
	}
}

NumberRange_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "new", number_range_new)
}
