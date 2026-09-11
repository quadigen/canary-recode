package datatypes

import "base:runtime"
import "core:fmt"
import vm "../vm"

push_quaternion :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
	value: Quaternion,
) {
	push_value(L, binding, value)
}

Push_Quaternion :: proc(
	L: ^vm.State,
	registry: ^Registry,
	value: Quaternion,
) {
	push_quaternion(L, &registry.quaternion, value)
}

Arg_Quaternion :: proc(
	L: ^vm.State,
	index: int,
	registry: ^Registry,
) -> Quaternion {
	return require_quaternion(L, index, &registry.quaternion)^
}

require_quaternion :: proc(
	L: ^vm.State,
	index: int,
	binding: ^vm.Userdata_Binding,
) -> ^Quaternion {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected Quaternion")
		return nil
	}

	return cast(^Quaternion)vm.UserdataValue(L, index)
}

quaternion_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	push_quaternion(
		L,
		binding_from_upvalue(L),
		Quaternion_New(
			f32(vm.ArgOptionalNumber(L, 1, 0)),
			f32(vm.ArgOptionalNumber(L, 2, 0)),
			f32(vm.ArgOptionalNumber(L, 3, 0)),
			f32(vm.ArgOptionalNumber(L, 4, 1)),
		),
	)

	return 1
}

quaternion_from_axis_angle :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	x, y, z := vm.ArgVector3(L, 1)
	angle := f32(vm.ArgNumber(L, 2))

	push_quaternion(
		L,
		binding_from_upvalue(L),
		Quaternion_FromAxisAngle(Vector3{x, y, z}, angle),
	)

	return 1
}

quaternion_get :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	key: string,
) -> bool {
	q := cast(^Quaternion)value
	binding := cast(^vm.Userdata_Binding)ctx

	switch key {
	case "X":
		vm.PushNumber(L, f64(q.X))
	case "Y":
		vm.PushNumber(L, f64(q.Y))
	case "Z":
		vm.PushNumber(L, f64(q.Z))
	case "W":
		vm.PushNumber(L, f64(q.W))
	case "Magnitude":
		vm.PushNumber(L, f64(Quaternion_Magnitude(q^)))
	case "Unit":
		push_quaternion(L, binding, Quaternion_Unit(q^))
	case "Conjugate", "Inverse", "Dot", "Lerp", "Slerp", "ToAxisAngle":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}

	return true
}

quaternion_namecall :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	method: string,
) -> (i32, bool) {
	q := cast(^Quaternion)value
	binding := cast(^vm.Userdata_Binding)ctx

	switch method {
	case "Conjugate":
		push_quaternion(L, binding, Quaternion_Conjugate(q^))
		return 1, true

	case "Inverse":
		push_quaternion(L, binding, Quaternion_Inverse(q^))
		return 1, true

	case "Dot":
		other := require_quaternion(L, 2, binding)
		vm.PushNumber(L, f64(Quaternion_Dot(q^, other^)))
		return 1, true

	case "Lerp":
		other := require_quaternion(L, 2, binding)
		alpha := f32(vm.ArgNumber(L, 3))
		push_quaternion(L, binding, Quaternion_Lerp(q^, other^, alpha))
		return 1, true

	case "Slerp":
		other := require_quaternion(L, 2, binding)
		alpha := f32(vm.ArgNumber(L, 3))
		push_quaternion(L, binding, Quaternion_Slerp(q^, other^, alpha))
		return 1, true

	case "ToAxisAngle":
		axis, angle := Quaternion_ToAxisAngle(q^)
		vm.PushVector3(L, axis.x, axis.y, axis.z)
		vm.PushNumber(L, f64(angle))
		return 2, true
	}

	return 0, false
}

quaternion_multiply :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	self_index, other_index: int,
) -> bool {
	binding := cast(^vm.Userdata_Binding)ctx
	self := (cast(^Quaternion)value)^
	other := require_quaternion(L, other_index, binding)^

	if self_index == 1 {
		push_quaternion(L, binding, Quaternion_Multiply(self, other))
	} else {
		push_quaternion(L, binding, Quaternion_Multiply(other, self))
	}

	return true
}

quaternion_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^Quaternion)value)^ == (cast(^Quaternion)other)^
}

quaternion_string :: proc(value, ctx: rawptr) -> string {
	q := cast(^Quaternion)value
	return fmt.tprintf("%g, %g, %g, %g", q.X, q.Y, q.Z, q.W)
}

quaternion_destroy :: proc(value, ctx: rawptr) {
	free(cast(^Quaternion)value)
}

Quaternion_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name     = "Quaternion",
		get      = quaternion_get,
		namecall = quaternion_namecall,
		string   = quaternion_string,
		destroy  = quaternion_destroy,
		multiply = quaternion_multiply,
		equal    = quaternion_equal,
	}
}

Quaternion_Install_Fields :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
) {
	add_library_function(L, binding, "new", quaternion_new)
	add_library_function(L, binding, "fromAxisAngle", quaternion_from_axis_angle)

	push_quaternion(L, binding, Quaternion_Identity)
	vm.SetField(L, -2, "identity")
}
