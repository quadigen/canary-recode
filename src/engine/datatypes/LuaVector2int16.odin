package datatypes

import "base:runtime"
import "core:fmt"
import vm "../vm"

push_vector2int16 :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
	value: Vector2int16,
) {
	push_value(L, binding, value)
}

Push_Vector2int16 :: proc(
	L: ^vm.State,
	registry: ^Registry,
	value: Vector2int16,
) {
	push_vector2int16(L, &registry.vector2int16, value)
}

Arg_Vector2int16 :: proc(
	L: ^vm.State,
	index: int,
	registry: ^Registry,
) -> Vector2int16 {
	return require_vector2int16(L, index, &registry.vector2int16)^
}

require_vector2int16 :: proc(
	L: ^vm.State,
	index: int,
	binding: ^vm.Userdata_Binding,
) -> ^Vector2int16 {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected Vector2int16")
		return nil
	}

	return cast(^Vector2int16)vm.UserdataValue(L, index)
}

vector2int16_component :: proc(L: ^vm.State, index: int) -> i16 {
	value := vm.ArgOptionalNumber(L, index, 0)

	if value < -32768 || value > 32767 {
		_ = vm.RaiseError(L, "Vector2int16 component is outside the int16 range")
		return 0
	}

	return i16(value)
}

vector2int16_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	push_vector2int16(
		L,
		binding_from_upvalue(L),
		Vector2int16_New(
			vector2int16_component(L, 1),
			vector2int16_component(L, 2),
		),
	)

	return 1
}

vector2int16_get :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	key: string,
) -> bool {
	vector := cast(^Vector2int16)value

	switch key {
	case "X":
		vm.PushNumber(L, f64(vector.X))
	case "Y":
		vm.PushNumber(L, f64(vector.Y))
	case:
		return false
	}

	return true
}

vector2int16_add :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	self_index, other_index: int,
) -> bool {
	binding := cast(^vm.Userdata_Binding)ctx
	other := require_vector2int16(L, other_index, binding)

	push_vector2int16(
		L,
		binding,
		Vector2int16_Add((cast(^Vector2int16)value)^, other^),
	)

	return true
}

vector2int16_subtract :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	self_index, other_index: int,
) -> bool {
	binding := cast(^vm.Userdata_Binding)ctx
	self := (cast(^Vector2int16)value)^
	other := require_vector2int16(L, other_index, binding)^

	if self_index == 1 {
		push_vector2int16(L, binding, Vector2int16_Subtract(self, other))
	} else {
		push_vector2int16(L, binding, Vector2int16_Subtract(other, self))
	}

	return true
}

vector2int16_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^Vector2int16)value)^ == (cast(^Vector2int16)other)^
}

vector2int16_string :: proc(value, ctx: rawptr) -> string {
	vector := cast(^Vector2int16)value
	return fmt.tprintf("%d, %d", vector.X, vector.Y)
}

vector2int16_destroy :: proc(value, ctx: rawptr) {
	free(cast(^Vector2int16)value)
}

Vector2int16_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name     = "Vector2int16",
		get      = vector2int16_get,
		string   = vector2int16_string,
		destroy  = vector2int16_destroy,
		add      = vector2int16_add,
		subtract = vector2int16_subtract,
		equal    = vector2int16_equal,
	}
}

Vector2int16_Install_Fields :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
) {
	add_library_function(L, binding, "new", vector2int16_new)

	push_vector2int16(L, binding, Vector2int16_Zero)
	vm.SetField(L, -2, "zero")
}
