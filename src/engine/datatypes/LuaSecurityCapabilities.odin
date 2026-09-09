package datatypes

import "base:runtime"
import engine_enums "../enum"
import vm "../vm"

push_security_capabilities :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding, value: SecurityCapabilities) {
	push_value(L, binding, value)
}

Push_SecurityCapabilities :: proc(L: ^vm.State, registry: ^Registry, value: SecurityCapabilities) {
	push_security_capabilities(L, &registry.security_capabilities, value)
}

Arg_SecurityCapabilities :: proc(L: ^vm.State, index: int, registry: ^Registry) -> SecurityCapabilities {
	if registry == nil || !vm.IsUserdataType(L, index, &registry.security_capabilities) {
		_ = vm.RaiseError(L, "expected SecurityCapabilities")
		return {}
	}
	return (cast(^SecurityCapabilities)vm.UserdataValue(L, index))^
}

security_capabilities_arguments :: proc(
	L: ^vm.State,
	registry: ^Registry,
	start_index: int,
) -> SecurityCapabilities {
	result: SecurityCapabilities
	for index := start_index; index <= vm.StackTop(L); index += 1 {
		if vm.IsUserdataType(L, index, &registry.security_capabilities) {
			result = SecurityCapabilities_Add(result, (cast(^SecurityCapabilities)vm.UserdataValue(L, index))^)
			continue
		}
		item := engine_enums.Arg_Item(L, index, registry.enums, "SecurityCapability")
		result = SecurityCapabilities_Add_Value(result, item.value)
	}
	return result
}

security_capabilities_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	binding := binding_from_upvalue(L)
	registry := registry_from_binding(binding)
	if registry == nil || registry.enums == nil {
		return vm.RaiseError(L, "SecurityCapabilities enum registry is unavailable")
	}
	push_security_capabilities(L, binding, security_capabilities_arguments(L, registry, 1))
	return 1
}

security_capabilities_from_current :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_security_capabilities(L, binding_from_upvalue(L), SECURITY_CAPABILITIES_ALL)
	return 1
}

security_capabilities_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	switch key {
	case "Add", "Remove", "Contains": vm.PushUserdataMethod(L, key)
	case: return false
	}
	return true
}

security_capabilities_namecall :: proc(L: ^vm.State, value, ctx: rawptr, method: string) -> (i32, bool) {
	binding := cast(^vm.Userdata_Binding)ctx
	registry := registry_from_binding(binding)
	if registry == nil || registry.enums == nil {
		return vm.RaiseError(L, "SecurityCapabilities enum registry is unavailable"), true
	}
	current := (cast(^SecurityCapabilities)value)^
	arguments := security_capabilities_arguments(L, registry, 2)
	switch method {
	case "Add":
		push_security_capabilities(L, binding, SecurityCapabilities_Add(current, arguments))
		return 1, true
	case "Remove":
		push_security_capabilities(L, binding, SecurityCapabilities_Remove(current, arguments))
		return 1, true
	case "Contains":
		vm.PushBoolean(L, SecurityCapabilities_Contains(current, arguments))
		return 1, true
	}
	return 0, false
}

security_capabilities_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^SecurityCapabilities)value)^ == (cast(^SecurityCapabilities)other)^
}

security_capabilities_string :: proc(value, ctx: rawptr) -> string {
	return "SecurityCapabilities"
}

security_capabilities_destroy :: proc(value, ctx: rawptr) {
	free(cast(^SecurityCapabilities)value)
}

SecurityCapabilities_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name     = "SecurityCapabilities",
		get      = security_capabilities_get,
		namecall = security_capabilities_namecall,
		string   = security_capabilities_string,
		destroy  = security_capabilities_destroy,
		equal    = security_capabilities_equal,
	}
}

SecurityCapabilities_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "new", security_capabilities_new)
	add_library_function(L, binding, "fromCurrent", security_capabilities_from_current)
}
