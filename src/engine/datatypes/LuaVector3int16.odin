package datatypes

import "base:runtime"
import "core:fmt"
import vm "../vm"

push_vector3int16 :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
	value: Vector3int16,
) {
	push_value(L, binding, value)
}

Push_Vector3int16 :: proc(
	L: ^vm.State,
	registry: ^Registry,
	value: Vector3int16,
) {
	push_vector3int16(L, &registry.vector3int16, value)
}

Arg_Vector3int16 :: proc(
	L: ^vm.State,
	index: int,
	registry: ^Registry,
) -> Vector3int16 {
	return require_vector3int16(L, index, &registry.vector3int16)^
}

require_vector3int16 :: proc(
	L: ^vm.State,
	index: int,
	binding: ^vm.Userdata_Binding,
) -> ^Vector3int16 {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected Vector3int16")
		return nil
	}

	return cast(^Vector3int16)vm.UserdataValue(L, index)
}

vector3int16_component :: proc(L: ^vm.State, index: int) -> i16 {
	value := vm.ArgOptionalNumber(L, index, 0)

	if value < -32768 || value > 32767 {
		_ = vm.RaiseError(L, "Vector3int16 component is outside the int16 range")
		return 0
	}

	return i16(value)
}

vector3int16_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	push_vector3int16(
		L,
		binding_from_upvalue(L),
		Vector3int16_New(
			vector3int16_component(L, 1),
			vector3int16_component(L, 2),
			vector3int16_component(L, 3),
		),
	)

	return 1
}

vector3int16_get :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	key: string,
) -> bool {
	vector := cast(^Vector3int16)value

	switch key {
	case "X":
		vm.PushNumber(L, f64(vector.X))
	case "Y":
		vm.PushNumber(L, f64(vector.Y))
	case "Z":
		vm.PushNumber(L, f64(vector.Z))
	case:
		return false
	}

	return true
}

vector3int16_add :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	self_index, other_index: int,
) -> bool {
	binding := cast(^vm.Userdata_Binding)ctx
	other := require_vector3int16(L, other_index, binding)

	push_vector3int16(
		L,
		binding,
		Vector3int16_Add((cast(^Vector3int16)value)^, other^),
	)

	return true
}

vector3int16_subtract :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	self_index, other_index: int,
) -> bool {
	binding := cast(^vm.Userdata_Binding)ctx
	self := (cast(^Vector3int16)value)^
	other := require_vector3int16(L, other_index, binding)^

	if self_index == 1 {
		push_vector3int16(L, binding, Vector3int16_Subtract(self, other))
	} else {
		push_vector3int16(L, binding, Vector3int16_Subtract(other, self))
	}

	return true
}

vector3int16_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^Vector3int16)value)^ == (cast(^Vector3int16)other)^
}

vector3int16_string :: proc(value, ctx: rawptr) -> string {
	vector := cast(^Vector3int16)value
	return fmt.tprintf("%d, %d, %d", vector.X, vector.Y, vector.Z)
}

vector3int16_destroy :: proc(value, ctx: rawptr) {
	free(cast(^Vector3int16)value)
}

Vector3int16_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name     = "Vector3int16",
		get      = vector3int16_get,
		string   = vector3int16_string,
		destroy  = vector3int16_destroy,
		add      = vector3int16_add,
		subtract = vector3int16_subtract,
		equal    = vector3int16_equal,
	}
}

Vector3int16_Install_Fields :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
) {
	add_library_function(L, binding, "new", vector3int16_new)

	push_vector3int16(L, binding, Vector3int16_Zero)
	vm.SetField(L, -2, "zero")
}
