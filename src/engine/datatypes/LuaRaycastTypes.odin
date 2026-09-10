package datatypes

import "base:runtime"
import "core:strings"
import engine_enums "../enum"
import vm "../vm"

release_instance_references :: proc(L: ^vm.State, references: ^[dynamic]Raycast_Instance_Reference) {
	for reference in references^ {
		vm.ReleaseValue(L, reference.lua_ref)
	}
	delete(references^)
	references^ = nil
}

read_instance_references :: proc(
	L: ^vm.State,
	index: int,
	references: ^[dynamic]Raycast_Instance_Reference,
) -> bool {
	release_instance_references(L, references)
	if vm.IsNoneOrNil(L, index) { return false }
	if !vm.IsTable(L, index) {
		_ = vm.RaiseError(L, "expected an array of Instances or nil")
		return false
	}

	count := vm.RawLen(L, index)
	for i in 0 ..< count {
		_ = vm.RawGetIndex(L, index, i+1)
		binding := vm.UserdataBindingOf(L, -1)
		if binding == nil || binding.name != "Instance" {
			vm.Pop(L)
			_ = vm.RaiseError(L, "raycast filters must contain Instances")
			return false
		}
		append(references, Raycast_Instance_Reference{
			object = vm.UserdataValue(L, -1),
			lua_ref = vm.RetainValue(L, -1),
		})
		vm.Pop(L)
	}
	return true
}

push_instance_references :: proc(L: ^vm.State, references: []Raycast_Instance_Reference) {
	vm.NewTable(L, len(references), 0)
	for reference, i in references {
		vm.PushRegistryReference(L, reference.lua_ref)
		vm.SetArrayValue(L, -2, i+1)
	}
}

require_raycast_params :: proc(L: ^vm.State, index: int, binding: ^vm.Userdata_Binding) -> ^RaycastParams {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected RaycastParams")
		return nil
	}
	return cast(^RaycastParams)vm.UserdataValue(L, index)
}

Arg_RaycastParams :: proc(L: ^vm.State, index: int, registry: ^Registry) -> ^RaycastParams {
	if registry == nil { return nil }
	return require_raycast_params(L, index, &registry.raycast_params)
}

raycast_params_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	value := RaycastParams_New()
	value.CollisionGroup = strings.clone(value.CollisionGroup)
	push_value(L, binding_from_upvalue(L), value)
	return 1
}

raycast_params_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	params := cast(^RaycastParams)value
	binding := cast(^vm.Userdata_Binding)ctx
	registry := registry_from_binding(binding)
	switch key {
	case "FilterDescendantsInstances": push_instance_references(L, params.FilterDescendantsInstances[:])
	case "ExcludeInstances":
		if !params.ExcludeFilterSet { vm.PushNil(L) } else { push_instance_references(L, params.ExcludeInstances[:]) }
	case "IncludeInstances":
		if !params.IncludeFilterSet { vm.PushNil(L) } else { push_instance_references(L, params.IncludeInstances[:]) }
	case "FilterType":
		if registry == nil || registry.enums == nil { return false }
		_ = engine_enums.Push_Item_By_Value(L, registry.enums, "RaycastFilterType", i64(params.FilterType))
	case "IgnoreWater": vm.PushBoolean(L, params.IgnoreWater)
	case "RespectCanCollide": vm.PushBoolean(L, params.RespectCanCollide)
	case "BruteForceAllSlow": vm.PushBoolean(L, params.BruteForceAllSlow)
	case "CollisionGroup": vm.PushString(L, params.CollisionGroup)
	case "AddToFilter": vm.PushUserdataMethod(L, key)
	case: return false
	}
	return true
}

raycast_params_set :: proc(L: ^vm.State, value, ctx: rawptr, key: string, value_index: int) -> bool {
	params := cast(^RaycastParams)value
	binding := cast(^vm.Userdata_Binding)ctx
	registry := registry_from_binding(binding)
	switch key {
	case "FilterDescendantsInstances":
		params.LegacyFilterSet = read_instance_references(L, value_index, &params.FilterDescendantsInstances)
	case "ExcludeInstances":
		params.ExcludeFilterSet = !vm.IsNoneOrNil(L, value_index)
		_ = read_instance_references(L, value_index, &params.ExcludeInstances)
	case "IncludeInstances":
		params.IncludeFilterSet = !vm.IsNoneOrNil(L, value_index)
		_ = read_instance_references(L, value_index, &params.IncludeInstances)
	case "FilterType":
		if registry == nil || registry.enums == nil { return false }
		item := engine_enums.Arg_Item(L, value_index, registry.enums, "RaycastFilterType")
		params.FilterType = engine_enums.RaycastFilterType(item.value)
	case "IgnoreWater": params.IgnoreWater = vm.ArgBoolean(L, value_index)
	case "RespectCanCollide": params.RespectCanCollide = vm.ArgBoolean(L, value_index)
	case "BruteForceAllSlow": params.BruteForceAllSlow = vm.ArgBoolean(L, value_index)
	case "CollisionGroup":
		delete(params.CollisionGroup)
		params.CollisionGroup = strings.clone(vm.ArgString(L, value_index))
	case: return false
	}
	return true
}

append_filter_argument :: proc(L: ^vm.State, index: int, references: ^[dynamic]Raycast_Instance_Reference) {
	if vm.IsTable(L, index) {
		count := vm.RawLen(L, index)
		for i in 0 ..< count {
			_ = vm.RawGetIndex(L, index, i+1)
			append_filter_argument(L, -1, references)
			vm.Pop(L)
		}
		return
	}
	binding := vm.UserdataBindingOf(L, index)
	if binding == nil || binding.name != "Instance" {
		_ = vm.RaiseError(L, "AddToFilter expects an Instance or array of Instances")
		return
	}
	append(references, Raycast_Instance_Reference{
		object = vm.UserdataValue(L, index),
		lua_ref = vm.RetainValue(L, index),
	})
}

raycast_params_namecall :: proc(L: ^vm.State, value, ctx: rawptr, method: string) -> (i32, bool) {
	if method != "AddToFilter" { return 0, false }
	params := cast(^RaycastParams)value
	append_filter_argument(L, 2, &params.FilterDescendantsInstances)
	params.LegacyFilterSet = true
	return 0, true
}

raycast_params_destroy :: proc(value, ctx: rawptr) {
	params := cast(^RaycastParams)value
	delete(params.FilterDescendantsInstances)
	delete(params.ExcludeInstances)
	delete(params.IncludeInstances)
	delete(params.CollisionGroup)
	free(params)
}

RaycastParams_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name = "RaycastParams",
		get = raycast_params_get,
		set = raycast_params_set,
		namecall = raycast_params_namecall,
		destroy = raycast_params_destroy,
	}
}

RaycastParams_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "new", raycast_params_new)
}

Push_RaycastResult :: proc(L: ^vm.State, registry: ^Registry, result: RaycastResult) {
	push_value(L, &registry.raycast_result, result)
}

raycast_result_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	result := cast(^RaycastResult)value
	binding := cast(^vm.Userdata_Binding)ctx
	registry := registry_from_binding(binding)
	switch key {
	case "Position": push_vector3(L, result.Position)
	case "Normal": push_vector3(L, result.Normal)
	case "Distance": vm.PushNumber(L, f64(result.Distance))
	case "Material":
		if registry == nil || registry.enums == nil { return false }
		_ = engine_enums.Push_Item_By_Value(L, registry.enums, "Material", i64(result.Material))
	case "Instance": vm.PushRegistryReference(L, result.InstanceRef)
	case: return false
	}
	return true
}

raycast_result_destroy :: proc(value, ctx: rawptr) {
	free(cast(^RaycastResult)value)
}

RaycastResult_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name = "RaycastResult",
		get = raycast_result_get,
		destroy = raycast_result_destroy,
	}
}

RaycastResult_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {}

