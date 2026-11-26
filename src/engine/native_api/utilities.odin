package native_api

import debuglog "../debuglog"
import globals "../global"
import services "../services"
import odin_runtime "base:runtime"

@(export)
Kinemium_GetServiceCount :: proc "c" (ctx: ^Context) -> u64 {
	context = odin_runtime.default_context()
	if ctx == nil || !ctx.active || ctx.services == nil {return 0}
	return u64(len(ctx.services.services))
}

@(export)
Kinemium_CopyServiceName :: proc "c" (
	ctx: ^Context,
	index: u64,
	buffer: [^]u8,
	capacity: u64,
) -> i64 {
	context = odin_runtime.default_context()
	if ctx == nil ||
	   !ctx.active ||
	   ctx.services == nil ||
	   index >= u64(len(ctx.services.services)) {
		return -1
	}
	return sdk_copy_string(ctx.services.services[int(index)].name, buffer, capacity)
}

@(export)
Kinemium_ServiceExists :: proc "c" (ctx: ^Context, name: cstring) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || !ctx.active || ctx.services == nil || name == nil {return false}
	return services.Find_Service(ctx.services, string(name)) != nil
}

@(export)
Kinemium_Log :: proc "c" (ctx: ^Context, level: i32, message: cstring) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || !ctx.active || message == nil {return false}
	if level < 0 || level > 4 {return false}
	if level == 4 {
		debuglog.Log_Error(string(message))
	} else {
		debuglog.Log(string(message))
	}
	return true
}

@(export)
Kinemium_CopyEngineVersion :: proc "c" (buffer: [^]u8, capacity: u64) -> i64 {
	context = odin_runtime.default_context()
	return sdk_copy_string(globals.RUNTIME_VERSION_DISPLAY, buffer, capacity)
}
