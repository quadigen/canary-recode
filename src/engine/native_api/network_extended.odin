package native_api

import classes "../classes"
import services "../services"
import vm "../vm"
import odin_runtime "base:runtime"

SDK_Network_Diagnostics :: struct {
	mode:                 i32,
	handshake_complete:   bool,
	scene_ready:          bool,
	replication_finished: bool,
	protocol_version:     u32,
	handshake_status:     u32,
	handshake_rejections: u64,
	malformed_packets:    u64,
	rejected_packets:     u64,
	version_mismatches:   u64,
	schema_mismatches:    u64,
	auth_failures:        u64,
	bandwidth_drops:      u64,
	states_applied:       u64,
	tick:                 u32,
}

sdk_replicator :: proc(ctx: ^Context) -> (^services.ReplicatorService, ^classes.Object) {
	if ctx == nil || !ctx.active || ctx.services == nil {return nil, nil}
	object := sdk_network_service(ctx)
	if object == nil {return nil, nil}
	return cast(^services.ReplicatorService)object, object
}

sdk_network_setting_allowed :: proc(name: string) -> bool {
	switch name {
	case "SnapshotRate",
	     "BandwidthBudget",
	     "SendRate",
	     "InterpolationDelayTicks",
	     "TeleportThreshold",
	     "RelevancyDistance",
	     "LODNearFraction",
	     "LODFarInterval":
		return true
	}
	return false
}

@(export)
Kinemium_NetworkGetMode :: proc "c" (ctx: ^Context) -> i32 {
	context = odin_runtime.default_context()
	service, _ := sdk_replicator(ctx)
	if service == nil {return -1}
	return i32(service.mode)
}

@(export)
Kinemium_NetworkGetProtocolVersion :: proc "c" () -> u32 {
	context = odin_runtime.default_context()
	return services.Replication_Protocol_Version
}

@(export)
Kinemium_NetworkGetDiagnostics :: proc "c" (
	ctx: ^Context,
	output: ^SDK_Network_Diagnostics,
) -> bool {
	context = odin_runtime.default_context()
	service, _ := sdk_replicator(ctx)
	if service == nil || output == nil {return false}
	output^ = SDK_Network_Diagnostics {
		mode                 = i32(service.mode),
		handshake_complete   = service.handshake_complete,
		scene_ready          = service.scene_ready,
		replication_finished = service.replication_finished,
		protocol_version     = services.Replication_Protocol_Version,
		handshake_status     = u32(service.handshake_status),
		handshake_rejections = service.handshake_rejections,
		malformed_packets    = service.malformed_packets,
		rejected_packets     = service.rejected_packets,
		version_mismatches   = service.version_mismatches,
		schema_mismatches    = service.schema_mismatches,
		auth_failures        = service.auth_failures,
		bandwidth_drops      = service.bandwidth_drops,
		states_applied       = service.states_applied,
		tick                 = service.tick,
	}
	return true
}

@(export)
Kinemium_NetworkGetSetting :: proc "c" (ctx: ^Context, name: cstring, output: ^f64) -> bool {
	context = odin_runtime.default_context()
	if name == nil || output == nil || !sdk_network_setting_allowed(string(name)) {return false}
	service, object := sdk_replicator(ctx)
	if service == nil {return false}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	if !sdk_property_get(ctx, object, string(name)) {return false}
	value, ok := vm.ToNumber(L, -1)
	if !ok {return false}
	output^ = value
	sdk_clear_error(ctx)
	return true
}

@(export)
Kinemium_NetworkSetSetting :: proc "c" (ctx: ^Context, name: cstring, value: f64) -> bool {
	context = odin_runtime.default_context()
	if name == nil || !sdk_network_setting_allowed(string(name)) {return false}
	service, object := sdk_replicator(ctx)
	if service == nil {return false}
	return sdk_property_set(ctx, object, string(name), .Number, number = value)
}

@(export)
Kinemium_NetworkGetPeerCount :: proc "c" (ctx: ^Context) -> u64 {
	context = odin_runtime.default_context()
	service, _ := sdk_replicator(ctx)
	if service == nil || service.mode != .Server {return 0}
	return u64(len(service.peers))
}

@(export)
Kinemium_NetworkGetPeerPlayer :: proc "c" (ctx: ^Context, index: u64) -> u64 {
	context = odin_runtime.default_context()
	service, _ := sdk_replicator(ctx)
	if service == nil || service.mode != .Server || index >= u64(len(service.peers)) {return 0}
	player := service.peers[int(index)].player
	if player == nil {return 0}
	return register_handle(ctx, &player.object)
}

@(export)
Kinemium_NetworkGetPeerUserId :: proc "c" (ctx: ^Context, index: u64, output: ^u32) -> bool {
	context = odin_runtime.default_context()
	service, _ := sdk_replicator(ctx)
	if service == nil ||
	   output == nil ||
	   service.mode != .Server ||
	   index >= u64(len(service.peers)) {return false}
	player := service.peers[int(index)].player
	if player == nil {return false}
	output^ = player.user_id
	return true
}

@(export)
Kinemium_NetworkConnectEvent :: proc "c" (
	ctx: ^Context,
	callback: Signal_Callback,
	user_data: rawptr,
	once: bool,
) -> u64 {
	context = odin_runtime.default_context()
	if callback == nil {return 0}
	_, object := sdk_replicator(ctx)
	if object == nil {return 0}
	return Kinemium_ConnectSignal(
		ctx,
		register_handle(ctx, object),
		"EventReceived",
		callback,
		user_data,
		once,
	)
}

@(export)
Kinemium_NetworkSetClientEventAllowed :: proc "c" (
	ctx: ^Context,
	name: cstring,
	allowed: bool,
) -> bool {
	context = odin_runtime.default_context()
	service, object := sdk_replicator(ctx)
	if service == nil ||
	   service.mode != .Server ||
	   name == nil ||
	   len(string(name)) == 0 ||
	   len(string(name)) > 256 {return false}
	arguments := [2]SDK_Value{{kind = .String, text = name}, {kind = .Boolean, boolean = allowed}}
	return Kinemium_Invoke(
		ctx,
		register_handle(ctx, object),
		"SetClientEventAllowed",
		&arguments[0],
		2,
		nil,
		nil,
		0,
	)
}

@(export)
Kinemium_NetworkSendStringEventTo :: proc "c" (
	ctx: ^Context,
	player_handle: u64,
	name, payload: cstring,
	reliable: bool,
) -> bool {
	context = odin_runtime.default_context()
	service, object := sdk_replicator(ctx)
	player := resolve_handle(ctx, player_handle)
	if service == nil ||
	   service.mode != .Server ||
	   player == nil ||
	   !classes.Is_A(player, "Player") ||
	   name == nil ||
	   payload == nil ||
	   len(string(name)) == 0 ||
	   len(string(name)) > 256 {return false}
	arguments := [4]SDK_Value {
		{kind = .Instance, instance = player_handle},
		{kind = .String, text = name},
		{kind = .String, text = payload},
		{kind = .Boolean, boolean = reliable},
	}
	result: SDK_Value
	if !Kinemium_Invoke(
		ctx,
		register_handle(ctx, object),
		"SendEventTo",
		&arguments[0],
		4,
		&result,
		nil,
		0,
	) {return false}
	return result.kind == .Boolean && result.boolean
}

@(export)
Kinemium_NetworkRegisterInstance :: proc "c" (
	ctx: ^Context,
	instance_handle: u64,
	output: ^u32,
) -> bool {
	context = odin_runtime.default_context()
	service, object := sdk_replicator(ctx)
	instance := resolve_handle(ctx, instance_handle)
	if service == nil || service.mode != .Server || instance == nil || output == nil {return false}
	input := SDK_Value {
		kind     = .Instance,
		instance = instance_handle,
	}
	result: SDK_Value
	if !Kinemium_Invoke(
		ctx,
		register_handle(ctx, object),
		"Register",
		&input,
		1,
		&result,
		nil,
		0,
	) {return false}
	if result.kind != .Number || result.number <= 0 || result.number > 4294967295 {return false}
	output^ = u32(result.number)
	return true
}

@(export)
Kinemium_NetworkGetInstanceId :: proc "c" (ctx: ^Context, instance_handle: u64) -> u32 {
	context = odin_runtime.default_context()
	service, _ := sdk_replicator(ctx)
	instance := resolve_handle(ctx, instance_handle)
	if service == nil || instance == nil {return 0}
	id, exists := service.entity_ids[instance]
	if !exists {return 0}
	return id
}

@(export)
Kinemium_NetworkUnregisterInstance :: proc "c" (ctx: ^Context, instance_handle: u64) -> bool {
	context = odin_runtime.default_context()
	service, object := sdk_replicator(ctx)
	instance := resolve_handle(ctx, instance_handle)
	if service == nil ||
	   service.mode != .Server ||
	   instance == nil ||
	   Kinemium_NetworkGetInstanceId(ctx, instance_handle) == 0 {return false}
	input := SDK_Value {
		kind     = .Instance,
		instance = instance_handle,
	}
	return Kinemium_Invoke(ctx, register_handle(ctx, object), "Unregister", &input, 1, nil, nil, 0)
}

@(export)
Kinemium_NetworkSetRequireJoinToken :: proc "c" (ctx: ^Context, required: bool) -> bool {
	context = odin_runtime.default_context()
	service, _ := sdk_replicator(ctx)
	if service == nil || ctx.mode == .Client || service.mode == .Client {return false}
	value := SDK_Value {
		kind    = .Boolean,
		boolean = required,
	}
	return Kinemium_ServiceSetProperty(ctx, "ReplicatorService", "RequireJoinToken", &value)
}

@(export)
Kinemium_NetworkSetJoinToken :: proc "c" (ctx: ^Context, token: cstring) -> bool {
	context = odin_runtime.default_context()
	service, object := sdk_replicator(ctx)
	if service == nil ||
	   ctx.mode == .Client ||
	   service.mode == .Client ||
	   token == nil ||
	   len(string(token)) > 256 {return false}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	if !sdk_network_load(
		ctx,
		"return function(replicator,token) return replicator:SetJoinToken(token) end",
	) {return false}
	classes.Push_Object(L, object)
	vm.PushString(L, string(token))
	ok, err := vm.ProtectedCall(L, 2, 1)
	if !ok {
		sdk_error(ctx, err)
		delete(err)
		return false
	}
	result := vm.IsBoolean(L, -1) && vm.ArgBoolean(L, -1)
	if result {sdk_clear_error(ctx)}
	return result
}
