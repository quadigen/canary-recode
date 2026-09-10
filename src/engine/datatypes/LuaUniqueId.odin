package datatypes

import "base:runtime"
import vm "../vm"

push_unique_id :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding, value: UniqueId) {
	push_value(L, binding, value)
}

Push_UniqueId :: proc(L: ^vm.State, registry: ^Registry, value: UniqueId) {
	push_unique_id(L, &registry.unique_id, value)
}

Arg_UniqueId :: proc(L: ^vm.State, index: int, registry: ^Registry) -> UniqueId {
	if !vm.IsUserdataType(L, index, &registry.unique_id) {
		_ = vm.RaiseError(L, "expected UniqueId")
		return {}
	}
	return (cast(^UniqueId)vm.UserdataValue(L, index))^
}

unique_id_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_unique_id(L, binding_from_upvalue(L), UniqueId_New())
	return 1
}

unique_id_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	id := cast(^UniqueId)value
	switch key {
	case "Random": vm.PushNumber(L, f64(id.Random))
	case "Time": vm.PushNumber(L, f64(id.Time))
	case "Index": vm.PushNumber(L, f64(id.Index))
	case: return false
	}
	return true
}

unique_id_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^UniqueId)value)^ == (cast(^UniqueId)other)^
}

unique_id_string :: proc(value, ctx: rawptr) -> string {
	return UniqueId_ToString((cast(^UniqueId)value)^)
}

unique_id_destroy :: proc(value, ctx: rawptr) {
	free(cast(^UniqueId)value)
}

UniqueId_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name    = "UniqueId",
		get     = unique_id_get,
		string  = unique_id_string,
		destroy = unique_id_destroy,
		equal   = unique_id_equal,
	}
}

UniqueId_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "new", unique_id_new)
}

