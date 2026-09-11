package datatypes

import "base:runtime"
import "core:fmt"

import engine_enums "../enum"
import vm "../vm"
import luauh "../vm/luauh"

push_vector3_native :: proc(L: ^vm.State, value: Vector3) {
	vm.PushVector3(L, value.x, value.y, value.z)
}

Push_Vector3 :: proc(L: ^vm.State, value: Vector3) {
	push_vector3_native(L, value)
}

Arg_Vector3 :: proc(L: ^vm.State, index: int) -> Vector3 {
	x, y, z := vm.ArgVector3(L, index)
	return Vector3{x, y, z}
}

vector3_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	push_vector3_native(L, Vector3{
		f32(vm.ArgOptionalNumber(L, 1)),
		f32(vm.ArgOptionalNumber(L, 2)),
		f32(vm.ArgOptionalNumber(L, 3)),
	})
	return 1
}

vector3_from_axis :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	binding := binding_from_upvalue(L)
	registry := registry_from_binding(binding)
	if registry == nil || registry.enums == nil {
		return vm.RaiseError(L, "Vector3.FromAxis requires the enum registry")
	}

	item := engine_enums.Arg_Item(L, 1, registry.enums, "Axis")
	if item == nil {
		return 0
	}

	value, ok := Vec3_From_Axis_Name(item.name)
	if !ok {
		return vm.RaiseError(L, "invalid Enum.Axis value")
	}

	push_vector3_native(L, value)
	return 1
}

vector3_from_normal_id :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	binding := binding_from_upvalue(L)
	registry := registry_from_binding(binding)
	if registry == nil || registry.enums == nil {
		return vm.RaiseError(L, "Vector3.FromNormalId requires the enum registry")
	}

	item := engine_enums.Arg_Item(L, 1, registry.enums, "NormalId")
	if item == nil {
		return 0
	}

	value, ok := Vec3_From_Normal_Id_Name(item.name)
	if !ok {
		return vm.RaiseError(L, "invalid Enum.NormalId value")
	}

	push_vector3_native(L, value)
	return 1
}

vector3_abs :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_vector3_native(L, Vec3_Abs(Arg_Vector3(L, 1)))
	return 1
}

vector3_ceil :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_vector3_native(L, Vec3_Ceil(Arg_Vector3(L, 1)))
	return 1
}

vector3_floor :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_vector3_native(L, Vec3_Floor(Arg_Vector3(L, 1)))
	return 1
}

vector3_sign :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_vector3_native(L, Vec3_Sign(Arg_Vector3(L, 1)))
	return 1
}

vector3_cross :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_vector3_native(L, Vec3_Cross(
		Arg_Vector3(L, 1),
		Arg_Vector3(L, 2),
	))
	return 1
}

vector3_angle :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	self := Arg_Vector3(L, 1)
	other := Arg_Vector3(L, 2)

	if vm.IsNoneOrNil(L, 3) {
		vm.PushNumber(L, f64(Vec3_Angle(self, other)))
		return 1
	}

	axis := Arg_Vector3(L, 3)
	vm.PushNumber(L, f64(Vec3_Angle(self, other, &axis)))
	return 1
}

vector3_dot :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	vm.PushNumber(L, f64(Vec3_Dot(
		Arg_Vector3(L, 1),
		Arg_Vector3(L, 2),
	)))
	return 1
}

vector3_fuzzy_eq :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	vm.PushBoolean(L, Vec3_FuzzyEq(
		Arg_Vector3(L, 1),
		Arg_Vector3(L, 2),
		f32(vm.ArgOptionalNumber(L, 3, 1.0e-5)),
	))
	return 1
}

vector3_lerp :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	push_vector3_native(L, Vec3_Lerp(
		Arg_Vector3(L, 1),
		Arg_Vector3(L, 2),
		f32(vm.ArgNumber(L, 3)),
	))
	return 1
}

vector3_max :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_vector3_native(L, Vec3_Max(
		Arg_Vector3(L, 1),
		Arg_Vector3(L, 2),
	))
	return 1
}

vector3_min :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_vector3_native(L, Vec3_Min(
		Arg_Vector3(L, 1),
		Arg_Vector3(L, 2),
	))
	return 1
}

push_vector3_method :: proc(L: ^vm.State, name: string, function: vm.CFunction) {
	vm.PushFunction(L, name, function)
}

vector3_index :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	value := Arg_Vector3(L, 1)
	key := vm.ArgString(L, 2)

	switch key {
	case "x", "X":
		vm.PushNumber(L, f64(value.x))
	case "y", "Y":
		vm.PushNumber(L, f64(value.y))
	case "z", "Z":
		vm.PushNumber(L, f64(value.z))

	case "Magnitude":
		vm.PushNumber(L, f64(Vec3_Magnitude(value)))
	case "Unit":
		push_vector3_native(L, Vec3_Unit(value))

	case "Abs":
		push_vector3_method(L, "Vector3.Abs", vector3_abs)
	case "Ceil":
		push_vector3_method(L, "Vector3.Ceil", vector3_ceil)
	case "Floor":
		push_vector3_method(L, "Vector3.Floor", vector3_floor)
	case "Sign":
		push_vector3_method(L, "Vector3.Sign", vector3_sign)
	case "Cross":
		push_vector3_method(L, "Vector3.Cross", vector3_cross)
	case "Angle":
		push_vector3_method(L, "Vector3.Angle", vector3_angle)
	case "Dot":
		push_vector3_method(L, "Vector3.Dot", vector3_dot)
	case "FuzzyEq":
		push_vector3_method(L, "Vector3.FuzzyEq", vector3_fuzzy_eq)
	case "Lerp":
		push_vector3_method(L, "Vector3.Lerp", vector3_lerp)
	case "Max":
		push_vector3_method(L, "Vector3.Max", vector3_max)
	case "Min":
		push_vector3_method(L, "Vector3.Min", vector3_min)

	case:
		return vm.RaiseError(
			L,
			fmt.tprintf("attempt to index Vector3 with '%s'", key),
		)
	}

	return 1
}

install_vector3_metatable :: proc(L: ^vm.State) {
	vm.PushVector3(L, 0, 0, 0)

	if luauh.lua_getmetatable(L, -1) == 0 {
		vm.Pop(L)
		return
	}

	vm.SetReadOnly(L, -1, false)

	vm.PushFunction(L, "Vector3.__index", vector3_index)
	vm.SetField(L, -2, "__index")

	vm.SetReadOnly(L, -1, true)
	vm.Pop(L, 2)
}

Vector3_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name = "Vector3",
	}
}

Vector3_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	install_vector3_metatable(L)

	add_library_function(L, binding, "new", vector3_new)
	add_library_function(L, binding, "FromNormalId", vector3_from_normal_id)
	add_library_function(L, binding, "FromAxis", vector3_from_axis)

	push_vector3_native(L, Vector3_Zero)
	vm.SetField(L, -2, "zero")

	push_vector3_native(L, Vector3_One)
	vm.SetField(L, -2, "one")

	push_vector3_native(L, Vector3_XAxis)
	vm.SetField(L, -2, "xAxis")

	push_vector3_native(L, Vector3_YAxis)
	vm.SetField(L, -2, "yAxis")

	push_vector3_native(L, Vector3_ZAxis)
	vm.SetField(L, -2, "zAxis")
}
