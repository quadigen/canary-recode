package datatypes

import "base:runtime"
import "core:fmt"
import engine_enums "../enum"
import vm "../vm"

push_tween_info :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
	value: TweenInfo,
) {
	push_value(L, binding, value)
}

Push_TweenInfo :: proc(
	L: ^vm.State,
	registry: ^Registry,
	value: TweenInfo,
) {
	push_tween_info(L, &registry.tween_info, value)
}

Arg_TweenInfo :: proc(
	L: ^vm.State,
	index: int,
	registry: ^Registry,
) -> TweenInfo {
	return require_tween_info(L, index, &registry.tween_info)^
}

require_tween_info :: proc(
	L: ^vm.State,
	index: int,
	binding: ^vm.Userdata_Binding,
) -> ^TweenInfo {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected TweenInfo")
		return nil
	}
	return cast(^TweenInfo)vm.UserdataValue(L, index)
}

tween_info_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	binding := binding_from_upvalue(L)
	registry := registry_from_binding(binding)
	if registry == nil || registry.enums == nil {
		return vm.RaiseError(L, "TweenInfo enum registry is unavailable")
	}

	time := f32(vm.ArgOptionalNumber(L, 1, 1))

	easing_style := engine_enums.EasingStyle.Quad
	if !vm.IsNoneOrNil(L, 2) {
		item := engine_enums.Arg_Item(
			L,
			2,
			registry.enums,
			"EasingStyle",
		)
		easing_style = engine_enums.EasingStyle(item.value)
	}

	easing_direction := engine_enums.EasingDirection.Out
	if !vm.IsNoneOrNil(L, 3) {
		item := engine_enums.Arg_Item(
			L,
			3,
			registry.enums,
			"EasingDirection",
		)
		easing_direction = engine_enums.EasingDirection(item.value)
	}

	repeat_count := i32(vm.ArgOptionalNumber(L, 4, 0))
	reverses := vm.ArgOptionalBoolean(L, 5, false)
	delay_time := f32(vm.ArgOptionalNumber(L, 6, 0))

	result, ok := TweenInfo_New(
		time,
		easing_style,
		easing_direction,
		repeat_count,
		reverses,
		delay_time,
	)

	if !ok {
		return vm.RaiseError(
			L,
			"invalid TweenInfo values: time/delay must be >= 0 and repeat count must be >= -1",
		)
	}

	push_tween_info(L, binding, result)
	return 1
}

tween_info_get :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	key: string,
) -> bool {
	info := cast(^TweenInfo)value
	binding := cast(^vm.Userdata_Binding)ctx
	registry := registry_from_binding(binding)

	switch key {
	case "Time":
		vm.PushNumber(L, f64(info.Time))

	case "EasingStyle":
		if registry == nil || registry.enums == nil {
			return false
		}
		_ = engine_enums.Push_Item_By_Value(
			L,
			registry.enums,
			"EasingStyle",
			i64(info.EasingStyle),
		)

	case "EasingDirection":
		if registry == nil || registry.enums == nil {
			return false
		}
		_ = engine_enums.Push_Item_By_Value(
			L,
			registry.enums,
			"EasingDirection",
			i64(info.EasingDirection),
		)

	case "RepeatCount":
		vm.PushNumber(L, f64(info.RepeatCount))

	case "Reverses":
		vm.PushBoolean(L, info.Reverses)

	case "DelayTime":
		vm.PushNumber(L, f64(info.DelayTime))

	case:
		return false
	}

	return true
}

tween_info_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^TweenInfo)value)^ == (cast(^TweenInfo)other)^
}

tween_info_string :: proc(value, ctx: rawptr) -> string {
	info := cast(^TweenInfo)value
	return fmt.tprintf(
		"Time=%g, RepeatCount=%d, Reverses=%v, DelayTime=%g",
		info.Time,
		info.RepeatCount,
		info.Reverses,
		info.DelayTime,
	)
}

tween_info_destroy :: proc(value, ctx: rawptr) {
	free(cast(^TweenInfo)value)
}

TweenInfo_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name    = "TweenInfo",
		get     = tween_info_get,
		string  = tween_info_string,
		destroy = tween_info_destroy,
		equal   = tween_info_equal,
	}
}

TweenInfo_Install_Fields :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
) {
	add_library_function(L, binding, "new", tween_info_new)

	push_tween_info(L, binding, TweenInfo_Default)
	vm.SetField(L, -2, "default")
}
