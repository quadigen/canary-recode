package native_api

import vm "../vm"
import odin_runtime "base:runtime"

@(export)
Kinemium_EvaluateLuau :: proc "c" (
	ctx: ^Context,
	source: cstring,
	output: ^SDK_Value,
	text_buffer: [^]u8,
	text_capacity: u64,
) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil ||
	   !ctx.active ||
	   ctx.script_vm == nil ||
	   ctx.script_vm.L == nil ||
	   source == nil {
		return false
	}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)

	ok, err := vm.LoadSource(ctx.script_vm, L, string(source), "NativeSDK")
	if !ok {
		sdk_error(ctx, err)
		delete(err)
		return false
	}

	result_count := 0
	if output != nil {result_count = 1}
	ok, err = vm.ProtectedCall(L, 0, result_count)
	if !ok {
		sdk_error(ctx, err)
		delete(err)
		return false
	}
	if output != nil {
		sdk_pull_value(ctx, output, text_buffer, text_capacity)
		if output.kind == .String && text_buffer != nil && text_capacity > 0 {
			output.text = cast(cstring)text_buffer
		}
	}
	sdk_clear_error(ctx)
	return true
}
