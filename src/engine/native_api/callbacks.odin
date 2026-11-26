package native_api

import classes "../classes"
import vm "../vm"
import odin_runtime "base:runtime"
import "core:strings"

SDK_Native_Callback :: proc "c" (
	user_data: rawptr,
	argument_count: u32,
	arguments: [^]SDK_Value,
	output: ^SDK_Value,
) -> bool

Native_Registration :: struct {
	ctx:       ^Context,
	callback:  SDK_Native_Callback,
	user_data: rawptr,
	name:      string,
	library:   string,
}

sdk_native_dispatch :: proc "c" (L: ^vm.State) -> i32 {
	context = odin_runtime.default_context()
	registration := cast(^Native_Registration)vm.UpvaluePointer(L)
	if registration == nil || registration.ctx == nil || registration.callback == nil {
		return vm.RaiseError(L, "native callback is unavailable")
	}
	count := vm.StackTop(L)
	if count > 32 {return vm.RaiseError(L, "too many native callback arguments")}

	input: [32]SDK_Value
	temporary_strings: [dynamic]cstring
	defer {
		for value in temporary_strings {delete(value)}
		delete(temporary_strings)
	}
	for i in 0 ..< count {
		index := i + 1
		value := &input[i]
		#partial switch vm.TypeOf(L, index) {
		case .Nil:
			value.kind = .Nil
		case .Boolean:
			value.kind = .Boolean
			value.boolean = vm.ArgBoolean(L, index)
		case .Number, .Integer:
			value.kind = .Number
			value.number, _ = vm.ToNumber(L, index)
		case .String:
			value.kind = .String
			text_value, _ := vm.ToString(L, index)
			copy := strings.clone_to_cstring(text_value)
			append(&temporary_strings, copy)
			value.text = copy
			value.text_length = u64(len(text_value))
		case .Vector:
			value.kind = .Vector3
			value.vector.x, value.vector.y, value.vector.z = vm.ArgVector3(L, index)
		case .Userdata:
			binding := vm.UserdataBindingOf(L, index)
			if binding != nil && binding.name == "Instance" {
				value.kind = .Instance
				value.instance = register_handle(
					registration.ctx,
					cast(^classes.Object)vm.UserdataValue(L, index),
				)
			} else {
				value.kind = .Other
			}
		case:
			value.kind = .Other
		}
	}

	output: SDK_Value
	if !registration.callback(registration.user_data, u32(count), &input[0], &output) {
		return vm.RaiseError(L, "native callback returned failure")
	}
	if !sdk_push_value(registration.ctx, output) {
		return vm.RaiseError(L, "native callback returned an invalid value")
	}
	return 1
}

@(export)
Kinemium_RegisterNativeFunction :: proc "c" (
	ctx: ^Context,
	name: cstring,
	callback: SDK_Native_Callback,
	user_data: rawptr,
) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil ||
	   !ctx.active ||
	   name == nil ||
	   callback == nil ||
	   string(name) == "" {return false}
	_ = vm.GetGlobal(ctx.script_vm.L, string(name))
	already_registered := vm.TypeOf(ctx.script_vm.L, -1) != .Nil
	vm.Pop(ctx.script_vm.L)
	if already_registered {sdk_error(ctx, "native function name is already in use"); return false}
	reg := new(Native_Registration)
	reg^ = Native_Registration {
		ctx       = ctx,
		callback  = callback,
		user_data = user_data,
		name      = strings.clone(string(name)),
	}
	append(&ctx.native_callbacks, reg)
	vm.PushLightUserdata(ctx.script_vm.L, reg)
	vm.PushFunction(ctx.script_vm.L, string(name), sdk_native_dispatch, 1)
	vm.SetGlobal(ctx.script_vm.L, string(name))
	return true
}

@(export)
Kinemium_UnregisterNativeFunction :: proc "c" (ctx: ^Context, name: cstring) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || !ctx.active || name == nil {return false}
	found := false
	for registration in ctx.native_callbacks {
		if registration.ctx == ctx &&
		   registration.callback != nil &&
		   registration.name == string(name) &&
		   registration.library == "" {
			registration.callback = nil
			registration.ctx = nil
			found = true
		}
	}
	if !found {return false}
	vm.PushNil(ctx.script_vm.L)
	vm.SetGlobal(ctx.script_vm.L, string(name))
	return true
}

sdk_unregister_native_callback :: proc(ctx: ^Context, reg: ^Native_Registration) {
	if ctx == nil || reg == nil || reg.ctx != ctx || reg.callback == nil {return}
	L := ctx.script_vm.L
	if L != nil {
		if reg.library != "" {
			_ = vm.GetGlobal(L, reg.library)
			if vm.TypeOf(L, -1) == .Table {
				vm.PushNil(L)
				vm.SetField(L, -2, reg.name)
			}
			vm.Pop(L)
		} else {
			vm.PushNil(L)
			vm.SetGlobal(L, reg.name)
		}
	}
	reg.callback = nil
	reg.ctx = nil
}

@(export)
Kinemium_RegisterLibraryFunction :: proc "c" (
	ctx: ^Context,
	library: cstring,
	name: cstring,
	callback: SDK_Native_Callback,
	user_data: rawptr,
) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil ||
	   !ctx.active ||
	   ctx.script_vm == nil ||
	   library == nil ||
	   name == nil ||
	   callback == nil ||
	   string(library) == "" ||
	   string(name) == "" {return false}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	_ = vm.GetGlobal(L, string(library))
	make_table := vm.TypeOf(L, -1) == .Nil
	if make_table {
		vm.Pop(L)
		vm.NewTable(L, 0, 1)
	} else if vm.TypeOf(L, -1) != .Table {
		sdk_error(ctx, "native library global is not a table")
		return false
	}
	_ = vm.GetField(L, -1, string(name))
	exists := vm.TypeOf(L, -1) != .Nil
	vm.Pop(L)
	if exists {sdk_error(ctx, "native library function name already used"); return false}
	reg := new(Native_Registration)
	reg^ = Native_Registration {
		ctx       = ctx,
		callback  = callback,
		user_data = user_data,
		name      = strings.clone(string(name)),
		library   = strings.clone(string(library)),
	}
	append(&ctx.native_callbacks, reg)
	vm.PushLightUserdata(L, reg)
	vm.PushFunction(L, string(name), sdk_native_dispatch, 1)
	vm.SetField(L, -2, string(name))
	if make_table {
		vm.SetGlobal(L, string(library))
	}
	sdk_clear_error(ctx)
	return true
}

@(export)
Kinemium_UnregisterLibraryFunction :: proc "c" (ctx: ^Context, library, name: cstring) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || !ctx.active || library == nil || name == nil {return false}
	for reg in ctx.native_callbacks {
		if reg != nil &&
		   reg.ctx == ctx &&
		   reg.callback != nil &&
		   reg.library == string(library) &&
		   reg.name == string(name) {
			sdk_unregister_native_callback(ctx, reg)
			return true
		}
	}
	return false
}
