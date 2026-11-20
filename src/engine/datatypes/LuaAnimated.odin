package datatypes

import tracy "../util/odin-tracy"
import vm "../vm"
import "core:fmt"

Push_Animated :: proc(L: ^vm.State, registry: ^Registry, value: Animated) {
	push_value(L, &registry.animated, Animated_Clone(value))
}

Arg_Animated :: proc(L: ^vm.State, index: int, registry: ^Registry) -> Animated {
	if !vm.IsUserdataType(L, index, &registry.animated) {
		_ = vm.RaiseError(L, "expected Animated")
		return {}
	}
	return (cast(^Animated)vm.UserdataValue(L, index))^
}

animated_from_uri :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	push_value(L, binding_from_upvalue(L), Animated_From_URI(vm.ArgString(L, 1)))
	return 1
}

animated_from_buffer :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	data: []u8
	if vm.IsBuffer(L, 1) {
		data = vm.ArgBuffer(L, 1)
	} else if vm.TypeOf(L, 1) == .String {
		data = transmute([]u8)vm.ArgString(L, 1)
	} else {
		return vm.RaiseError(L, "expected an animation buffer or binary string")
	}
	value, ok := Animated_From_Bytes(data)
	if !ok {return vm.RaiseError(L, "unsupported or oversized animated image (expected GIF or Aseprite)")}
	push_value(L, binding_from_upvalue(L), value)
	return 1
}

animated_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	a := cast(^Animated)value
	switch key {
	case "Uri":
		vm.PushString(L, a.uri)
	case "IsUri":
		vm.PushBoolean(L, a.uri != "")
	case:
		return false
	}
	return true
}

animated_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^Animated)value).uri == (cast(^Animated)other).uri
}

animated_string :: proc(value, ctx: rawptr) -> string {
	return fmt.tprintf("%s", (cast(^Animated)value).uri)
}

animated_destroy :: proc(value, ctx: rawptr) {
	a := cast(^Animated)value
	delete(a.uri)
	free(a)
}

Animated_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return {
		name = "Animated",
		get = animated_get,
		string = animated_string,
		destroy = animated_destroy,
		equal = animated_equal,
	}
}

Animated_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "fromUri", animated_from_uri)
	add_library_function(L, binding, "fromBuffer", animated_from_buffer)
	add_library_function(L, binding, "fromBytes", animated_from_buffer)
}
