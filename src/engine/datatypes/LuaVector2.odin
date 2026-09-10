package datatypes

import "base:runtime"
import "core:fmt"
import vm "../vm"

push_vector2 :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding, value: Vector2) {
	push_value(L, binding, value)
}

Push_Vector2 :: proc(L: ^vm.State, registry: ^Registry, value: Vector2) {
	push_vector2(L, &registry.vector2, value)
}

Arg_Vector2 :: proc(L: ^vm.State, index: int, registry: ^Registry) -> Vector2 {
	return require_vector2(L, index, &registry.vector2)^
}

require_vector2 :: proc(L: ^vm.State, index: int, binding: ^vm.Userdata_Binding) -> ^Vector2 {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected Vector2")
		return nil
	}
	return cast(^Vector2)vm.UserdataValue(L, index)
}

vector2_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_vector2(L, binding_from_upvalue(L), Vector2{
		f32(vm.ArgOptionalNumber(L, 1)),
		f32(vm.ArgOptionalNumber(L, 2)),
	})
	return 1
}

vector2_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	vector := cast(^Vector2)value
	switch key {
	case "X":
		vm.PushNumber(L, f64(vector.X))
	case "Y":
		vm.PushNumber(L, f64(vector.Y))
	case "Magnitude":
		vm.PushNumber(L, f64(Vec2_Magnitude(vector^)))
	case "Unit":
		push_vector2(L, cast(^vm.Userdata_Binding)ctx, Vec2_Unit(vector^))
	case "Cross", "Dot", "FuzzyEq", "Lerp":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

vector2_namecall :: proc(L: ^vm.State, value, ctx: rawptr, method: string) -> (i32, bool) {
	vector := cast(^Vector2)value
	binding := cast(^vm.Userdata_Binding)ctx
	switch method {
	case "Cross":
		other := require_vector2(L, 2, binding)
		vm.PushNumber(L, f64(Vec2_Cross(vector^, other^)))
		return 1, true
	case "Dot":
		other := require_vector2(L, 2, binding)
		vm.PushNumber(L, f64(Vec2_Dot(vector^, other^)))
		return 1, true
	case "FuzzyEq":
		other := require_vector2(L, 2, binding)
		vm.PushBoolean(L, Vec2_FuzzyEq(vector^, other^, f32(vm.ArgOptionalNumber(L, 3, 1.0e-5))))
		return 1, true
	case "Lerp":
		goal := require_vector2(L, 2, binding)
		push_vector2(L, binding, Vec2_Lerp(vector^, goal^, f32(vm.ArgNumber(L, 3))))
		return 1, true
	}
	return 0, false
}

vector2_add :: proc(L: ^vm.State, value, ctx: rawptr, self_index, other_index: int) -> bool {
	binding := cast(^vm.Userdata_Binding)ctx
	other := require_vector2(L, other_index, binding)
	push_vector2(L, binding, Vec2_Add((cast(^Vector2)value)^, other^))
	return true
}

vector2_subtract :: proc(L: ^vm.State, value, ctx: rawptr, self_index, other_index: int) -> bool {
	binding := cast(^vm.Userdata_Binding)ctx
	other := require_vector2(L, other_index, binding)
	left := (cast(^Vector2)value)^
	if self_index == 1 {
		push_vector2(L, binding, Vec2_Subtract(left, other^))
	} else {
		push_vector2(L, binding, Vec2_Subtract(other^, left))
	}
	return true
}

vector2_multiply :: proc(L: ^vm.State, value, ctx: rawptr, self_index, other_index: int) -> bool {
	binding := cast(^vm.Userdata_Binding)ctx
	vector := (cast(^Vector2)value)^
	if vm.IsNumber(L, other_index) {
		push_vector2(L, binding, Vec2_Multiply_Scalar(vector, f32(vm.ArgNumber(L, other_index))))
		return true
	}
	push_vector2(L, binding, Vec2_Multiply(vector, require_vector2(L, other_index, binding)^))
	return true
}

vector2_divide :: proc(L: ^vm.State, value, ctx: rawptr, self_index, other_index: int) -> bool {
	binding := cast(^vm.Userdata_Binding)ctx
	vector := (cast(^Vector2)value)^
	if vm.IsNumber(L, other_index) {
		scalar := f32(vm.ArgNumber(L, other_index))
		if self_index == 1 {
			push_vector2(L, binding, Vec2_Divide_Scalar(vector, scalar))
		} else {
			push_vector2(L, binding, Vector2{scalar/vector.X, scalar/vector.Y})
		}
		return true
	}
	other := require_vector2(L, other_index, binding)^
	if self_index == 1 {
		push_vector2(L, binding, Vec2_Divide(vector, other))
	} else {
		push_vector2(L, binding, Vec2_Divide(other, vector))
	}
	return true
}

vector2_negate :: proc(L: ^vm.State, value, ctx: rawptr) -> bool {
	push_vector2(L, cast(^vm.Userdata_Binding)ctx, Vec2_Negate((cast(^Vector2)value)^))
	return true
}

vector2_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^Vector2)value)^ == (cast(^Vector2)other)^
}

vector2_string :: proc(value, ctx: rawptr) -> string {
	vector := cast(^Vector2)value
	return fmt.tprintf("%g, %g", vector.X, vector.Y)
}

vector2_destroy :: proc(value, ctx: rawptr) {
	free(cast(^Vector2)value)
}

Vector2_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name     = "Vector2",
		get      = vector2_get,
		namecall = vector2_namecall,
		string   = vector2_string,
		destroy  = vector2_destroy,
		add      = vector2_add,
		subtract = vector2_subtract,
		multiply = vector2_multiply,
		divide   = vector2_divide,
		negate   = vector2_negate,
		equal    = vector2_equal,
	}
}

Vector2_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "new", vector2_new)
	push_vector2(L, binding, Vector2_Zero)
	vm.SetField(L, -2, "zero")
	push_vector2(L, binding, Vector2_One)
	vm.SetField(L, -2, "one")
	push_vector2(L, binding, Vector2_XAxis)
	vm.SetField(L, -2, "xAxis")
	push_vector2(L, binding, Vector2_YAxis)
	vm.SetField(L, -2, "yAxis")
}

