package datatypes

import "base:runtime"
import "core:fmt"
import vm "../vm"

push_color_sequence_keypoint :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding, value: ColorSequenceKeypoint) {
	push_value(L, binding, value)
}

Push_ColorSequenceKeypoint :: proc(L: ^vm.State, registry: ^Registry, value: ColorSequenceKeypoint) {
	push_color_sequence_keypoint(L, &registry.color_sequence_keypoint, value)
}

Arg_ColorSequenceKeypoint :: proc(L: ^vm.State, index: int, registry: ^Registry) -> ColorSequenceKeypoint {
	return require_color_sequence_keypoint(L, index, &registry.color_sequence_keypoint)^
}

require_color_sequence_keypoint :: proc(L: ^vm.State, index: int, binding: ^vm.Userdata_Binding) -> ^ColorSequenceKeypoint {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected ColorSequenceKeypoint")
		return nil
	}
	return cast(^ColorSequenceKeypoint)vm.UserdataValue(L, index)
}

color_sequence_keypoint_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	binding := binding_from_upvalue(L)
	registry := registry_from_binding(binding)
	if registry == nil {
		return vm.RaiseError(L, "ColorSequenceKeypoint registry is unavailable")
	}
	time := f32(vm.ArgNumber(L, 1))
	if time != time || time < 0 || time > 1 {
		return vm.RaiseError(L, "ColorSequenceKeypoint time must be between 0 and 1")
	}
	color := require_color3(L, 2, &registry.color3)
	push_color_sequence_keypoint(L, binding, ColorSequenceKeypoint_New(
		time,
		color^,
	))
	return 1
}

color_sequence_keypoint_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	keypoint := cast(^ColorSequenceKeypoint)value
	binding := cast(^vm.Userdata_Binding)ctx
	registry := registry_from_binding(binding)
	switch key {
	case "Time":
		vm.PushNumber(L, f64(keypoint.Time))
	case "Value":
		if registry == nil { return false }
		push_color3(L, &registry.color3, keypoint.Value)
	case:
		return false
	}
	return true
}

color_sequence_keypoint_equal :: proc(value, other, ctx: rawptr) -> bool {
	a, b := cast(^ColorSequenceKeypoint)value, cast(^ColorSequenceKeypoint)other
	return ColorSequenceKeypoint_Equal(a^, b^)
}

color_sequence_keypoint_string :: proc(value, ctx: rawptr) -> string {
	keypoint := cast(^ColorSequenceKeypoint)value
	return fmt.tprintf("%g, %g, %g, %g", keypoint.Time, keypoint.Value.R, keypoint.Value.G, keypoint.Value.B)
}

color_sequence_keypoint_destroy :: proc(value, ctx: rawptr) {
	free(cast(^ColorSequenceKeypoint)value)
}

ColorSequenceKeypoint_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name    = "ColorSequenceKeypoint",
		get     = color_sequence_keypoint_get,
		string  = color_sequence_keypoint_string,
		destroy = color_sequence_keypoint_destroy,
		equal   = color_sequence_keypoint_equal,
	}
}

ColorSequenceKeypoint_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "new", color_sequence_keypoint_new)
}

push_color_sequence :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding, value: ColorSequence) {
	push_value(L, binding, value)
}

Push_ColorSequence :: proc(L: ^vm.State, registry: ^Registry, value: ColorSequence) {
	push_color_sequence(L, &registry.color_sequence, ColorSequence_Clone(value))
}

Arg_ColorSequence :: proc(L: ^vm.State, index: int, registry: ^Registry) -> ColorSequence {
	return require_color_sequence(L, index, &registry.color_sequence)^
}

require_color_sequence :: proc(L: ^vm.State, index: int, binding: ^vm.Userdata_Binding) -> ^ColorSequence {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected ColorSequence")
		return nil
	}
	return cast(^ColorSequence)vm.UserdataValue(L, index)
}

color_sequence_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	binding := binding_from_upvalue(L)
	registry := registry_from_binding(binding)
	if registry == nil {
		return vm.RaiseError(L, "ColorSequence registry is unavailable")
	}

	if vm.IsTable(L, 1) {
		count := vm.RawLen(L, 1)
		keypoints := make([]ColorSequenceKeypoint, count)
		for i in 0 ..< count {
			_ = vm.RawGetIndex(L, 1, i + 1)
			keypoints[i] = require_color_sequence_keypoint(L, -1, &registry.color_sequence_keypoint)^
			vm.Pop(L, 1)
		}

		sequence, ok := ColorSequence_FromKeypoints(keypoints)
		delete(keypoints)
		if !ok {
			return vm.RaiseError(L, "invalid ColorSequence keypoints")
		}
		push_color_sequence(L, binding, sequence)
		return 1
	}

	color0 := require_color3(L, 1, &registry.color3)
	if vm.IsNoneOrNil(L, 2) {
		push_color_sequence(L, binding, ColorSequence_New(color0^))
	} else {
		color1 := require_color3(L, 2, &registry.color3)
		push_color_sequence(L, binding, ColorSequence_New2(color0^, color1^))
	}
	return 1
}

color_sequence_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	sequence := cast(^ColorSequence)value
	binding := cast(^vm.Userdata_Binding)ctx
	registry := registry_from_binding(binding)
	switch key {
	case "Keypoints":
		if registry == nil { return false }
		vm.NewTable(L, len(sequence.Keypoints), 0)
		for keypoint, i in sequence.Keypoints {
			push_color_sequence_keypoint(L, &registry.color_sequence_keypoint, keypoint)
			vm.RawSetIndex(L, -2, i + 1)
		}
		vm.SetReadOnly(L, -1)
	case:
		return false
	}
	return true
}

color_sequence_equal :: proc(value, other, ctx: rawptr) -> bool {
	a, b := cast(^ColorSequence)value, cast(^ColorSequence)other
	return ColorSequence_Equal(a^, b^)
}

color_sequence_string :: proc(value, ctx: rawptr) -> string {
	sequence := cast(^ColorSequence)value
	result := ""
	for keypoint, i in sequence.Keypoints {
		entry := fmt.tprintf("%g: %g, %g, %g", keypoint.Time, keypoint.Value.R, keypoint.Value.G, keypoint.Value.B)
		if i == 0 {
			result = entry
		} else {
			result = fmt.tprintf("%s; %s", result, entry)
		}
	}
	return result
}

color_sequence_destroy :: proc(value, ctx: rawptr) {
	sequence := cast(^ColorSequence)value
	ColorSequence_Destroy(sequence^)
	free(sequence)
}

ColorSequence_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name    = "ColorSequence",
		get     = color_sequence_get,
		string  = color_sequence_string,
		destroy = color_sequence_destroy,
		equal   = color_sequence_equal,
	}
}

ColorSequence_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "new", color_sequence_new)
}
