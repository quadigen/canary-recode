package native_api

import classes "../classes"
import datatypes "../datatypes"
import vm "../vm"
import odin_runtime "base:runtime"
import "core:strings"

SDK_Vector3 :: struct {
	x, y, z: f64,
}

SDK_Property_Type :: enum i32 {
	Invalid  = -1,
	Nil      = 0,
	Boolean  = 1,
	Number   = 2,
	String   = 3,
	Vector3  = 4,
	Instance = 5,
	Other    = 6,
}

SDK_Input :: enum {
	Boolean,
	Number,
	String,
	Vector3,
	Instance,
	Nil,
	Color3,
	CFrame,
}

sdk_copy_string :: proc(value: string, buffer: [^]u8, capacity: u64) -> i64 {
	if buffer != nil && capacity > 0 {
		count := min(u64(len(value)), capacity - 1)
		for i in 0 ..< int(count) {
			buffer[i] = value[i]
		}
		buffer[int(count)] = 0
	}
	return i64(len(value))
}

sdk_error :: proc(ctx: ^Context, message: string) {
	if ctx == nil {return}
	delete(ctx.last_error)
	ctx.last_error = strings.clone(message)
}

sdk_clear_error :: proc(ctx: ^Context) {
	if ctx == nil {return}
	delete(ctx.last_error)
	ctx.last_error = ""
}

sdk_getter :: proc "c" (L: ^vm.State) -> i32 {
	context = odin_runtime.default_context()
	_ = vm.GetField(L, 1, vm.ArgString(L, 2))
	return 1
}

sdk_setter :: proc "c" (L: ^vm.State) -> i32 {
	context = odin_runtime.default_context()
	vm.PushValue(L, 3)
	vm.SetField(L, 1, vm.ArgString(L, 2))
	return 0
}

sdk_property_get :: proc(ctx: ^Context, object: ^classes.Object, property: string) -> bool {
	if ctx == nil || object == nil {
		sdk_error(ctx, "invalid instance handle")
		return false
	}
	if !property_exists(ctx, object, property) {
		sdk_error(ctx, "unknown property")
		return false
	}
	if !ctx.active || ctx.script_vm == nil || ctx.script_vm.L == nil {return false}
	L := ctx.script_vm.L
	if !vm.CheckStack(L, 12) {
		sdk_error(ctx, "insufficient Luau stack space to read property")
		return false
	}
	vm.PushFunction(L, "Kinemium_GetProperty", sdk_getter)
	classes.Push_Object(L, object)
	vm.PushString(L, property)
	ok, err := vm.ProtectedCall(L, 2, 1)
	if !ok {
		sdk_error(ctx, err)
		delete(err)
		return false
	}
	return true
}

sdk_property_set :: proc(
	ctx: ^Context,
	object: ^classes.Object,
	property: string,
	kind: SDK_Input,
	number: f64 = 0,
	boolean: bool = false,
	string_value: string = "",
	vector: SDK_Vector3 = {},
	reference: ^classes.Object = nil,
	color: SDK_Color3 = {},
	frame: SDK_CFrame = {},
) -> bool {
	if ctx == nil || object == nil {
		sdk_error(ctx, "invalid instance handle")
		return false
	}
	if !property_exists(ctx, object, property) {
		sdk_error(ctx, "unknown property")
		return false
	}
	if !ctx.active || ctx.script_vm == nil || ctx.script_vm.L == nil {return false}
	L := ctx.script_vm.L
	if !vm.CheckStack(L, 16) {
		sdk_error(ctx, "insufficient Luau stack space to set property")
		return false
	}
	initial_top := vm.StackTop(L)
	defer vm.SetStackTop(L, initial_top)
	vm.PushFunction(L, "Kinemium_SetProperty", sdk_setter)
	classes.Push_Object(L, object)
	vm.PushString(L, property)
	switch kind {
	case .Boolean:
		vm.PushBoolean(L, boolean)
	case .Number:
		vm.PushNumber(L, number)
	case .String:
		vm.PushString(L, string_value)
	case .Vector3:
		vm.PushVector3(L, vector.x, vector.y, vector.z)
	case .Instance:
		classes.Push_Object(L, reference)
	case .Nil:
		vm.PushNil(L)
	case .Color3:
		datatypes.Push_Color3(
			L,
			ctx.datatypes,
			datatypes.Color3{R = f32(color.r), G = f32(color.g), B = f32(color.b)},
		)
	case .CFrame:
		datatypes.Push_CFrame(L, ctx.datatypes, sdk_cframe_to_engine(frame))
	}
	ok, err := vm.ProtectedCall(L, 3, 0)
	if !ok {
		sdk_error(ctx, err)
		delete(err)
		return false
	}
	sdk_clear_error(ctx)
	return true
}

sdk_value_type :: proc(L: ^vm.State) -> SDK_Property_Type {
	#partial switch vm.TypeOf(L, -1) {
	case .Nil:
		return .Nil
	case .Boolean:
		return .Boolean
	case .Number, .Integer:
		return .Number
	case .String:
		return .String
	case .Vector:
		return .Vector3
	case .Userdata:
		binding := vm.UserdataBindingOf(L, -1)
		if binding != nil && binding.name == "Instance" {return .Instance}
		return .Other
	case:
		return .Other
	}
}

@(export)
Kinemium_HandleGetPropertyType :: proc "c" (ctx: ^Context, handle: u64, property: cstring) -> i32 {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if ctx == nil || property == nil || object == nil {
		sdk_error(ctx, "invalid property request")
		return i32(SDK_Property_Type.Invalid)
	}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	if !sdk_property_get(ctx, object, string(property)) {return i32(SDK_Property_Type.Invalid)}
	result := sdk_value_type(L)
	sdk_clear_error(ctx)
	return i32(result)
}

@(export)
Kinemium_HandleGetDynamicBoolean :: proc "c" (
	ctx: ^Context,
	handle: u64,
	property: cstring,
	output: ^bool,
) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if ctx == nil || property == nil || output == nil || object == nil {return false}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	if !sdk_property_get(ctx, object, string(property)) {return false}
	if !vm.IsBoolean(L, -1) {sdk_error(ctx, "property is not a boolean"); return false}
	output^ = vm.ArgBoolean(L, -1)
	sdk_clear_error(ctx)
	return true
}

@(export)
Kinemium_HandleSetDynamicBoolean :: proc "c" (
	ctx: ^Context,
	handle: u64,
	property: cstring,
	value: bool,
) -> bool {
	context = odin_runtime.default_context()
	if property == nil {return false}
	return sdk_property_set(
		ctx,
		resolve_handle(ctx, handle),
		string(property),
		.Boolean,
		boolean = value,
	)
}

@(export)
Kinemium_HandleSetDynamicNumber :: proc "c" (
	ctx: ^Context,
	handle: u64,
	property: cstring,
	value: f64,
) -> bool {
	context = odin_runtime.default_context()
	if property == nil {return false}
	return sdk_property_set(
		ctx,
		resolve_handle(ctx, handle),
		string(property),
		.Number,
		number = value,
	)
}

@(export)
Kinemium_HandleSetDynamicString :: proc "c" (
	ctx: ^Context,
	handle: u64,
	property: cstring,
	value: cstring,
) -> bool {
	context = odin_runtime.default_context()
	if property == nil || value == nil {return false}
	return sdk_property_set(
		ctx,
		resolve_handle(ctx, handle),
		string(property),
		.String,
		string_value = string(value),
	)
}

@(export)
Kinemium_HandleGetDynamicVector3 :: proc "c" (
	ctx: ^Context,
	handle: u64,
	property: cstring,
	output: ^SDK_Vector3,
) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if ctx == nil || property == nil || output == nil || object == nil {return false}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	if !sdk_property_get(ctx, object, string(property)) {return false}
	if vm.TypeOf(L, -1) != .Vector {sdk_error(ctx, "property is not a Vector3"); return false}
	x, y, z := vm.ArgVector3(L, -1)
	output^ = SDK_Vector3{x, y, z}
	sdk_clear_error(ctx)
	return true
}

@(export)
Kinemium_HandleSetDynamicVector3 :: proc "c" (
	ctx: ^Context,
	handle: u64,
	property: cstring,
	value: SDK_Vector3,
) -> bool {
	context = odin_runtime.default_context()
	if property == nil {return false}
	return sdk_property_set(
		ctx,
		resolve_handle(ctx, handle),
		string(property),
		.Vector3,
		vector = value,
	)
}

@(export)
Kinemium_HandleGetDynamicInstance :: proc "c" (
	ctx: ^Context,
	handle: u64,
	property: cstring,
	output: ^u64,
) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if ctx == nil || property == nil || output == nil || object == nil {return false}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	if !sdk_property_get(ctx, object, string(property)) {return false}
	if vm.TypeOf(L, -1) == .Nil {
		output^ = 0
	} else if sdk_value_type(L) == .Instance {
		value := cast(^classes.Object)vm.UserdataValue(L, -1)
		output^ = register_handle(ctx, value)
	} else {
		sdk_error(ctx, "property is not an Instance")
		return false
	}
	sdk_clear_error(ctx)
	return true
}

@(export)
Kinemium_HandleSetDynamicInstance :: proc "c" (
	ctx: ^Context,
	handle: u64,
	property: cstring,
	value: u64,
) -> bool {
	context = odin_runtime.default_context()
	if property == nil {return false}
	reference: ^classes.Object
	if value != 0 {
		reference = resolve_handle(ctx, value)
		if reference == nil {sdk_error(ctx, "invalid referenced instance handle"); return false}
	}
	return sdk_property_set(
		ctx,
		resolve_handle(ctx, handle),
		string(property),
		.Instance,
		reference = reference,
	)
}

@(export)
Kinemium_HandleSetDynamicNil :: proc "c" (ctx: ^Context, handle: u64, property: cstring) -> bool {
	context = odin_runtime.default_context()
	if property == nil {return false}
	return sdk_property_set(ctx, resolve_handle(ctx, handle), string(property), .Nil)
}

@(export)
Kinemium_SetGlobalBoolean :: proc "c" (ctx: ^Context, name: cstring, value: bool) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || name == nil {return false}
	vm.PushBoolean(ctx.script_vm.L, value)
	vm.SetGlobal(ctx.script_vm.L, string(name))
	return true
}

@(export)
Kinemium_GetGlobalBoolean :: proc "c" (ctx: ^Context, name: cstring, output: ^bool) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || name == nil || output == nil {return false}
	L := ctx.script_vm.L
	_ = vm.GetGlobal(L, string(name))
	defer vm.Pop(L)
	if !vm.IsBoolean(L, -1) {return false}
	output^ = vm.ArgBoolean(L, -1)
	return true
}

@(export)
Kinemium_SetGlobalVector3 :: proc "c" (ctx: ^Context, name: cstring, value: SDK_Vector3) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || name == nil {return false}
	vm.PushVector3(ctx.script_vm.L, value.x, value.y, value.z)
	vm.SetGlobal(ctx.script_vm.L, string(name))
	return true
}

@(export)
Kinemium_GetGlobalVector3 :: proc "c" (
	ctx: ^Context,
	name: cstring,
	output: ^SDK_Vector3,
) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || name == nil || output == nil {return false}
	L := ctx.script_vm.L
	_ = vm.GetGlobal(L, string(name))
	defer vm.Pop(L)
	if vm.TypeOf(L, -1) != .Vector {return false}
	x, y, z := vm.ArgVector3(L, -1)
	output^ = SDK_Vector3{x, y, z}
	return true
}

@(export)
Kinemium_SetGlobalInstance :: proc "c" (ctx: ^Context, name: cstring, handle: u64) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || name == nil {return false}
	reference: ^classes.Object
	if handle != 0 {
		reference = resolve_handle(ctx, handle)
		if reference == nil {return false}
	}
	classes.Push_Object(ctx.script_vm.L, reference)
	vm.SetGlobal(ctx.script_vm.L, string(name))
	return true
}

@(export)
Kinemium_GetGlobalInstance :: proc "c" (ctx: ^Context, name: cstring, output: ^u64) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || name == nil || output == nil {return false}
	L := ctx.script_vm.L
	_ = vm.GetGlobal(L, string(name))
	defer vm.Pop(L)
	if vm.TypeOf(L, -1) == .Nil {output^ = 0; return true}
	if sdk_value_type(L) != .Instance {return false}
	output^ = register_handle(ctx, cast(^classes.Object)vm.UserdataValue(L, -1))
	return true
}
