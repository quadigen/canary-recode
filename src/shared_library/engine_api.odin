package shared_library
import native_api "../engine/native_api"
import engine_runtime "../engine/runtime"
import target "../engine/target"
import odin_runtime "base:runtime"

@(export)
Kinemium_CreateWithMode :: proc "c" (mode: i32) -> ^Context {
	context = odin_runtime.default_context()
	if mode < i32(target.Mode.Editor) || mode > i32(target.Mode.Singleplayer) {return nil}
	return create_owned(target.Mode(mode))
}

@(export)
Kinemium_GetMode :: proc "c" (ctx: ^Context) -> i32 {
	context = odin_runtime.default_context()
	if ctx == nil {return -1}
	return i32(ctx.mode)
}

@(export)
Kinemium_SetMode :: proc "c" (ctx: ^Context, mode: i32) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil ||
	   mode < i32(target.Mode.Editor) ||
	   mode > i32(target.Mode.Singleplayer) {return false}
	owned := owned_context(ctx)
	if owned == nil {return false}
	engine_runtime.Environment_Set_Mode(&owned.environment, target.Mode(mode))
	ctx.mode = target.Mode(mode)
	return true
}

@(export)
Kinemium_Tick :: proc "c" (ctx: ^Context, delta_seconds: f32) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || delta_seconds < 0 || delta_seconds > 1 {return false}
	owned := owned_context(ctx)
	if owned == nil {return false}
	engine_runtime.Environment_Update_Step(&owned.environment, ctx.script_vm, delta_seconds)
	engine_runtime.Environment_Render_Step(&owned.environment, ctx.script_vm, delta_seconds)
	return true
}
