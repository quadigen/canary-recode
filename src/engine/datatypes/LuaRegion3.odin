package datatypes

import "base:runtime"
import "core:fmt"
import vm "../vm"

push_region3 :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
	value: Region3,
) {
	push_value(L, binding, value)
}

Push_Region3 :: proc(
	L: ^vm.State,
	registry: ^Registry,
	value: Region3,
) {
	push_region3(L, &registry.region3, value)
}

Arg_Region3 :: proc(
	L: ^vm.State,
	index: int,
	registry: ^Registry,
) -> Region3 {
	return require_region3(L, index, &registry.region3)^
}

require_region3 :: proc(
	L: ^vm.State,
	index: int,
	binding: ^vm.Userdata_Binding,
) -> ^Region3 {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected Region3")
		return nil
	}

	return cast(^Region3)vm.UserdataValue(L, index)
}

region3_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	min_x, min_y, min_z := vm.ArgVector3(L, 1)
	max_x, max_y, max_z := vm.ArgVector3(L, 2)

	push_region3(
		L,
		binding_from_upvalue(L),
		Region3_New(
			Vector3{min_x, min_y, min_z},
			Vector3{max_x, max_y, max_z},
		),
	)

	return 1
}

region3_get :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	key: string,
) -> bool {
	region := cast(^Region3)value
	binding := cast(^vm.Userdata_Binding)ctx
	registry := registry_from_binding(binding)

	switch key {
	case "Min":
		vm.PushVector3(L, region.Min.x, region.Min.y, region.Min.z)

	case "Max":
		vm.PushVector3(L, region.Max.x, region.Max.y, region.Max.z)

	case "Size":
		size := Region3_Size(region^)
		vm.PushVector3(L, size.x, size.y, size.z)

	case "CFrame":
		if registry == nil {
			return false
		}

		center := Region3_Center(region^)
		push_cframe(
			L,
			&registry.c_frame,
			CFrame_New_XYZ(center.x, center.y, center.z),
		)

	case "ExpandToGrid":
		vm.PushUserdataMethod(L, key)

	case:
		return false
	}

	return true
}

region3_namecall :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	method: string,
) -> (i32, bool) {
	region := cast(^Region3)value
	binding := cast(^vm.Userdata_Binding)ctx

	switch method {
	case "ExpandToGrid":
		resolution := f32(vm.ArgNumber(L, 2))
		expanded, ok := Region3_ExpandToGrid(region^, resolution)

		if !ok {
			return vm.RaiseError(L, "Region3 grid resolution must be greater than zero"), true
		}

		push_region3(L, binding, expanded)
		return 1, true
	}

	return 0, false
}

region3_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^Region3)value)^ == (cast(^Region3)other)^
}

region3_string :: proc(value, ctx: rawptr) -> string {
	region := cast(^Region3)value

	return fmt.tprintf(
		"%g, %g, %g; %g, %g, %g",
		region.Min.x,
		region.Min.y,
		region.Min.z,
		region.Max.x,
		region.Max.y,
		region.Max.z,
	)
}

region3_destroy :: proc(value, ctx: rawptr) {
	free(cast(^Region3)value)
}

Region3_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name     = "Region3",
		get      = region3_get,
		namecall = region3_namecall,
		string   = region3_string,
		destroy  = region3_destroy,
		equal    = region3_equal,
	}
}

Region3_Install_Fields :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
) {
	add_library_function(L, binding, "new", region3_new)
}
