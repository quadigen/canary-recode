package datatypes

import "base:runtime"
import "core:fmt"
import vm "../vm"

push_region3int16 :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
	value: Region3int16,
) {
	push_value(L, binding, value)
}

Push_Region3int16 :: proc(
	L: ^vm.State,
	registry: ^Registry,
	value: Region3int16,
) {
	push_region3int16(L, &registry.region3int16, value)
}

Arg_Region3int16 :: proc(
	L: ^vm.State,
	index: int,
	registry: ^Registry,
) -> Region3int16 {
	return require_region3int16(L, index, &registry.region3int16)^
}

require_region3int16 :: proc(
	L: ^vm.State,
	index: int,
	binding: ^vm.Userdata_Binding,
) -> ^Region3int16 {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected Region3int16")
		return nil
	}
	return cast(^Region3int16)vm.UserdataValue(L, index)
}

region3int16_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	binding := binding_from_upvalue(L)
	registry := registry_from_binding(binding)
	if registry == nil {
		return vm.RaiseError(L, "Region3int16 registry is unavailable")
	}

	minimum := require_vector3int16(L, 1, &registry.vector3int16)
	maximum := require_vector3int16(L, 2, &registry.vector3int16)

	push_region3int16(
		L,
		binding,
		Region3int16_New(minimum^, maximum^),
	)
	return 1
}

region3int16_get :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	key: string,
) -> bool {
	region := cast(^Region3int16)value
	binding := cast(^vm.Userdata_Binding)ctx
	registry := registry_from_binding(binding)
	if registry == nil {
		return false
	}

	switch key {
	case "Min":
		push_vector3int16(L, &registry.vector3int16, region.Min)
	case "Max":
		push_vector3int16(L, &registry.vector3int16, region.Max)
	case "Size":
		push_vector3int16(
			L,
			&registry.vector3int16,
			Region3int16_Size(region^),
		)
	case:
		return false
	}

	return true
}

region3int16_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^Region3int16)value)^ ==
	       (cast(^Region3int16)other)^
}

region3int16_string :: proc(value, ctx: rawptr) -> string {
	region := cast(^Region3int16)value
	return fmt.tprintf(
		"%d, %d, %d; %d, %d, %d",
		region.Min.X,
		region.Min.Y,
		region.Min.Z,
		region.Max.X,
		region.Max.Y,
		region.Max.Z,
	)
}

region3int16_destroy :: proc(value, ctx: rawptr) {
	free(cast(^Region3int16)value)
}

Region3int16_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name    = "Region3int16",
		get     = region3int16_get,
		string  = region3int16_string,
		destroy = region3int16_destroy,
		equal   = region3int16_equal,
	}
}

Region3int16_Install_Fields :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
) {
	add_library_function(L, binding, "new", region3int16_new)
}
