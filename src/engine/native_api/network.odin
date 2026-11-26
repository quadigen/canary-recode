package native_api

import classes "../classes"
import services "../services"
import vm "../vm"
import odin_runtime "base:runtime"

SDK_Network_Stats :: struct {
	connected:           bool,
	scene_ready:         bool,
	peers:               u32,
	replicated_entities: u32,
	packets_sent:        u64,
	packets_received:    u64,
	bytes_sent:          u64,
	bytes_received:      u64,
}

sdk_network_service :: proc(ctx: ^Context) -> ^classes.Object {
	if ctx == nil {return nil}
	return services.DataModel_Get_Service(ctx.services.data_model, "ReplicatorService")
}

sdk_network_load :: proc(ctx: ^Context, source: string) -> bool {
	L := ctx.script_vm.L
	ok, err := vm.LoadSource(ctx.script_vm, L, source, "Kinemium_NativeNetwork")
	if !ok {sdk_error(ctx, err)
		delete(err); return false}
	ok, err = vm.ProtectedCall(L, 0, 1)
	if !ok {sdk_error(ctx, err)
		delete(err); return false}
	return true
}

sdk_network_start :: proc(ctx: ^Context, host: string, port: u16, is_server: bool) -> bool {
	if ctx == nil || host == "" || port == 0 {return false}
	object := sdk_network_service(ctx)
	if object == nil {sdk_error(ctx, "ReplicatorService is unavailable"); return false}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	source := "return function(replicator,host,port) return replicator:ConnectClient(host,port) end"
	if is_server {source = "return function(replicator,host,port) return replicator:StartServer(host,port) end"}
	if !sdk_network_load(ctx, source) {return false}
	classes.Push_Object(L, object)
	vm.PushString(L, host)
	vm.PushNumber(L, f64(port))
	ok, err := vm.ProtectedCall(L, 3, 1)
	if !ok {sdk_error(ctx, err)
		delete(err); return false}
	if vm.IsNil(L, -1) {sdk_error(ctx, "network startup failed"); return false}
	sdk_clear_error(ctx)
	return true
}

@(export)
Kinemium_NetworkStartServer :: proc "c" (ctx: ^Context, host: cstring, port: u16) -> bool {
	context = odin_runtime.default_context()
	if host == nil {return false}
	return sdk_network_start(ctx, string(host), port, true)
}

@(export)
Kinemium_NetworkConnect :: proc "c" (ctx: ^Context, host: cstring, port: u16) -> bool {
	context = odin_runtime.default_context()
	if host == nil {return false}
	return sdk_network_start(ctx, string(host), port, false)
}

@(export)
Kinemium_NetworkStop :: proc "c" (ctx: ^Context) -> bool {
	context = odin_runtime.default_context()
	object := sdk_network_service(ctx)
	if object == nil {return false}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	if !sdk_network_load(
		ctx,
		"return function(replicator) replicator:Stop() return true end",
	) {return false}
	classes.Push_Object(L, object)
	ok, err := vm.ProtectedCall(L, 1, 1)
	if !ok {sdk_error(ctx, err)
		delete(err); return false}
	sdk_clear_error(ctx)
	return true
}

@(export)
Kinemium_NetworkSendStringEvent :: proc "c" (
	ctx: ^Context,
	name: cstring,
	payload: cstring,
	reliable: bool,
) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || name == nil || payload == nil {return false}
	object := sdk_network_service(ctx)
	if object == nil {return false}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	if !sdk_network_load(
		ctx,
		"return function(replicator,name,payload,reliable) return replicator:SendEvent(name,payload,reliable) end",
	) {return false}
	classes.Push_Object(L, object)
	vm.PushString(L, string(name))
	vm.PushString(L, string(payload))
	vm.PushBoolean(L, reliable)
	ok, err := vm.ProtectedCall(L, 4, 1)
	if !ok {sdk_error(ctx, err)
		delete(err); return false}
	if !vm.IsBoolean(L, -1) {sdk_error(ctx, "SendEvent did not return a boolean"); return false}
	result := vm.ArgBoolean(L, -1)
	if result {sdk_clear_error(ctx)}
	return result
}

@(export)
Kinemium_NetworkSetSendRate :: proc "c" (ctx: ^Context, bytes_per_second: u32) -> bool {
	context = odin_runtime.default_context()
	object := sdk_network_service(ctx)
	return sdk_property_set(ctx, object, "SendRate", .Number, number = f64(bytes_per_second))
}

@(export)
Kinemium_NetworkGetStats :: proc "c" (ctx: ^Context, output: ^SDK_Network_Stats) -> bool {
	context = odin_runtime.default_context()
	if ctx == nil || output == nil {return false}
	object := sdk_network_service(ctx)
	if object == nil {return false}
	service := cast(^services.ReplicatorService)object
	output^ = SDK_Network_Stats {
		connected           = service.connected,
		scene_ready         = service.scene_ready,
		peers               = u32(len(service.peers)),
		replicated_entities = u32(len(service.entity_list)),
		packets_sent        = service.packets_sent,
		packets_received    = service.packets_received,
		bytes_sent          = service.bytes_sent,
		bytes_received      = service.bytes_received,
	}
	return true
}
