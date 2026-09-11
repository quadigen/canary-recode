package datatypes

import "base:runtime"
import "core:fmt"
import vm "../vm"

push_number_sequence_keypoint :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
	value: NumberSequenceKeypoint,
) {
	push_value(L, binding, value)
}

Push_NumberSequenceKeypoint :: proc(
	L: ^vm.State,
	registry: ^Registry,
	value: NumberSequenceKeypoint,
) {
	push_number_sequence_keypoint(L, &registry.number_sequence_keypoint, value)
}

Arg_NumberSequenceKeypoint :: proc(
	L: ^vm.State,
	index: int,
	registry: ^Registry,
) -> NumberSequenceKeypoint {
	return require_number_sequence_keypoint(
		L,
		index,
		&registry.number_sequence_keypoint,
	)^
}

require_number_sequence_keypoint :: proc(
	L: ^vm.State,
	index: int,
	binding: ^vm.Userdata_Binding,
) -> ^NumberSequenceKeypoint {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected NumberSequenceKeypoint")
		return nil
	}

	return cast(^NumberSequenceKeypoint)vm.UserdataValue(L, index)
}

number_sequence_keypoint_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	time := f32(vm.ArgNumber(L, 1))
	value := f32(vm.ArgNumber(L, 2))
	envelope := f32(vm.ArgOptionalNumber(L, 3, 0))

	if time != time || time < 0 || time > 1 {
		return vm.RaiseError(L, "NumberSequenceKeypoint time must be between 0 and 1")
	}

	if value != value {
		return vm.RaiseError(L, "NumberSequenceKeypoint value must be finite")
	}

	if envelope != envelope || envelope < 0 {
		return vm.RaiseError(L, "NumberSequenceKeypoint envelope must be >= 0")
	}

	push_number_sequence_keypoint(
		L,
		binding_from_upvalue(L),
		NumberSequenceKeypoint_New(time, value, envelope),
	)

	return 1
}

number_sequence_keypoint_get :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	key: string,
) -> bool {
	keypoint := cast(^NumberSequenceKeypoint)value

	switch key {
	case "Time":
		vm.PushNumber(L, f64(keypoint.Time))
	case "Value":
		vm.PushNumber(L, f64(keypoint.Value))
	case "Envelope":
		vm.PushNumber(L, f64(keypoint.Envelope))
	case:
		return false
	}

	return true
}

number_sequence_keypoint_equal :: proc(value, other, ctx: rawptr) -> bool {
	return NumberSequenceKeypoint_Equal(
		(cast(^NumberSequenceKeypoint)value)^,
		(cast(^NumberSequenceKeypoint)other)^,
	)
}

number_sequence_keypoint_string :: proc(value, ctx: rawptr) -> string {
	k := cast(^NumberSequenceKeypoint)value
	return fmt.tprintf("%g, %g, %g", k.Time, k.Value, k.Envelope)
}

number_sequence_keypoint_destroy :: proc(value, ctx: rawptr) {
	free(cast(^NumberSequenceKeypoint)value)
}

NumberSequenceKeypoint_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name    = "NumberSequenceKeypoint",
		get     = number_sequence_keypoint_get,
		string  = number_sequence_keypoint_string,
		destroy = number_sequence_keypoint_destroy,
		equal   = number_sequence_keypoint_equal,
	}
}

NumberSequenceKeypoint_Install_Fields :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
) {
	add_library_function(L, binding, "new", number_sequence_keypoint_new)
}

push_number_sequence :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
	value: NumberSequence,
) {
	push_value(L, binding, value)
}

Push_NumberSequence :: proc(
	L: ^vm.State,
	registry: ^Registry,
	value: NumberSequence,
) {
	push_number_sequence(
		L,
		&registry.number_sequence,
		NumberSequence_Clone(value),
	)
}

Arg_NumberSequence :: proc(
	L: ^vm.State,
	index: int,
	registry: ^Registry,
) -> NumberSequence {
	return require_number_sequence(L, index, &registry.number_sequence)^
}

require_number_sequence :: proc(
	L: ^vm.State,
	index: int,
	binding: ^vm.Userdata_Binding,
) -> ^NumberSequence {
	if !vm.IsUserdataType(L, index, binding) {
		_ = vm.RaiseError(L, "expected NumberSequence")
		return nil
	}

	return cast(^NumberSequence)vm.UserdataValue(L, index)
}

number_sequence_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()

	binding := binding_from_upvalue(L)
	registry := registry_from_binding(binding)

	if registry == nil {
		return vm.RaiseError(L, "NumberSequence registry is unavailable")
	}

	if vm.IsTable(L, 1) {
		count := vm.RawLen(L, 1)

		keypoints := make([]NumberSequenceKeypoint, count)
		for i in 0 ..< count {
			_ = vm.RawGetIndex(L, 1, i+1)
			keypoints[i] = require_number_sequence_keypoint(
				L,
				-1,
				&registry.number_sequence_keypoint,
			)^
			vm.Pop(L, 1)
		}

		sequence, ok := NumberSequence_FromKeypoints(keypoints)
		delete(keypoints)

		if !ok {
			return vm.RaiseError(L, "invalid NumberSequence keypoints")
		}

		push_number_sequence(L, binding, sequence)
		return 1
	}

	start := f32(vm.ArgNumber(L, 1))

	if vm.IsNoneOrNil(L, 2) {
		push_number_sequence(L, binding, NumberSequence_New(start))
	} else {
		finish := f32(vm.ArgNumber(L, 2))
		push_number_sequence(L, binding, NumberSequence_New2(start, finish))
	}

	return 1
}

number_sequence_get :: proc(
	L: ^vm.State,
	value,
	ctx: rawptr,
	key: string,
) -> bool {
	sequence := cast(^NumberSequence)value
	binding := cast(^vm.Userdata_Binding)ctx
	registry := registry_from_binding(binding)

	switch key {
	case "Keypoints":
		if registry == nil {
			return false
		}

		vm.NewTable(L, len(sequence.Keypoints), 0)

		for keypoint, i in sequence.Keypoints {
			push_number_sequence_keypoint(
				L,
				&registry.number_sequence_keypoint,
				keypoint,
			)
			vm.RawSetIndex(L, -2, i+1)
		}

		vm.SetReadOnly(L, -1)

	case:
		return false
	}

	return true
}

number_sequence_equal :: proc(value, other, ctx: rawptr) -> bool {
	return NumberSequence_Equal(
		(cast(^NumberSequence)value)^,
		(cast(^NumberSequence)other)^,
	)
}

number_sequence_string :: proc(value, ctx: rawptr) -> string {
	sequence := cast(^NumberSequence)value
	result := ""

	for keypoint, i in sequence.Keypoints {
		entry := fmt.tprintf(
			"%g: %g ± %g",
			keypoint.Time,
			keypoint.Value,
			keypoint.Envelope,
		)

		if i == 0 {
			result = entry
		} else {
			result = fmt.tprintf("%s; %s", result, entry)
		}
	}

	return result
}

number_sequence_destroy :: proc(value, ctx: rawptr) {
	sequence := cast(^NumberSequence)value
	NumberSequence_Destroy(sequence^)
	free(sequence)
}

NumberSequence_Luau_Binding :: proc() -> vm.Userdata_Binding {
	return vm.Userdata_Binding{
		name    = "NumberSequence",
		get     = number_sequence_get,
		string  = number_sequence_string,
		destroy = number_sequence_destroy,
		equal   = number_sequence_equal,
	}
}

NumberSequence_Install_Fields :: proc(
	L: ^vm.State,
	binding: ^vm.Userdata_Binding,
) {
	add_library_function(L, binding, "new", number_sequence_new)
}
