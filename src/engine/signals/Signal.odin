package signals

import "base:runtime"
import "core:fmt"
import datatypes "../datatypes"
import vm "../vm"

SIGNAL_TAG     :: 49
CONNECTION_TAG :: 50

Listener :: struct {
	id:           u64,
	callback_ref: i32,
	connected:    bool,
	once:         bool,
	capabilities: vm.Thread_Security_Capabilities,
}

Waiter :: struct {
	thread:       ^vm.State,
	thread_ref:   i32,
	capabilities: vm.Thread_Security_Capabilities,
}

Pending_Callback :: struct {
	callback_ref: i32,
	capabilities: vm.Thread_Security_Capabilities,
}

Signal :: struct {
	registry:       ^Registry,
	listeners:      [dynamic]Listener,
	waiters:        [dynamic]Waiter,
	next_id:        u64,
	destroyed:      bool,
	external_owner: bool,
}

KinemiumConnection :: struct {
	registry:    ^Registry,
	signal:      ^Signal,
	listener_id: u64,
	signal_ref:  i32,
}

Registry :: struct {
	L:                  ^vm.State,
	signal_binding:     vm.Userdata_Binding,
	connection_binding: vm.Userdata_Binding,
	free_signals:       [dynamic]^Signal,
}

signal_has_internal_fire_capability :: proc(L: ^vm.State) -> bool {
	return vm.ThreadHasSecurityCapability(L, datatypes.SECURITY_CAPABILITY_INTERNAL_SIGNAL_FIRE)
}

find_listener :: proc(signal: ^Signal, id: u64) -> ^Listener {
	if signal == nil { return nil }
	for listener, index in signal.listeners {
		if listener.id == id { return &signal.listeners[index] }
	}
	return nil
}

disconnect_listener :: proc(signal: ^Signal, id: u64) {
	if signal == nil { return }
	for listener, index in signal.listeners {
		if listener.id == id && listener.connected {
			if signal.registry != nil && signal.registry.L != nil {
				vm.ReleaseValue(signal.registry.L, listener.callback_ref)
			}
			ordered_remove(&signal.listeners, index)
			return
		}
	}
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

connection_namecall :: proc(
    L: ^vm.State,
    value,
    ctx: rawptr,
    method: string,
) -> (i32, bool) {
    if method != "Disconnect" {
        return 0, false
    }

    connection_disconnect(cast(^KinemiumConnection)value)
    return 0, true
}

connection_destroy :: proc(value, ctx: rawptr) {
    connection := cast(^KinemiumConnection)value

    free(connection)
}

connection_string :: proc(value, ctx: rawptr) -> string {
	return "KinemiumConnection"
}

signal_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	switch key {
	case "Connect", "Once", "Wait":
		vm.PushUserdataMethod(L, key)
	case "Fire", "DisconnectAll":
		if !signal_has_internal_fire_capability(L) {
			return false
		}
		vm.PushUserdataMethod(L, key)
	case:
		return false
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
		id           = signal.next_id,
		callback_ref = callback_ref,
		connected    = true,
		once         = once,
		capabilities = vm.GetThreadSecurityCapabilities(L),
	})

	connection := new(KinemiumConnection)
	connection^ = KinemiumConnection{
		registry    = signal.registry,
		signal      = signal,
		listener_id = signal.next_id,
	}
	vm.PushValue(L, 1)
	connection.signal_ref = vm.RetainValue(L)
	vm.Pop(L)
	vm.PushUserdata(&vm.VM{L = L}, connection, &signal.registry.connection_binding)
	return 1
}

fire_callback :: proc(
	signal: ^Signal,
	L: ^vm.State,
	callback_ref: i32,
	capabilities: vm.Thread_Security_Capabilities,
	first_argument: int,
	argument_count: int,
) {
	vm.PushRegistryReference(L, callback_ref)
	callback_index := vm.StackTop(L)
	thread := vm.NewThread(L)
	vm.SetThreadSecurityCapabilities(thread, capabilities)
	vm.CopyValueToThread(L, thread, callback_index)
	for offset := 0; offset < argument_count; offset += 1 {
		vm.CopyValueToThread(L, thread, first_argument+offset)
	}
	thread_ref := vm.RetainValue(L)
	vm.Pop(L, 2)
	_, _, err := vm.ResumeThread(thread, signal.registry.L, argument_count)
	vm.ReleaseValue(signal.registry.L, thread_ref)
	if err != "" {
		fmt.eprintf("Signal callback failed: %s\n", err)
		delete(err)
	}
}

signal_fire_arguments :: proc(
	L: ^vm.State,
	signal: ^Signal,
	first_argument: int,
	argument_count: int,
) {
	if signal == nil || signal.destroyed || signal.registry == nil || signal.registry.L == nil {
		return
	}
	if argument_count < 0 {
		return
	}

	callbacks: [dynamic]Pending_Callback
	for listener in signal.listeners {
		if !listener.connected { continue }
		vm.PushRegistryReference(L, listener.callback_ref)
		append(&callbacks, Pending_Callback{
			callback_ref = vm.RetainValue(L),
			capabilities = listener.capabilities,
		})
		vm.Pop(L)
	}

	// Disconnect "once" listeners after the snapshot so the removal cannot
	// invalidate the iteration above.
	for index := len(signal.listeners) - 1; index >= 0; index -= 1 {
		if signal.listeners[index].once {
			disconnect_listener(signal, signal.listeners[index].id)
		}
	}

	waiters := signal.waiters
	signal.waiters = nil
	for waiter in waiters {
		for offset := 0; offset < argument_count; offset += 1 {
			vm.CopyValueToThread(L, waiter.thread, first_argument+offset)
		}
		vm.SetThreadSecurityCapabilities(waiter.thread, waiter.capabilities)
		_, _, err := vm.ResumeThread(waiter.thread, signal.registry.L, argument_count)
		vm.ReleaseValue(signal.registry.L, waiter.thread_ref)
		if err != "" {
			fmt.eprintf("Signal waiter failed: %s\n", err)
			delete(err)
		}
	}
	delete(waiters)

	for callback in callbacks {
		fire_callback(
			signal,
			L,
			callback.callback_ref,
			callback.capabilities,
			first_argument,
			argument_count,
		)
		vm.ReleaseValue(signal.registry.L, callback.callback_ref)
	}
	delete(callbacks)
}

// Engine/native firing path. This bypasses the Luau-facing capability gate,
// but callbacks still run with the capabilities they had when they connected.
Signal_Fire :: proc(L: ^vm.State, signal: ^Signal) {
	signal_fire_arguments(L, signal, 0, 0)
}

Signal_Fire_Arguments :: proc(
	L: ^vm.State,
	signal: ^Signal,
	first_argument: int,
	argument_count: int,
) {
	signal_fire_arguments(L, signal, first_argument, argument_count)
}

signal_namecall :: proc(L: ^vm.State, value, ctx: rawptr, method: string) -> (i32, bool) {
	context = runtime.default_context()
	signal := cast(^Signal)value
	switch method {
	case "Connect":
		return signal_connect(L, signal, false), true
	case "Once":
		return signal_connect(L, signal, true), true
	case "Wait":
		if !vm.IsYieldable(L) { return vm.RaiseError(L, "Signal:Wait must be called from a coroutine"), true }
		vm.PushCurrentThread(L)
		thread_ref := vm.RetainValue(L)
		vm.Pop(L)
		append(&signal.waiters, Waiter{
			thread       = L,
			thread_ref   = thread_ref,
			capabilities = vm.GetThreadSecurityCapabilities(L),
		})
		return vm.YieldThread(L), true
	case "Fire":
		if !signal_has_internal_fire_capability(L) {
			return vm.RaiseError(L, "Signal:Fire is restricted to internal scripts"), true
		}
		argument_count := max(vm.StackTop(L)-1, 0)
		signal_fire_arguments(L, signal, 2, argument_count)
		return 0, true
	case "DisconnectAll":
		if !signal_has_internal_fire_capability(L) {
			return vm.RaiseError(L, "Signal:DisconnectAll is restricted to internal scripts"), true
		}
		for index := len(signal.listeners) - 1; index >= 0; index -= 1 {
			disconnect_listener(signal, signal.listeners[index].id)
		}
		return 0, true
	}
	return 0, false
}

signal_destroy :: proc(value, ctx: rawptr) {
	signal := cast(^Signal)value
	if signal.external_owner {
		return
	}
	signal.destroyed = true
	for index := len(signal.listeners) - 1; index >= 0; index -= 1 {
		disconnect_listener(signal, signal.listeners[index].id)
	}
	if signal.registry != nil && signal.registry.L != nil {
		for waiter in signal.waiters { vm.ReleaseValue(signal.registry.L, waiter.thread_ref) }
	}
	delete(signal.listeners)
	delete(signal.waiters)
	free(signal)
}

// Destroy tears down a signal. External signals are returned to the registry
// pool instead of freed so connections may still reference the struct.
Destroy :: proc(signal: ^Signal) {
	if signal == nil || signal.destroyed {
		return
	}
	signal.destroyed = true
	for index := len(signal.listeners) - 1; index >= 0; index -= 1 {
		disconnect_listener(signal, signal.listeners[index].id)
	}
	if signal.registry != nil && signal.registry.L != nil {
		for waiter in signal.waiters { vm.ReleaseValue(signal.registry.L, waiter.thread_ref) }
	}
	delete(signal.listeners)
	delete(signal.waiters)
	if signal.external_owner && signal.registry != nil {
		append(&signal.registry.free_signals, signal)
	}
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

Create :: proc(registry: ^Registry, _ignored: ..any) -> ^Signal {
	if registry == nil { return nil }
	signal: ^Signal
	if len(registry.free_signals) > 0 {
		signal = pop(&registry.free_signals)
		// Preserve next_id so stale connections holding old listener ids
		// can never match listeners created after the signal is reused.
		next_id := signal.next_id
		signal^ = Signal{}
		signal.next_id = next_id
	} else {
		signal = new(Signal)
	}
	signal.registry = registry
	signal.external_owner = true
	return signal
}

Push :: proc(L: ^vm.State, signal: ^Signal) {
	if signal == nil || signal.destroyed || signal.registry == nil {
		vm.PushNil(L)
		return
	}
	vm.PushUserdata(&vm.VM{L = L}, signal, &signal.registry.signal_binding)
}

Fire :: proc(L: ^vm.State, signal: ^Signal, argument_count: int = 0) {
	if signal == nil || signal.destroyed { return }
	if argument_count <= 0 {
		Signal_Fire(L, signal)
		return
	}
	top := vm.StackTop(L)
	if argument_count > top { return }
	Signal_Fire_Arguments(L, signal, top-argument_count+1, argument_count)
}

Registry_Init :: proc(registry: ^Registry) {
	registry.signal_binding = vm.Userdata_Binding{
		name     = "KinemiumSignal",
		tag      = SIGNAL_TAG,
		ctx      = registry,
		get      = signal_get,
		namecall = signal_namecall,
		string   = signal_string,
		destroy  = signal_destroy,
	}
	registry.connection_binding = vm.Userdata_Binding{
		name     = "KinemiumConnection",
		tag      = CONNECTION_TAG,
		ctx      = registry,
		get      = connection_get,
		namecall = connection_namecall,
		string   = connection_string,
		destroy  = connection_destroy,
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
	for signal in registry.free_signals { free(signal) }
	delete(registry.free_signals)
	registry.free_signals = nil
	registry.L = nil
}
