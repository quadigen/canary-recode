package native_api

import classes "../classes"
import vm "../vm"
import odin_runtime "base:runtime"

Native_Export_Call :: struct {
	handler:  classes.Class_Export_Handler,
	namecall: classes.Class_Namecall,
	details:  classes.Class_Export_Context,
}

native_export_trampoline :: proc "c" (L: ^vm.State) -> i32 {
	context = odin_runtime.default_context()
	call := cast(^Native_Export_Call)vm.UpvaluePointer(L)
	if call == nil {return vm.RaiseError(L, "native export callback is unavailable")}
	call.details.L = L
	if call.handler != nil {return call.handler(&call.details)}
	if call.namecall != nil {
		count, handled := call.namecall(
			L,
			call.details.object,
			call.details.datatypes,
			call.details.enums,
			call.details.method,
		)
		if handled {return count}
	}
	return vm.RaiseError(L, "exported native method is unavailable")
}

find_native_export :: proc(
	ctx: ^Context,
	object: ^classes.Object,
	name: string,
) -> (
	^classes.Class_Export,
	^classes.Class_Descriptor,
) {
	if ctx == nil || object == nil {return nil, nil}
	current := object.class
	for current != nil {
		descriptor := classes.Find_Class(ctx.classes, current.name)
		if descriptor != nil {
			found := classes.Find_Export(descriptor, name)
			if found != nil {return found, descriptor}
		}
		current = current.parent
	}
	return nil, nil
}

@(export)
Kinemium_InvokeExport :: proc "c" (
	ctx: ^Context,
	handle: u64,
	method: cstring,
	args: [^]SDK_Value,
	arg_count: u64,
	output: ^SDK_Value,
	text_buffer: [^]u8,
	text_capacity: u64,
) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if object == nil || method == nil || arg_count > 32 || (arg_count > 0 && args == nil) {
		sdk_error(ctx, "invalid native export invocation")
		return false
	}
	export_entry, export_owner := find_native_export(ctx, object, string(method))
	if export_entry == nil {
		sdk_error(ctx, "native export does not exist")
		return false
	}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	call := Native_Export_Call {
		handler = export_entry.handler,
		namecall = export_owner.namecall,
		details = classes.Class_Export_Context {
			L = L,
			object = object,
			datatypes = ctx.datatypes,
			enums = ctx.classes.enums,
			method = string(method),
		},
	}
	vm.PushLightUserdata(L, &call)
	vm.PushFunction(L, "KinemiumNativeExport", native_export_trampoline, 1)
	classes.Push_Object(L, object)
	for i in 0 ..< int(arg_count) {
		if !sdk_push_value(ctx, args[i]) {
			sdk_error(ctx, "invalid native export argument")
			return false
		}
	}
	result_count := 0
	if output != nil {result_count = 1}
	ok, err := vm.ProtectedCall(L, int(arg_count) + 1, result_count)
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
