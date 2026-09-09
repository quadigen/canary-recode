package signals

import "base:runtime"
import "core:fmt"
import vm "../vm"

SIGNAL_TAG     :: 49
CONNECTION_TAG :: 50

Listener :: struct {
	id:           u64,
	callback_ref: i32,
	connected:    bool,
	once:         bool,
}

Waiter :: struct {
	thread:     ^vm.State,
	thread_ref: i32,
}

Signal :: struct {
	registry:  ^Registry,
	listeners: [dynamic]Listener,
	waiters:   [dynamic]Waiter,
	next_id:   u64,
	destroyed: bool,
}

KinemiumConnection :: struct {
	registry:   ^Registry,
	signal:     ^Signal,
	listener_id: u64,
	signal_ref: i32,
}

Registry :: struct {
	L:                  ^vm.State,
	signal_binding:     vm.Userdata_Binding,
	connection_binding: vm.Userdata_Binding,
}

find_listener :: proc(signal: ^Signal, id: u64) -> ^Listener {
	if signal == nil { return nil }
	for listener, index in signal.listeners {
		if listener.id == id { return &signal.listeners[index] }
	}
	return nil
}

disconnect_listener :: proc(signal: ^Signal, id: u64) {
	listener := find_listener(signal, id)
	if listener == nil || !listener.connected { return }
	listener.connected = false
	if signal.registry != nil && signal.registry.L != nil {
		vm.ReleaseValue(signal.registry.L, listener.callback_ref)
	}
	listener.callback_ref = -1
}

connection_disconnect :: proc(connection: ^KinemiumConnection) {
	if connection == nil { return }
	if connection.signal != nil {
		disconnect_listener(connection.signal, connection.listener_id)
	}
	if connection.registry != nil && connection.registry.L != nil {
		vm.ReleaseValue(connection.registry.L, connection.signal_ref)
	}
	connection.signal = nil
	connection.signal_ref = -1
}

connection_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	connection := cast(^KinemiumConnection)value
	switch key {
	case "Connected":
		listener := find_listener(connection.signal, connection.listener_id)
		vm.PushBoolean(L, listener != nil && listener.connected)
	case "Disconnect": vm.PushUserdataMethod(L, key)
	case: return false
	}
	return true
}

connection_namecall :: proc(L: ^vm.State, value, ctx: rawptr, method: string) -> (i32, bool) {
	if method != "Disconnect" { return 0, false }
	connection_disconnect(cast(^KinemiumConnection)value)
	return 0, true
}

connection_destroy :: proc(value, ctx: rawptr) {
	connection := cast(^KinemiumConnection)value
	connection_disconnect(connection)
	free(connection)
}

connection_string :: proc(value, ctx: rawptr) -> string {
	return "KinemiumConnection"
}

signal_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	switch key {
	case "Connect", "Once", "Wait", "Fire", "DisconnectAll": vm.PushUserdataMethod(L, key)
	case: return false
	}
	return true
}

signal_connect :: proc(L: ^vm.State, signal: ^Signal, once: bool) -> i32 {
	if signal == nil || signal.destroyed { return vm.RaiseError(L, "Signal is destroyed") }
	if !vm.IsFunction(L, 2) { return vm.RaiseError(L, "Connect expects a function") }
	vm.PushValue(L, 2)
	callback_ref := vm.RetainValue(L)
	vm.Pop(L)
	signal.next_id += 1
	append(&signal.listeners, Listener{
		id = signal.next_id,
		callback_ref = callback_ref,
		connected = true,
		once = once,
	})

	connection := new(KinemiumConnection)
	connection^ = KinemiumConnection{
		registry = signal.registry,
		signal = signal,
		listener_id = signal.next_id,
	}
	vm.PushValue(L, 1)
	connection.signal_ref = vm.RetainValue(L)
	vm.Pop(L)
	vm.PushUserdata(&vm.VM{L = L}, connection, &signal.registry.connection_binding)
	return 1
}

fire_callback :: proc(signal: ^Signal, L: ^vm.State, callback_ref: i32, argument_top: int) {
	vm.PushRegistryReference(L, callback_ref)
	callback_index := vm.StackTop(L)
	thread := vm.NewThread(L)
	vm.CopyValueToThread(L, thread, callback_index)
	for index := 2; index <= argument_top; index += 1 {
		vm.CopyValueToThread(L, thread, index)
	}
	thread_ref := vm.RetainValue(L)
	vm.Pop(L, 2)
	_, _, err := vm.ResumeThread(thread, signal.registry.L, argument_top-1)
	vm.ReleaseValue(signal.registry.L, thread_ref)
	if err != "" {
		fmt.eprintf("Signal callback failed: %s\n", err)
		delete(err)
	}
}

signal_fire :: proc(L: ^vm.State, signal: ^Signal) {
	argument_top := vm.StackTop(L)
	callback_refs: [dynamic]i32
	for listener in signal.listeners {
		if !listener.connected { continue }
		vm.PushRegistryReference(L, listener.callback_ref)
		append(&callback_refs, vm.RetainValue(L))
		vm.Pop(L)
		if listener.once { disconnect_listener(signal, listener.id) }
	}

	waiters := signal.waiters
	signal.waiters = nil
	for waiter in waiters {
		for index := 2; index <= argument_top; index += 1 {
			vm.CopyValueToThread(L, waiter.thread, index)
		}
		_, _, err := vm.ResumeThread(waiter.thread, signal.registry.L, argument_top-1)
		vm.ReleaseValue(signal.registry.L, waiter.thread_ref)
		if err != "" {
			fmt.eprintf("Signal waiter failed: %s\n", err)
			delete(err)
		}
	}
	delete(waiters)

	for callback_ref in callback_refs {
		fire_callback(signal, L, callback_ref, argument_top)
		vm.ReleaseValue(signal.registry.L, callback_ref)
	}
	delete(callback_refs)
}

signal_namecall :: proc(L: ^vm.State, value, ctx: rawptr, method: string) -> (i32, bool) {
	context = runtime.default_context()
	signal := cast(^Signal)value
	switch method {
	case "Connect": return signal_connect(L, signal, false), true
	case "Once": return signal_connect(L, signal, true), true
	case "Wait":
		if !vm.IsYieldable(L) { return vm.RaiseError(L, "Signal:Wait must be called from a coroutine"), true }
		vm.PushCurrentThread(L)
		thread_ref := vm.RetainValue(L)
		vm.Pop(L)
		append(&signal.waiters, Waiter{thread = L, thread_ref = thread_ref})
		return vm.YieldThread(L), true
	case "Fire":
		signal_fire(L, signal)
		return 0, true
	case "DisconnectAll":
		for listener in signal.listeners { disconnect_listener(signal, listener.id) }
		return 0, true
	}
	return 0, false
}

signal_destroy :: proc(value, ctx: rawptr) {
	signal := cast(^Signal)value
	signal.destroyed = true
	for listener in signal.listeners { disconnect_listener(signal, listener.id) }
	if signal.registry != nil && signal.registry.L != nil {
		for waiter in signal.waiters { vm.ReleaseValue(signal.registry.L, waiter.thread_ref) }
	}
	delete(signal.listeners)
	delete(signal.waiters)
	free(signal)
}

signal_string :: proc(value, ctx: rawptr) -> string {
	return "Signal"
}

signal_new :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	registry := cast(^Registry)vm.UpvaluePointer(L)
	signal := new(Signal)
	signal.registry = registry
	vm.PushUserdata(&vm.VM{L = L}, signal, &registry.signal_binding)
	return 1
}

Registry_Init :: proc(registry: ^Registry) {
	registry.signal_binding = vm.Userdata_Binding{
		name = "KinemiumSignal",
		tag = SIGNAL_TAG,
		ctx = registry,
		get = signal_get,
		namecall = signal_namecall,
		string = signal_string,
		destroy = signal_destroy,
	}
	registry.connection_binding = vm.Userdata_Binding{
		name = "KinemiumConnection",
		tag = CONNECTION_TAG,
		ctx = registry,
		get = connection_get,
		namecall = connection_namecall,
		string = connection_string,
		destroy = connection_destroy,
	}
}

Install :: proc(registry: ^Registry, vm_state: ^vm.VM) {
	registry.L = vm_state.L
	vm.NewTable(vm_state.L, 0, 1)
	vm.PushLightUserdata(vm_state.L, registry)
	vm.PushFunction(vm_state.L, "Signal.new", signal_new, 1)
	vm.SetField(vm_state.L, -2, "new")
	vm.SetReadOnly(vm_state.L, -1)
	vm.PushValue(vm_state.L, -1)
	vm.SetGlobalFromStack(vm_state, "KinemiumSignal")
	vm.SetGlobalFromStack(vm_state, "Signal")
}

Registry_Destroy :: proc(registry: ^Registry) {
	if registry == nil { return }
	registry.L = nil
}
