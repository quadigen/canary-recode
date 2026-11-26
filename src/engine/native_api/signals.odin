package native_api

import classes "../classes"
import signals "../signals"
import vm "../vm"
import odin_runtime "base:runtime"
import "core:strings"

Signal_Callback :: proc "c" (ctx: ^Context, user_data: rawptr, count: u32, args: [^]SDK_Value)

Native_Connection :: struct {
	owner:      ^Context,
	connection: ^signals.KinemiumConnection,
	callback:   Signal_Callback,
	user_data:  rawptr,
	handle:     u64,
	active:     bool,
}

next_native_connection_id: u64 = 1

find_native_connection :: proc(ctx: ^Context, handle: u64) -> ^Native_Connection {
	if ctx == nil || handle == 0 {return nil}
	root := ctx.root
	if root == nil {return nil}
	for conn in root.all_connections {
		if conn != nil && conn.handle == handle && conn.active {
			return conn
		}
	}
	return nil
}

native_signal_callback :: proc "c" (opaque: rawptr, L: ^vm.State) -> i32 {
	context = odin_runtime.default_context()
	c := cast(^Native_Connection)opaque
	if c == nil || !c.active || c.owner == nil || !c.owner.active || c.callback == nil {
		return 0
	}
	count := vm.StackTop(L)
	if count > 32 {return 0}
	arguments: [32]SDK_Value
	copies: [dynamic]cstring
	defer {
		for value in copies {delete(value)}
		delete(copies)
	}
	for i in 0 ..< count {
		index := i + 1
		value := &arguments[i]
		#partial switch vm.TypeOf(L, index) {
		case .Nil:
			value.kind = .Nil
		case .Boolean:
			value.kind = .Boolean
			value.boolean = vm.ArgBoolean(L, index)
		case .Number, .Integer:
			value.kind = .Number
			value.number = vm.ArgNumber(L, index)
		case .String:
			value.kind = .String
			text := strings.clone_to_cstring(vm.ArgString(L, index))
			append(&copies, text)
			value.text = text
			value.text_length = u64(len(string(text)))
		case .Vector:
			value.kind = .Vector3
			value.vector.x, value.vector.y, value.vector.z = vm.ArgVector3(L, index)
		case .Userdata:
			binding := vm.UserdataBindingOf(L, index)
			if binding != nil && binding.name == "Instance" {
				value.kind = .Instance
				value.instance = register_handle(
					c.owner,
					cast(^classes.Object)vm.UserdataValue(L, index),
				)
			} else {value.kind = .Other}
		case:
			value.kind = .Other
		}
	}
	c.callback(c.owner, c.user_data, u32(count), &arguments[0])
	return 0
}

native_signal_from_instance :: proc(
	ctx: ^Context,
	instance: ^classes.Object,
	name: string,
) -> ^signals.Signal {
	if ctx == nil ||
	   instance == nil ||
	   name == "" ||
	   instance.signal_registry == nil ||
	   instance.signal_registry.signal_registry == nil {
		return nil
	}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	vm.PushFunction(L, "NativeSignalLookup", sdk_getter)
	classes.Push_Object(L, instance)
	vm.PushString(L, name)
	ok, err := vm.ProtectedCall(L, 2, 1)
	if !ok {
		sdk_error(ctx, err)
		delete(err)
		return nil
	}
	registry := instance.signal_registry.signal_registry
	if !vm.IsUserdataType(L, -1, &registry.signal_binding) {return nil}
	return cast(^signals.Signal)vm.UserdataValue(L, -1)
}

@(export)
Kinemium_ConnectSignal :: proc "c" (
	ctx: ^Context,
	handle: u64,
	name: cstring,
	callback: Signal_Callback,
	user_data: rawptr,
	once: bool,
) -> u64 {
	context = odin_runtime.default_context()
	instance := resolve_handle(ctx, handle)
	if instance == nil || name == nil || callback == nil {return 0}
	signal := native_signal_from_instance(ctx, instance, string(name))
	if signal == nil {return 0}
	conn := new(Native_Connection)
	conn.owner = ctx
	conn.callback = callback
	conn.user_data = user_data
	conn.handle = next_native_connection_id
	next_native_connection_id += 1
	if next_native_connection_id == 0 {next_native_connection_id = 1}
	conn.connection = signals.Connect_Native(signal, native_signal_callback, conn, once)
	if conn.connection == nil {
		free(conn)
		return 0
	}
	conn.active = true
	append(&ctx.all_connections, conn)
	if ctx.root != ctx {
		append(&ctx.root.all_connections, conn)
	}
	return conn.handle
}

native_luau_signal_bridge :: proc "c" (
	ctx: ^Context,
	user_data: rawptr,
	count: u32,
	args: [^]SDK_Value,
) {
	callback_handle := u64(uintptr(user_data))
	if !Kinemium_LuauCallbackIsValid(ctx, callback_handle) {return}
	_ = Kinemium_CallLuauCallback(ctx, callback_handle, args, count, nil, nil, 0)
}

@(export)
Kinemium_ConnectLuauSignal :: proc "c" (
	ctx: ^Context,
	handle: u64,
	name: cstring,
	retained_callback: u64,
	once: bool,
) -> u64 {
	context = odin_runtime.default_context()
	if ctx == nil || !ctx.active || !Kinemium_LuauCallbackIsValid(ctx, retained_callback) {
		return 0
	}
	return Kinemium_ConnectSignal(
		ctx,
		handle,
		name,
		native_luau_signal_bridge,
		cast(rawptr)uintptr(retained_callback),
		once,
	)
}

@(export)
Kinemium_DisconnectSignal :: proc "c" (ctx: ^Context, handle: u64) -> bool {
	context = odin_runtime.default_context()
	conn := find_native_connection(ctx, handle)
	if conn == nil || (ctx != conn.owner && ctx != ctx.root) {return false}
	if conn.connection != nil {
		signals.Disconnect_Connection(conn.connection)
	}
	conn.active = false
	conn.callback = nil
	return true
}

@(export)
Kinemium_SignalConnected :: proc "c" (ctx: ^Context, handle: u64) -> bool {
	context = odin_runtime.default_context()
	conn := find_native_connection(ctx, handle)
	if conn == nil || conn.connection == nil {return false}
	return signals.Connection_Connected(conn.connection)
}

@(export)
Kinemium_FireSignal :: proc "c" (
	ctx: ^Context,
	handle: u64,
	name: cstring,
	args: [^]SDK_Value,
	count: u32,
) -> bool {
	context = odin_runtime.default_context()
	object := resolve_handle(ctx, handle)
	if ctx == nil || object == nil || name == nil || count > 32 || (count > 0 && args == nil) {
		return false
	}
	signal := native_signal_from_instance(ctx, object, string(name))
	if signal == nil {return false}
	L := ctx.script_vm.L
	top := vm.StackTop(L)
	defer vm.SetStackTop(L, top)
	for i in 0 ..< int(count) {
		if !sdk_push_value(ctx, args[i]) {return false}
	}
	signals.Fire(L, signal, int(count))
	return true
}

ClearOwnerConnections :: proc(ctx: ^Context) {
	if ctx == nil {return}
	for conn in ctx.all_connections {
		if conn == nil || conn.owner != ctx {continue}
		if conn.connection != nil {signals.Disconnect_Connection(conn.connection)}
		conn.active = false
		conn.callback = nil
		conn.owner = nil
	}
	if ctx.root == ctx {
		for conn in ctx.all_connections {
			if conn != nil {
				if conn.connection != nil {free(conn.connection)}
				free(conn)
			}
		}
	}
	delete(ctx.all_connections)
	ctx.all_connections = nil
}
