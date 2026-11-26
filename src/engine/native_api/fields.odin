package native_api

import datatypes "../datatypes"
import vm "../vm"
import odin_runtime "base:runtime"
import "core:strings"

native_allocated_strings: map[uintptr]cstring

native_field_get :: proc(
	L: ^vm.State,
	datatype_registry: ^datatypes.Registry,
	kind: Property_Kind,
	address: uintptr,
) -> bool {
	context = odin_runtime.default_context()
	#partial switch kind {
	case .Boolean:
		vm.PushBoolean(L, (cast(^bool)address)^)
	case .Number:
		vm.PushNumber(L, (cast(^f64)address)^)
	case .Integer:
		vm.PushInteger(L, (cast(^i64)address)^)
	case .String:
		value := (cast(^cstring)address)^
		if value == nil {vm.PushString(L, "")} else {vm.PushString(L, string(value))}
	case .Vector3:
		value := (cast(^SDK_Vector3)address)^
		vm.PushVector3(L, value.x, value.y, value.z)
	case .Color3:
		value := (cast(^SDK_Color3)address)^
		datatypes.Push_Color3(
			L,
			datatype_registry,
			datatypes.Color3{R = f32(value.r), G = f32(value.g), B = f32(value.b)},
		)
	case .CFrame:
		value := (cast(^SDK_CFrame)address)^
		datatypes.Push_CFrame(L, datatype_registry, sdk_cframe_to_engine(value))
	case:
		return false
	}
	return true
}

native_field_set :: proc(
	L: ^vm.State,
	datatype_registry: ^datatypes.Registry,
	kind: Property_Kind,
	address: uintptr,
	index: int,
) -> bool {
	context = odin_runtime.default_context()
	#partial switch kind {
	case .Boolean:
		if !vm.IsBoolean(L, index) {return false}
		(cast(^bool)address)^ = vm.ArgBoolean(L, index)
	case .Number:
		if vm.TypeOf(L, index) != .Number && vm.TypeOf(L, index) != .Integer {return false}
		(cast(^f64)address)^ = vm.ArgNumber(L, index)
	case .Integer:
		if vm.TypeOf(L, index) != .Integer {return false}
		(cast(^i64)address)^ = vm.ArgInteger(L, index)
	case .String:
		if vm.TypeOf(L, index) != .String {return false}
		native_field_destroy(.String, address)
		copied := strings.clone_to_cstring(vm.ArgString(L, index))
		if native_allocated_strings == nil {
			native_allocated_strings = make(map[uintptr]cstring)
		}
		native_allocated_strings[address] = copied
		(cast(^cstring)address)^ = copied
	case .Vector3:
		if vm.TypeOf(L, index) != .Vector {return false}
		x, y, z := vm.ArgVector3(L, index)
		(cast(^SDK_Vector3)address)^ = SDK_Vector3{x, y, z}
	case .Color3:
		if !vm.IsUserdataType(L, index, &datatype_registry.color3) {return false}
		value := datatypes.Arg_Color3(L, index, datatype_registry)
		(cast(^SDK_Color3)address)^ = SDK_Color3{f64(value.R), f64(value.G), f64(value.B)}
	case .CFrame:
		if !vm.IsUserdataType(L, index, &datatype_registry.c_frame) {return false}
		value := datatypes.Arg_CFrame(L, index, datatype_registry)
		(cast(^SDK_CFrame)address)^ = sdk_cframe_from_engine(value)
	case:
		return false
	}
	return true
}

native_field_destroy :: proc(kind: Property_Kind, address: uintptr) {
	if kind != .String || native_allocated_strings == nil {return}
	if value, present := native_allocated_strings[address]; present {
		delete(value)
		delete_key(&native_allocated_strings, address)
		(cast(^cstring)address)^ = nil
	}
}
