package native_api

import odin_runtime "base:runtime"

ABI_MAJOR :: u32(2)
ABI_MINOR :: u32(0)

Plugin_Load_Fn :: proc "c" (_: ^Context) -> bool
Plugin_Update_Fn :: proc "c" (_: ^Context, _: f64)
Plugin_Stop_Fn :: proc "c" (_: ^Context)

Plugin_Descriptor :: struct {
	size:      u32,
	abi_major: u32,
	abi_minor: u32,
	id:        cstring,
	name:      cstring,
	version:   cstring,
	on_load:   Plugin_Load_Fn,
	on_start:  Plugin_Load_Fn,
	on_update: Plugin_Update_Fn,
	on_stop:   Plugin_Stop_Fn,
	on_unload: Plugin_Stop_Fn,
}

Plugin_Entry_Fn :: proc "c" () -> ^Plugin_Descriptor

Plugin_Info :: struct {
	handle:    u64,
	active:    bool,
	api_major: u32,
	api_minor: u32,
}

Plugin_Manager_Hooks :: struct {
	load:   proc "c" (_: rawptr, _: cstring, _: ^u64) -> bool,
	unload: proc "c" (_: rawptr, _: u64) -> bool,
	reload: proc "c" (_: rawptr, _: u64) -> bool,
	count:  proc "c" (_: rawptr) -> u64,
	info:   proc "c" (_: rawptr, _: u64, _: ^Plugin_Info) -> bool,
}

Plugin_Manager_Set :: proc(ctx: ^Context, manager: rawptr, hooks: Plugin_Manager_Hooks) {
	if ctx == nil {return}
	ctx.plugin_manager = manager
	ctx.plugin_hooks = hooks
}

@(export)
Kinemium_GetABIMajor :: proc "c" () -> u32 {
	return ABI_MAJOR
}

@(export)
Kinemium_GetABIMinor :: proc "c" () -> u32 {
	return ABI_MINOR
}

@(export)
Kinemium_PluginLoad :: proc "c" (ctx: ^Context, path: cstring, output: ^u64) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil ||
	   !ctx.active ||
	   ctx.root == nil ||
	   !ctx.root.active ||
	   path == nil ||
	   output == nil {return false}
	if ctx.plugin_owner != nil {sdk_error(ctx, "plugins cannot load other plugins"); return false}
	root := ctx.root
	if root.plugin_hooks.load ==
	   nil {sdk_error(ctx, "plugin manager is unavailable"); return false}
	output^ = 0
	result := root.plugin_hooks.load(root.plugin_manager, path, output)
	if !result {
		if ctx != root && root.last_error != "" {sdk_error(ctx, root.last_error)}
		return false
	}
	sdk_clear_error(ctx)
	return true
}

@(export)
Kinemium_PluginUnload :: proc "c" (ctx: ^Context, plugin: u64) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil ||
	   !ctx.active ||
	   ctx.root == nil ||
	   !ctx.root.active ||
	   ctx.plugin_owner != nil {return false}
	if ctx.root.plugin_hooks.unload == nil {return false}
	result := ctx.root.plugin_hooks.unload(ctx.root.plugin_manager, plugin)
	if result {sdk_clear_error(ctx)}
	return result
}

@(export)
Kinemium_PluginReload :: proc "c" (ctx: ^Context, plugin: u64) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil ||
	   !ctx.active ||
	   ctx.root == nil ||
	   !ctx.root.active ||
	   ctx.plugin_owner != nil {return false}
	if ctx.root.plugin_hooks.reload == nil {return false}
	result := ctx.root.plugin_hooks.reload(ctx.root.plugin_manager, plugin)
	if result {sdk_clear_error(ctx)}
	return result
}

@(export)
Kinemium_PluginGetCount :: proc "c" (ctx: ^Context) -> u64 {
	context = odin_runtime.default_context()
	if ctx == nil || !ctx.active || ctx.root == nil || !ctx.root.active {return 0}
	if ctx.root.plugin_hooks.count == nil {return 0}
	return ctx.root.plugin_hooks.count(ctx.root.plugin_manager)
}

@(export)
Kinemium_PluginGetInfo :: proc "c" (ctx: ^Context, plugin: u64, output: ^Plugin_Info) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil ||
	   !ctx.active ||
	   ctx.root == nil ||
	   !ctx.root.active ||
	   output == nil {return false}
	if ctx.root.plugin_hooks.info == nil {return false}
	return ctx.root.plugin_hooks.info(ctx.root.plugin_manager, plugin, output)
}

SetError :: proc(ctx: ^Context, message: string) {
	sdk_error(ctx, message)
}

ClearError :: proc(ctx: ^Context) {
	sdk_clear_error(ctx)
}
