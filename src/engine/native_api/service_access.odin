package native_api

import classes "../classes"
import services "../services"
import vm "../vm"
import odin_runtime "base:runtime"

sdk_service_descriptor :: proc(ctx: ^Context, name: cstring) -> ^services.Service_Descriptor {
	if ctx == nil || !ctx.active || ctx.services == nil || name == nil {return nil}
	return services.Find_Service(ctx.services, string(name))
}

@(export)
Kinemium_ServiceGetHandleAt :: proc "c" (ctx: ^Context, index: u64) -> u64 {
	context = odin_runtime.default_context()
	if ctx == nil ||
	   !ctx.active ||
	   ctx.services == nil ||
	   index >= u64(len(ctx.services.services)) {return 0}
	name := ctx.services.services[int(index)].name
	return register_handle(ctx, services.Ensure_Service(ctx.services, name))
}

@(export)
Kinemium_ServiceCopyClassName :: proc "c" (
	ctx: ^Context,
	name: cstring,
	buffer: [^]u8,
	capacity: u64,
) -> i64 {
	context = odin_runtime.default_context()
	desc := sdk_service_descriptor(ctx, name)
	if desc == nil {return -1}
	return sdk_copy_string(desc.class_name, buffer, capacity)
}

@(export)
Kinemium_ServiceCopyGlobalName :: proc "c" (
	ctx: ^Context,
	name: cstring,
	buffer: [^]u8,
	capacity: u64,
) -> i64 {
	context = odin_runtime.default_context()
	desc := sdk_service_descriptor(ctx, name)
	if desc == nil {return -1}
	return sdk_copy_string(desc.global_name, buffer, capacity)
}

@(export)
Kinemium_ServiceIsInitialized :: proc "c" (ctx: ^Context, name: cstring) -> bool {
	context = odin_runtime.default_context()
	desc := sdk_service_descriptor(ctx, name)
	return desc != nil && desc.object != nil && !desc.object.destroyed
}

@(export)
Kinemium_ServiceGetProperty :: proc "c" (
	ctx: ^Context,
	name, property: cstring,
	output: ^SDK_Value,
	text_buffer: [^]u8,
	text_capacity: u64,
) -> bool {
	context = odin_runtime.default_context()
	desc := sdk_service_descriptor(ctx, name)
	if desc == nil ||
	   property == nil ||
	   output == nil ||
	   ctx.script_vm == nil ||
	   ctx.script_vm.L == nil {return false}
	object := services.Ensure_Service(ctx.services, desc.name)
	if object == nil {return false}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	if !sdk_property_get(ctx, object, string(property)) {return false}
	sdk_pull_value(ctx, output, text_buffer, text_capacity)
	if output.kind == .String && text_buffer != nil && text_capacity > 0 {
		output.text = cast(cstring)text_buffer
	}
	sdk_clear_error(ctx)
	return true
}

@(export)
Kinemium_ServiceSetProperty :: proc "c" (
	ctx: ^Context,
	name, property: cstring,
	value: ^SDK_Value,
) -> bool {
	context = odin_runtime.default_context()
	desc := sdk_service_descriptor(ctx, name)
	if desc == nil ||
	   property == nil ||
	   value == nil ||
	   ctx.script_vm == nil ||
	   ctx.script_vm.L == nil {return false}
	object := services.Ensure_Service(ctx.services, desc.name)
	if object == nil {return false}
	if !property_exists(ctx, object, string(property)) {
		sdk_error(ctx, "unknown service property")
		return false
	}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	vm.PushFunction(L, "Kinemium_SetServiceProperty", sdk_setter)
	classes.Push_Object(L, object)
	vm.PushString(L, string(property))
	if !sdk_push_value(ctx, value^) {
		sdk_error(ctx, "unsupported service property value")
		return false
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
