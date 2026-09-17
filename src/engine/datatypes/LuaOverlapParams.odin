package datatypes

import "base:runtime"
import "core:strings"

import engine_enums "../enum"
import vm "../vm"

require_overlap_params :: proc(
	L: ^vm.State,
	index: int,
	binding: ^vm.Userdata_Binding,
) -> ^OverlapParams {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected OverlapParams")
		return nil
	}

	return cast(^OverlapParams)vm.UserdataValue(L, index)
}

Arg_OverlapParams :: proc(
	L: ^vm.State,
	index: int,
	registry: ^Registry,
) -> ^OverlapParams {
	if registry == nil {
		return nil
	}

	return require_overlap_params(
		L,
		index,
		&registry.overlap_params,
	)
}

overlap_params_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	value := OverlapParams_New()
	value.CollisionGroup = strings.clone(value.CollisionGroup)

	push_value(
		L,
		binding_from_upvalue(L),
		value,
	)

	return 1
}

overlap_params_get :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	key: string,
) -> bool {
	params := cast(^OverlapParams)value
	binding := cast(^vm.Userdata_Binding)ctx
	registry := registry_from_binding(binding)

	switch key {
	case "FilterDescendantsInstances":
		push_instance_references(
			L,
			params.FilterDescendantsInstances[:],
		)

	case "ExcludeInstances":
		if !params.ExcludeFilterSet {
			vm.PushNil(L)
		} else {
			push_instance_references(
				L,
				params.ExcludeInstances[:],
			)
		}

	case "IncludeInstances":
		if !params.IncludeFilterSet {
			vm.PushNil(L)
		} else {
			push_instance_references(
				L,
				params.IncludeInstances[:],
			)
		}

	case "FilterType":
		if registry == nil || registry.enums == nil {
			return false
		}

		_ = engine_enums.Push_Item_By_Value(
			L,
			registry.enums,
			"RaycastFilterType",
			i64(params.FilterType),
		)

	case "MaxParts":
		vm.PushInteger(L, i64(params.MaxParts))

	case "CollisionGroup":
		vm.PushString(L, params.CollisionGroup)

	case "Tolerance":
		vm.PushNumber(L, f64(params.Tolerance))

	case "RespectCanCollide":
		vm.PushBoolean(L, params.RespectCanCollide)

	case "BruteForceAllSlow":
		vm.PushBoolean(L, params.BruteForceAllSlow)

	case "AddToFilter":
		vm.PushUserdataMethod(L, key)

	case:
		return false
	}

	return true
}

overlap_params_set :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	key: string,
	value_index: int,
) -> bool {
	params := cast(^OverlapParams)value
	binding := cast(^vm.Userdata_Binding)ctx
	registry := registry_from_binding(binding)

	switch key {
	case "FilterDescendantsInstances":
		params.LegacyFilterSet = read_instance_references(
			L,
			value_index,
			&params.FilterDescendantsInstances,
		)

	case "ExcludeInstances":
		params.ExcludeFilterSet = !vm.IsNoneOrNil(
			L,
			value_index,
		)

		_ = read_instance_references(
			L,
			value_index,
			&params.ExcludeInstances,
		)

	case "IncludeInstances":
		params.IncludeFilterSet = !vm.IsNoneOrNil(
			L,
			value_index,
		)

		_ = read_instance_references(
			L,
			value_index,
			&params.IncludeInstances,
		)

	case "FilterType":
		if registry == nil || registry.enums == nil {
			return false
		}

		item := engine_enums.Arg_Item(
			L,
			value_index,
			registry.enums,
			"RaycastFilterType",
		)

		params.FilterType = engine_enums.RaycastFilterType(
			item.value,
		)

	case "MaxParts":
		max_parts := vm.ArgInteger(L, value_index)

		if max_parts < 0 {
			_ = vm.RaiseError(
				L,
				"MaxParts must be greater than or equal to 0",
			)
			return true
		}

		params.MaxParts = i32(max_parts)

	case "CollisionGroup":
		delete(params.CollisionGroup)

		params.CollisionGroup = strings.clone(
			vm.ArgString(L, value_index),
		)

	case "Tolerance":
		params.Tolerance = clamp(
			f32(vm.ArgNumber(L, value_index)),
			0,
			0.05,
		)

	case "RespectCanCollide":
		params.RespectCanCollide = vm.ArgBoolean(
			L,
			value_index,
		)

	case "BruteForceAllSlow":
		params.BruteForceAllSlow = vm.ArgBoolean(
			L,
			value_index,
		)

	case:
		return false
	}

	return true
}

overlap_params_namecall :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	method: string,
) -> (i32, bool) {
	if method != "AddToFilter" {
		return 0, false
	}

	params := cast(^OverlapParams)value

	append_filter_argument(
		L,
		2,
		&params.FilterDescendantsInstances,
	)

	params.LegacyFilterSet = true

	return 0, true
}

overlap_params_destroy :: proc(value, ctx: rawptr) {
	params := cast(^OverlapParams)value

	delete(params.FilterDescendantsInstances)
	delete(params.ExcludeInstances)
	delete(params.IncludeInstances)
	delete(params.CollisionGroup)

	free(params)
}

OverlapParams_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name     = "OverlapParams",
		get      = overlap_params_get,
		set      = overlap_params_set,
		namecall = overlap_params_namecall,
		destroy  = overlap_params_destroy,
	}
}

OverlapParams_Install_Fields :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
) {
	add_library_function(
		L,
		binding,
		"new",
		overlap_params_new,
	)
}