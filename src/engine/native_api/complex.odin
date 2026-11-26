package native_api

import datatypes "../datatypes"
import vm "../vm"
import odin_runtime "base:runtime"

SDK_Color3 :: struct {
	r, g, b: f64,
}

SDK_CFrame :: struct {
	x, y, z:       f64,
	r00, r01, r02: f64,
	r10, r11, r12: f64,
	r20, r21, r22: f64,
}

sdk_cframe_to_engine :: proc(value: SDK_CFrame) -> datatypes.CFrame {
	return datatypes.CFrame {
		x = value.x,
		y = value.y,
		z = value.z,
		r00 = value.r00,
		r01 = value.r01,
		r02 = value.r02,
		r10 = value.r10,
		r11 = value.r11,
		r12 = value.r12,
		r20 = value.r20,
		r21 = value.r21,
		r22 = value.r22,
	}
}

sdk_cframe_from_engine :: proc(value: datatypes.CFrame) -> SDK_CFrame {
	return SDK_CFrame {
		x = value.x,
		y = value.y,
		z = value.z,
		r00 = value.r00,
		r01 = value.r01,
		r02 = value.r02,
		r10 = value.r10,
		r11 = value.r11,
		r12 = value.r12,
		r20 = value.r20,
		r21 = value.r21,
		r22 = value.r22,
	}
}

@(export)
Kinemium_HandleGetColor3 :: proc "c" (
	ctx: ^Context,
	handle: u64,
	property: cstring,
	output: ^SDK_Color3,
) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if ctx == nil || object == nil || property == nil || output == nil {return false}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	if !sdk_property_get(ctx, object, string(property)) {return false}
	if !vm.IsUserdataType(L, -1, &ctx.datatypes.color3) {
		sdk_error(ctx, "property is not a Color3")
		return false
	}
	value := datatypes.Arg_Color3(L, -1, ctx.datatypes)
	output^ = SDK_Color3{f64(value.R), f64(value.G), f64(value.B)}
	sdk_clear_error(ctx)
	return true
}

@(export)
Kinemium_HandleSetColor3 :: proc "c" (
	ctx: ^Context,
	handle: u64,
	property: cstring,
	value: SDK_Color3,
) -> bool {
	context = odin_runtime.default_context()
	if property == nil {return false}
	return sdk_property_set(
		ctx,
		resolve_handle(ctx, handle),
		string(property),
		.Color3,
		color = value,
	)
}

@(export)
Kinemium_HandleGetCFrame :: proc "c" (
	ctx: ^Context,
	handle: u64,
	property: cstring,
	output: ^SDK_CFrame,
) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if ctx == nil || object == nil || property == nil || output == nil {return false}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	if !sdk_property_get(ctx, object, string(property)) {return false}
	if !vm.IsUserdataType(L, -1, &ctx.datatypes.c_frame) {
		sdk_error(ctx, "property is not a CFrame")
		return false
	}
	value := datatypes.Arg_CFrame(L, -1, ctx.datatypes)
	output^ = sdk_cframe_from_engine(value)
	sdk_clear_error(ctx)
	return true
}

@(export)
Kinemium_HandleSetCFrame :: proc "c" (
	ctx: ^Context,
	handle: u64,
	property: cstring,
	value: SDK_CFrame,
) -> bool {
	context = odin_runtime.default_context()
	if property == nil {return false}
	return sdk_property_set(
		ctx,
		resolve_handle(ctx, handle),
		string(property),
		.CFrame,
		frame = value,
	)
}
