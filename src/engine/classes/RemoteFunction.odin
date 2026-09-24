package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

RemoteFunction_Class := Class_Info {
	name   = "RemoteFunction",
	parent = &Instance_Class,
}

RemoteFunction :: struct {
	using object: Object,

	on_server_invoke: i32,
	on_client_invoke: i32,
}

REMOTE_FUNCTION_NO_HANDLER :: -1

RemoteFunction_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	remote_function := new(RemoteFunction)

	remote_function.object = Object_Init(&RemoteFunction_Class, "RemoteFunction")
	remote_function.on_server_invoke = REMOTE_FUNCTION_NO_HANDLER
	remote_function.on_client_invoke = REMOTE_FUNCTION_NO_HANDLER

	return &remote_function.object
}

RemoteFunction_release_handler :: proc(remote_function: ^RemoteFunction, which: ^i32) {
	if remote_function == nil || which == nil {
		return
	}
	if which^ != REMOTE_FUNCTION_NO_HANDLER &&
	   remote_function.signal_registry != nil &&
	   remote_function.signal_registry.vm_state != nil &&
	   remote_function.signal_registry.vm_state.L != nil {
		vm.ReleaseValue(remote_function.signal_registry.vm_state.L, which^)
		which^ = REMOTE_FUNCTION_NO_HANDLER
	}
}

RemoteFunction_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	remote_function := cast(^RemoteFunction)object

	if remote_function != nil {
		RemoteFunction_release_handler(remote_function, &remote_function.on_server_invoke)
		RemoteFunction_release_handler(remote_function, &remote_function.on_client_invoke)
	}

	Object_Destroy(object)
	free(remote_function)
}

RemoteFunction_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	remote_function := cast(^RemoteFunction)object

	switch key {
	case "OnServerInvoke":
		if remote_function.on_server_invoke == REMOTE_FUNCTION_NO_HANDLER {
			vm.PushNil(L)
		} else {
			vm.PushRegistryReference(L, remote_function.on_server_invoke)
		}
	case "OnClientInvoke":
		if remote_function.on_client_invoke == REMOTE_FUNCTION_NO_HANDLER {
			vm.PushNil(L)
		} else {
			vm.PushRegistryReference(L, remote_function.on_client_invoke)
		}
	case:
		return false
	}
	return true
}

RemoteFunction_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	remote_function := cast(^RemoteFunction)object

	handler: ^i32
	switch key {
	case "OnServerInvoke":
		handler = &remote_function.on_server_invoke
	case "OnClientInvoke":
		handler = &remote_function.on_client_invoke
	case:
		return false
	}

	if vm.TypeOf(L, value_index) == .Nil {
		RemoteFunction_release_handler(remote_function, handler)
		return true
	}
	if !vm.IsFunction(L, value_index) {
		return false
	}

	RemoteFunction_release_handler(remote_function, handler)
	vm.PushValue(L, value_index)
	handler^ = vm.RetainValue(L)
	vm.Pop(L)
	return true
}

RemoteFunction_Server_Handler :: proc(remote_function: ^RemoteFunction) -> i32 {
	if remote_function == nil {
		return REMOTE_FUNCTION_NO_HANDLER
	}
	return remote_function.on_server_invoke
}

RemoteFunction_Client_Handler :: proc(remote_function: ^RemoteFunction) -> i32 {
	if remote_function == nil {
		return REMOTE_FUNCTION_NO_HANDLER
	}
	return remote_function.on_client_invoke
}

Register_RemoteFunction :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&RemoteFunction_Class,
		RemoteFunction_construct,
		RemoteFunction_destroy,
		get = RemoteFunction_get,
		set = RemoteFunction_set,
	)
}