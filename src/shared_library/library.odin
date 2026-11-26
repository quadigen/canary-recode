package shared_library

import kineffi "../engine/bindings"
import classes "../engine/classes"
import native_api "../engine/native_api"
import sdl3 "../engine/platform"
import renderer "../engine/renderer"
import native_compositor "../engine/renderer/compositor"
import engine_runtime "../engine/runtime"
import services "../engine/services"
import target "../engine/target"
import vm "../engine/vm"
import odin_runtime "base:runtime"

Context :: native_api.Context

Owned_Context :: struct {
	script_vm:          vm.VM,
	environment:        engine_runtime.Environment,
	sdk_renderer:       renderer.RendererObject,
	compositor_backend: native_compositor.Backend,
	owns_renderer:      bool,
}

owned_context :: proc(ctx: ^Context) -> ^Owned_Context {
	if ctx == nil || !ctx.active || !ctx.owns_engine {return nil}
	return cast(^Owned_Context)ctx.engine_owner
}

create_owned :: proc(
	mode: target.Mode,
	filament: ^kineffi.KineFilamentContext = nil,
	window: ^sdl3.Window = nil,
	width: i32 = 0,
	height: i32 = 0,
) -> ^Context {
	owned := new(Owned_Context)
	if filament != nil {
		owned.sdk_renderer.Filament = filament
		owned.sdk_renderer.Window = window
		owned.sdk_renderer.RenderFilament = true
		owned.sdk_renderer.Ready = true
		owned.sdk_renderer.HasViewportRect = true
		owned.sdk_renderer.ViewportRect = [4]i32{0, 0, width, height}
		owned.owns_renderer = true
	}
	owned.script_vm = vm.New()
	render_object: ^renderer.RendererObject
	if filament != nil {render_object = &owned.sdk_renderer}
	engine_runtime.Environment_Init(&owned.environment, &owned.script_vm, render_object, mode)
	ctx := &owned.environment.extensions.native_context
	ctx.engine_owner = owned
	ctx.owns_engine = true
	return ctx
}

@(export)
Kinemium_Create :: proc "c" () -> ^Context {
	context = odin_runtime.default_context()
	return create_owned(target.current_mode)
}

@(export)
Kinemium_Destroy :: proc "c" (ctx: ^Context) {
	context = odin_runtime.default_context()
	owned := owned_context(ctx)
	if owned == nil {return}
	engine_runtime.Environment_Destroy(&owned.environment)
	vm.Close(&owned.script_vm)
	native_compositor.detach(&owned.compositor_backend)
	if owned.owns_renderer && owned.sdk_renderer.Filament != nil {
		kineffi.Kine_Filament_Destroy(owned.sdk_renderer.Filament)
		owned.sdk_renderer.Filament = nil
	}
	free(owned)
}

@(export)
Kinemium_Update :: proc "c" (ctx: ^Context, dt: f32) {
	context = odin_runtime.default_context()
	owned := owned_context(ctx)
	if owned == nil || dt < 0 || dt > 1 {return}
	engine_runtime.Environment_Update_Step(&owned.environment, &owned.script_vm, dt)
}

@(export)
Kinemium_GetService :: proc "c" (ctx: ^Context, name: cstring) -> rawptr {
	context = odin_runtime.default_context()
	owned := owned_context(ctx)
	if owned == nil || name == nil {return nil}
	return(
		cast(rawptr)services.DataModel_Get_Service(
			owned.environment.services.data_model,
			string(name),
		) \
	)
}

@(export)
Kinemium_GetEnvironment :: proc "c" (ctx: ^Context) -> rawptr {
	context = odin_runtime.default_context()
	owned := owned_context(ctx)
	if owned == nil {return nil}
	return &owned.environment
}

@(export)
Kinemium_GetVM :: proc "c" (ctx: ^Context) -> rawptr {
	context = odin_runtime.default_context()
	owned := owned_context(ctx)
	if owned == nil {return nil}
	return &owned.script_vm
}

@(export)
Kinemium_Render :: proc "c" (ctx: ^Context, dt: f32) {
	context = odin_runtime.default_context()
	owned := owned_context(ctx)
	if owned == nil || dt < 0 || dt > 1 {return}
	engine_runtime.Environment_Render_Step(&owned.environment, &owned.script_vm, dt)
}

@(export)
Kinemium_CreateInstance :: proc "c" (ctx: ^Context, class_name: cstring) -> rawptr {
	context = odin_runtime.default_context()
	owned := owned_context(ctx)
	if owned == nil || class_name == nil || owned.script_vm.L == nil {return nil}
	L := owned.script_vm.L
	if !vm.CheckStack(L, 16) {return nil}
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	object, ok := classes.Push_New(
		&owned.environment.classes,
		&owned.script_vm,
		string(class_name),
	)
	if !ok {return nil}
	return object
}

@(export)
Kinemium_SetParent :: proc "c" (instance: rawptr, parent: rawptr) {
	context = odin_runtime.default_context()
	if instance == nil {return}
	classes.Set_Parent(cast(^classes.Object)instance, cast(^classes.Object)parent)
}

@(export)
Kinemium_SetName :: proc "c" (instance: rawptr, name: cstring) {
	context = odin_runtime.default_context()
	if instance == nil || name == nil {return}
	classes.Set_Name(cast(^classes.Object)instance, string(name))
}

@(export)
Kinemium_IsA :: proc "c" (instance: rawptr, class_name: cstring) -> bool {
	context = odin_runtime.default_context()
	if instance == nil || class_name == nil {return false}
	return classes.Is_A(cast(^classes.Object)instance, string(class_name))
}

@(export)
Kinemium_GetParent :: proc "c" (instance: rawptr) -> rawptr {
	context = odin_runtime.default_context()
	if instance == nil {return nil}
	object := cast(^classes.Object)instance
	if object.destroyed {return nil}
	return classes.Get_Parent(object)
}

@(export)
Kinemium_FindChild :: proc "c" (instance: rawptr, name: cstring) -> rawptr {
	context = odin_runtime.default_context()
	if instance == nil || name == nil {return nil}
	object := cast(^classes.Object)instance
	if object.destroyed {return nil}
	return classes.Find_First_Child(object, string(name))
}

@(export)
Kinemium_GetChildCount :: proc "c" (instance: rawptr) -> u64 {
	context = odin_runtime.default_context()
	if instance == nil {return 0}
	object := cast(^classes.Object)instance
	if object.destroyed {return 0}
	return u64(len(classes.Get_Children(object)))
}

@(export)
Kinemium_GetChildAt :: proc "c" (instance: rawptr, index: u64) -> rawptr {
	context = odin_runtime.default_context()
	if instance == nil {return nil}
	object := cast(^classes.Object)instance
	if object.destroyed {return nil}
	children := classes.Get_Children(object)
	if index >= u64(len(children)) {return nil}
	return children[int(index)]
}

@(export)
Kinemium_GetNameLength :: proc "c" (instance: rawptr) -> u64 {
	context = odin_runtime.default_context()
	if instance == nil {return 0}
	object := cast(^classes.Object)instance
	if object.destroyed {return 0}
	return u64(len(classes.Get_Name(object)))
}

@(export)
Kinemium_CopyName :: proc "c" (instance: rawptr, buffer: [^]u8, capacity: u64) -> u64 {
	context = odin_runtime.default_context()
	if instance == nil {return 0}
	object := cast(^classes.Object)instance
	if object.destroyed {return 0}
	name := classes.Get_Name(object)
	if buffer != nil && capacity > 0 {
		count := min(u64(len(name)), capacity - 1)
		for i in 0 ..< int(count) {buffer[i] = name[i]}
		buffer[int(count)] = 0
	}
	return u64(len(name))
}
