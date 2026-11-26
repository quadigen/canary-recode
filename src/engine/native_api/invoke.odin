package native_api

import classes "../classes"
import vm "../vm"
import odin_runtime "base:runtime"

SDK_Value_Kind :: enum i32 {
	Nil      = 0,
	Boolean  = 1,
	Number   = 2,
	String   = 3,
	Vector3  = 4,
	Instance = 5,
	Other    = 6,
}

SDK_Value :: struct {
	kind:        SDK_Value_Kind,
	number:      f64,
	boolean:     bool,
	vector:      SDK_Vector3,
	instance:    u64,
	text:        cstring,
	text_length: u64,
}

sdk_push_value :: proc(ctx: ^Context, value: SDK_Value) -> bool {
	L := ctx.script_vm.L
	#partial switch value.kind {
	case .Nil:
		vm.PushNil(L)
	case .Boolean:
		vm.PushBoolean(L, value.boolean)
	case .Number:
		vm.PushNumber(L, value.number)
	case .String:
		if value.text == nil {return false}
		vm.PushString(L, string(value.text))
	case .Vector3:
		vm.PushVector3(L, value.vector.x, value.vector.y, value.vector.z)
	case .Instance:
		object: ^classes.Object
		if value.instance != 0 {
			object = resolve_handle(ctx, value.instance)
			if object == nil {return false}
		}
		classes.Push_Object(L, object)
	case:
		return false
	}
	return true
}

sdk_pull_value :: proc(ctx: ^Context, output: ^SDK_Value, text_buffer: [^]u8, capacity: u64) {
	L := ctx.script_vm.L
	result: SDK_Value
	kind := sdk_value_type(L)
	#partial switch kind {
	case .Nil:
		result.kind = .Nil
	case .Boolean:
		result.kind = .Boolean
		result.boolean = vm.ArgBoolean(L, -1)
	case .Number:
		result.kind = .Number
		result.number, _ = vm.ToNumber(L, -1)
	case .String:
		result.kind = .String
		value, _ := vm.ToString(L, -1)
		result.text_length = u64(len(value))
		_ = sdk_copy_string(value, text_buffer, capacity)
	case .Vector3:
		result.kind = .Vector3
		result.vector.x, result.vector.y, result.vector.z = vm.ArgVector3(L, -1)
	case .Instance:
		result.kind = .Instance
		result.instance = register_handle(ctx, cast(^classes.Object)vm.UserdataValue(L, -1))
	case:
		result.kind = .Other
	}
	output^ = result
}

@(export)
Kinemium_Invoke :: proc "c" (
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
		sdk_error(ctx, "invalid invocation")
		return false
	}
	export_entry, _ := find_native_export(ctx, object, string(method))
	if export_entry != nil {
		return Kinemium_InvokeExport(
			ctx,
			handle,
			method,
			args,
			arg_count,
			output,
			text_buffer,
			text_capacity,
		)
	}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)

	vm.PushFunction(L, "Kinemium_GetMethod", sdk_getter)
	classes.Push_Object(L, object)
	vm.PushString(L, string(method))
	ok, err := vm.ProtectedCall(L, 2, 1)
	if !ok {
		sdk_error(ctx, err)
		delete(err)
		return false
	}
	if !vm.IsFunction(L, -1) {
		sdk_error(ctx, "unknown instance method")
		return false
	}
	classes.Push_Object(L, object)
	for i in 0 ..< int(arg_count) {
		if !sdk_push_value(ctx, args[i]) {
			sdk_error(ctx, "invalid method argument")
			return false
		}
	}
	return_count := 0
	if output != nil {return_count = 1}
	ok, err = vm.ProtectedCall(L, int(arg_count) + 1, return_count)
	if !ok {
		sdk_error(ctx, err)
		delete(err)
		return false
	}
	if output != nil {sdk_pull_value(ctx, output, text_buffer, text_capacity)}
	sdk_clear_error(ctx)
	return true
}
