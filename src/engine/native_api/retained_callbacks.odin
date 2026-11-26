package native_api

import vm "../vm"
import odin_runtime "base:runtime"

Native_Retained_Callback :: struct {
	owner:     ^Context,
	handle:    u64,
	reference: i32,
	active:    bool,
}

next_callback_handle: u64 = 1

find_callback :: proc(ctx: ^Context, handle: u64) -> ^Native_Retained_Callback {
	if ctx == nil || ctx.root == nil || handle == 0 {return nil}
	for callback in ctx.root.all_retained_callbacks {
		if callback != nil && callback.handle == handle && callback.active {
			return callback
		}
	}
	return nil
}

retain_callback :: proc(ctx: ^Context, index: int) -> u64 {
	if ctx == nil || !ctx.active || ctx.script_vm == nil || ctx.script_vm.L == nil {return 0}
	L := ctx.script_vm.L
	if !vm.IsFunction(L, index) {return 0}
	reference := vm.RetainValue(L, index)
	if reference <= 0 {return 0}
	callback := new(Native_Retained_Callback)
	callback.owner = ctx
	callback.reference = reference
	callback.handle = next_callback_handle
	next_callback_handle += 1
	if next_callback_handle == 0 {next_callback_handle = 1}
	callback.active = true
	append(&ctx.root.all_retained_callbacks, callback)
	return callback.handle
}

@(export)
Kinemium_RetainLuauCallback :: proc "c" (ctx: ^Context, index: i32) -> u64 {
	context = odin_runtime.default_context()
	return retain_callback(ctx, int(index))
}

@(export)
Kinemium_RetainGlobalFunction :: proc "c" (ctx: ^Context, name: cstring) -> u64 {
	context = odin_runtime.default_context()
	if ctx == nil || !ctx.active || name == nil || ctx.script_vm == nil {return 0}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	_ = vm.GetGlobal(L, string(name))
	return retain_callback(ctx, -1)
}

@(export)
Kinemium_LuauCallbackIsValid :: proc "c" (ctx: ^Context, handle: u64) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || !ctx.active {return false}
	callback := find_callback(ctx, handle)
	if callback == nil || callback.owner == nil || !callback.owner.active {return false}
	return callback.reference > 0 && (ctx == callback.owner || ctx == ctx.root)
}

@(export)
Kinemium_ReleaseLuauCallback :: proc "c" (ctx: ^Context, handle: u64) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || !ctx.active {return false}
	target := find_callback(ctx, handle)
	if target == nil || (target.owner != ctx && ctx != ctx.root) {return false}
	if target.reference > 0 && target.owner != nil && target.owner.script_vm != nil {
		vm.ReleaseValue(target.owner.script_vm.L, target.reference)
	}
	target.reference = 0
	target.active = false
	target.owner = nil
	return true
}

@(export)
Kinemium_CallLuauCallback :: proc "c" (
	ctx: ^Context,
	handle: u64,
	args: [^]SDK_Value,
	count: u32,
	output: ^SDK_Value,
	text_buffer: [^]u8,
	text_capacity: u64,
) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || !ctx.active || count > 32 || (count > 0 && args == nil) {return false}
	callback := find_callback(ctx, handle)
	if callback == nil ||
	   callback.owner == nil ||
	   (callback.owner != ctx && ctx != ctx.root) ||
	   !callback.owner.active ||
	   callback.reference <= 0 {
		return false
	}
	L := callback.owner.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	vm.PushRegistryReference(L, callback.reference)
	for i in 0 ..< int(count) {
		if !sdk_push_value(callback.owner, args[i]) {
			sdk_error(ctx, "invalid callback argument")
			return false
		}
	}
	output_count := 0
	if output != nil {output_count = 1}
	ok, err := vm.ProtectedCall(L, int(count), output_count)
	if !ok {
		sdk_error(ctx, err)
		delete(err)
		return false
	}
	if output != nil {
		sdk_pull_value(callback.owner, output, text_buffer, text_capacity)
		if output.kind == .String && text_buffer != nil && text_capacity > 0 {
			output.text = cast(cstring)text_buffer
		}
	}
	sdk_clear_error(ctx)
	return true
}

ClearOwnerCallbacks :: proc(ctx: ^Context) {
	if ctx == nil || ctx.root == nil {return}
	for callback in ctx.root.all_retained_callbacks {
		if callback == nil || callback.owner != ctx {continue}
		if callback.active &&
		   callback.reference > 0 &&
		   ctx.script_vm != nil &&
		   ctx.script_vm.L != nil {
			vm.ReleaseValue(ctx.script_vm.L, callback.reference)
		}
		callback.reference = 0
		callback.active = false
		callback.owner = nil
	}
	if ctx == ctx.root {
		for callback in ctx.all_retained_callbacks {
			free(callback)
		}
		delete(ctx.all_retained_callbacks)
	}
}
