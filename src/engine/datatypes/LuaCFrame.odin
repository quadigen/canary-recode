package datatypes

import "base:runtime"
import "core:fmt"
import vm "../vm"

push_cframe :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding, value: CFrame) {
	push_value(L, binding, value)
}

Push_CFrame :: proc(L: ^vm.State, registry: ^Registry, value: CFrame) {
	push_cframe(L, &registry.c_frame, value)
}

Arg_CFrame :: proc(L: ^vm.State, index: int, registry: ^Registry) -> CFrame {
	return require_cframe(L, index, &registry.c_frame)^
}

require_cframe :: proc(L: ^vm.State, index: int, binding: ^vm.Userdata_Binding) -> ^CFrame {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected CFrame")
		return nil
	}
	return cast(^CFrame)vm.UserdataValue(L, index)
}

arg_vector3 :: proc(L: ^vm.State, index: int) -> Vector3 {
	x, y, z := vm.ArgVector3(L, index)
	return Vector3{x, y, z}
}

push_vector3 :: proc(L: ^vm.State, value: Vector3) {
	vm.PushVector3(L, value.x, value.y, value.z)
}

cframe_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	binding := binding_from_upvalue(L)
	argument_count := vm.StackTop(L)

	switch argument_count {
	case 0:
		push_cframe(L, binding, CFrame_New_Empty())
	case 1:
		if vm.TypeOf(L, 1) != .Vector {
			return vm.RaiseError(L, "CFrame.new expected a vector")
		}
		push_cframe(L, binding, CFrame_New_Position(arg_vector3(L, 1)))
	case 2:
		push_cframe(L, binding, CFrame_New_LookAt(arg_vector3(L, 1), arg_vector3(L, 2)))
	case 3:
		push_cframe(L, binding, CFrame_New_XYZ(
			f32(vm.ArgNumber(L, 1)),
			f32(vm.ArgNumber(L, 2)),
			f32(vm.ArgNumber(L, 3)),
		))
	case 7:
		push_cframe(L, binding, CFrame_New_Quaternion(
			f32(vm.ArgNumber(L, 1)), f32(vm.ArgNumber(L, 2)), f32(vm.ArgNumber(L, 3)),
			f32(vm.ArgNumber(L, 4)), f32(vm.ArgNumber(L, 5)), f32(vm.ArgNumber(L, 6)), f32(vm.ArgNumber(L, 7)),
		))
	case 12:
		push_cframe(L, binding, CFrame_New_Matrix(
			f32(vm.ArgNumber(L, 1)), f32(vm.ArgNumber(L, 2)), f32(vm.ArgNumber(L, 3)),
			f32(vm.ArgNumber(L, 4)), f32(vm.ArgNumber(L, 5)), f32(vm.ArgNumber(L, 6)),
			f32(vm.ArgNumber(L, 7)), f32(vm.ArgNumber(L, 8)), f32(vm.ArgNumber(L, 9)),
			f32(vm.ArgNumber(L, 10)), f32(vm.ArgNumber(L, 11)), f32(vm.ArgNumber(L, 12)),
		))
	case:
		return vm.RaiseError(L, "invalid CFrame.new arguments")
	}
	return 1
}

cframe_angles :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_cframe(L, binding_from_upvalue(L), CFrame_Angles(
		f32(vm.ArgNumber(L, 1)), f32(vm.ArgNumber(L, 2)), f32(vm.ArgNumber(L, 3)),
	))
	return 1
}

cframe_from_euler_xyz :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_cframe(L, binding_from_upvalue(L), CFrame_FromEulerAnglesXYZ(
		f32(vm.ArgNumber(L, 1)), f32(vm.ArgNumber(L, 2)), f32(vm.ArgNumber(L, 3)),
	))
	return 1
}

cframe_from_euler_yxz :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_cframe(L, binding_from_upvalue(L), CFrame_FromEulerAnglesYXZ(
		f32(vm.ArgNumber(L, 1)), f32(vm.ArgNumber(L, 2)), f32(vm.ArgNumber(L, 3)),
	))
	return 1
}

cframe_from_orientation :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_cframe(L, binding_from_upvalue(L), CFrame_FromOrientation(
		f32(vm.ArgNumber(L, 1)), f32(vm.ArgNumber(L, 2)), f32(vm.ArgNumber(L, 3)),
	))
	return 1
}

cframe_from_axis_angle :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_cframe(L, binding_from_upvalue(L), CFrame_FromAxisAngle(arg_vector3(L, 1), f32(vm.ArgNumber(L, 2))))
	return 1
}

cframe_look_at :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	value := CFrame_LookAt_Default(arg_vector3(L, 1), arg_vector3(L, 2))
	if !vm.IsNoneOrNil(L, 3) {
		value = CFrame_LookAt_Up(arg_vector3(L, 1), arg_vector3(L, 2), arg_vector3(L, 3))
	}
	push_cframe(L, binding_from_upvalue(L), value)
	return 1
}

cframe_look_along :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	value := CFrame_LookAlong_Default(arg_vector3(L, 1), arg_vector3(L, 2))
	if !vm.IsNoneOrNil(L, 3) {
		value = CFrame_LookAlong_Up(arg_vector3(L, 1), arg_vector3(L, 2), arg_vector3(L, 3))
	}
	push_cframe(L, binding_from_upvalue(L), value)
	return 1
}

cframe_from_matrix :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	position := arg_vector3(L, 1)
	x_vector := arg_vector3(L, 2)
	y_vector := arg_vector3(L, 3)
	z_vector := cframe_v3_cross(x_vector, y_vector)
	if !vm.IsNoneOrNil(L, 4) {
		z_vector = arg_vector3(L, 4)
	}
	push_cframe(L, binding_from_upvalue(L), CFrame_FromMatrix(position, x_vector, y_vector, z_vector))
	return 1
}

cframe_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	cf := cast(^CFrame)value
	binding := cast(^vm.Userdata_Binding)ctx
	switch key {
	case "Position", "p":
		push_vector3(L, CFrame_Position(cf^))
	case "Rotation":
		push_cframe(L, binding, CFrame_Rotation(cf^))
	case "RightVector", "XVector":
		push_vector3(L, CFrame_RightVector(cf^))
	case "UpVector", "YVector":
		push_vector3(L, CFrame_UpVector(cf^))
	case "LookVector":
		push_vector3(L, CFrame_LookVector(cf^))
	case "ZVector":
		push_vector3(L, CFrame_ZVector(cf^))
	case "X":
		vm.PushNumber(L, f64(cf.x))
	case "Y":
		vm.PushNumber(L, f64(cf.y))
	case "Z":
		vm.PushNumber(L, f64(cf.z))
	case "Inverse", "Lerp", "ToWorldSpace", "ToObjectSpace", "PointToWorldSpace", "PointToObjectSpace",
	     "VectorToWorldSpace", "VectorToObjectSpace", "Orthonormalize", "GetComponents", "components",
	     "ToEulerAnglesXYZ", "ToEulerAnglesYXZ", "ToOrientation", "ToAxisAngle", "FuzzyEq", "AngleBetween":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

push_angles :: proc(L: ^vm.State, x, y, z: f32) {
	vm.PushNumber(L, f64(x))
	vm.PushNumber(L, f64(y))
	vm.PushNumber(L, f64(z))
}

cframe_namecall :: proc(L: ^vm.State, value, ctx: rawptr, method: string) -> (i32, bool) {
	cf := cast(^CFrame)value
	binding := cast(^vm.Userdata_Binding)ctx
	switch method {
	case "Inverse":
		push_cframe(L, binding, CFrame_Inverse(cf^))
		return 1, true
	case "Lerp":
		push_cframe(L, binding, CFrame_Lerp(cf^, require_cframe(L, 2, binding)^, f32(vm.ArgNumber(L, 3))))
		return 1, true
	case "ToWorldSpace":
		push_cframe(L, binding, CFrame_ToWorldSpace(cf^, require_cframe(L, 2, binding)^))
		return 1, true
	case "ToObjectSpace":
		push_cframe(L, binding, CFrame_ToObjectSpace(cf^, require_cframe(L, 2, binding)^))
		return 1, true
	case "PointToWorldSpace":
		push_vector3(L, CFrame_PointToWorldSpace(cf^, arg_vector3(L, 2)))
		return 1, true
	case "PointToObjectSpace":
		push_vector3(L, CFrame_PointToObjectSpace(cf^, arg_vector3(L, 2)))
		return 1, true
	case "VectorToWorldSpace":
		push_vector3(L, CFrame_VectorToWorldSpace(cf^, arg_vector3(L, 2)))
		return 1, true
	case "VectorToObjectSpace":
		push_vector3(L, CFrame_VectorToObjectSpace(cf^, arg_vector3(L, 2)))
		return 1, true
	case "Orthonormalize":
		push_cframe(L, binding, CFrame_Orthonormalize(cf^))
		return 1, true
	case "GetComponents", "components":
		x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 := CFrame_GetComponents(cf^)
		vm.PushNumber(L, f64(x)); vm.PushNumber(L, f64(y)); vm.PushNumber(L, f64(z))
		vm.PushNumber(L, f64(r00)); vm.PushNumber(L, f64(r01)); vm.PushNumber(L, f64(r02))
		vm.PushNumber(L, f64(r10)); vm.PushNumber(L, f64(r11)); vm.PushNumber(L, f64(r12))
		vm.PushNumber(L, f64(r20)); vm.PushNumber(L, f64(r21)); vm.PushNumber(L, f64(r22))
		return 12, true
	case "ToEulerAnglesXYZ":
		x, y, z := CFrame_ToEulerAnglesXYZ(cf^)
		push_angles(L, x, y, z)
		return 3, true
	case "ToEulerAnglesYXZ":
		x, y, z := CFrame_ToEulerAnglesYXZ(cf^)
		push_angles(L, x, y, z)
		return 3, true
	case "ToOrientation":
		x, y, z := CFrame_ToOrientation(cf^)
		push_angles(L, x, y, z)
		return 3, true
	case "ToAxisAngle":
		axis, angle := CFrame_ToAxisAngle(cf^)
		push_vector3(L, axis)
		vm.PushNumber(L, f64(angle))
		return 2, true
	case "FuzzyEq":
		other := require_cframe(L, 2, binding)
		vm.PushBoolean(L, CFrame_FuzzyEq_Epsilon(cf^, other^, f32(vm.ArgOptionalNumber(L, 3, 1.0e-5))))
		return 1, true
	case "AngleBetween":
		vm.PushNumber(L, f64(CFrame_AngleBetween(cf^, require_cframe(L, 2, binding)^)))
		return 1, true
	}
	return 0, false
}

cframe_add :: proc(L: ^vm.State, value, ctx: rawptr, self_index, other_index: int) -> bool {
	if self_index != 1 || vm.TypeOf(L, other_index) != .Vector {
		return false
	}
	push_cframe(L, cast(^vm.Userdata_Binding)ctx, CFrame_Add_Vector3((cast(^CFrame)value)^, arg_vector3(L, other_index)))
	return true
}

cframe_subtract :: proc(L: ^vm.State, value, ctx: rawptr, self_index, other_index: int) -> bool {
	if self_index != 1 || vm.TypeOf(L, other_index) != .Vector {
		return false
	}
	push_cframe(L, cast(^vm.Userdata_Binding)ctx, CFrame_Sub_Vector3((cast(^CFrame)value)^, arg_vector3(L, other_index)))
	return true
}

cframe_multiply :: proc(L: ^vm.State, value, ctx: rawptr, self_index, other_index: int) -> bool {
	if self_index != 1 {
		return false
	}
	binding := cast(^vm.Userdata_Binding)ctx
	if vm.IsUserdataType(L, other_index, binding) {
		push_cframe(L, binding, CFrame_Mul_CFrame((cast(^CFrame)value)^, require_cframe(L, other_index, binding)^))
		return true
	}
	if vm.TypeOf(L, other_index) == .Vector {
		push_vector3(L, CFrame_Mul_Vector3((cast(^CFrame)value)^, arg_vector3(L, other_index)))
		return true
	}
	return false
}

cframe_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^CFrame)value)^ == (cast(^CFrame)other)^
}

cframe_string :: proc(value, ctx: rawptr) -> string {
	cf := cast(^CFrame)value
	return fmt.tprintf(
		"%g, %g, %g, %g, %g, %g, %g, %g, %g, %g, %g, %g",
		cf.x, cf.y, cf.z, cf.r00, cf.r01, cf.r02, cf.r10, cf.r11, cf.r12, cf.r20, cf.r21, cf.r22,
	)
}

cframe_destroy :: proc(value, ctx: rawptr) {
	free(cast(^CFrame)value)
}

CFrame_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name     = "CFrame",
		get      = cframe_get,
		namecall = cframe_namecall,
		string   = cframe_string,
		destroy  = cframe_destroy,
		add      = cframe_add,
		subtract = cframe_subtract,
		multiply = cframe_multiply,
		equal    = cframe_equal,
	}
}

CFrame_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "new", cframe_new)
	add_library_function(L, binding, "Angles", cframe_angles)
	add_library_function(L, binding, "fromEulerAnglesXYZ", cframe_from_euler_xyz)
	add_library_function(L, binding, "fromEulerAnglesYXZ", cframe_from_euler_yxz)
	add_library_function(L, binding, "fromOrientation", cframe_from_orientation)
	add_library_function(L, binding, "fromAxisAngle", cframe_from_axis_angle)
	add_library_function(L, binding, "lookAt", cframe_look_at)
	add_library_function(L, binding, "lookAlong", cframe_look_along)
	add_library_function(L, binding, "fromMatrix", cframe_from_matrix)
	push_cframe(L, binding, CFrame_Identity)
	vm.SetField(L, -2, "identity")
}
