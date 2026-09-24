package classes

import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

RemoteEvent_Class := Class_Info {
	name   = "RemoteEvent",
	parent = &Instance_Class,
}

RemoteEvent :: struct {
	using object: Object,

	on_server_event: ^signals.Signal,
	on_client_event: ^signals.Signal,
}

RemoteEvent_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	remote_event := new(RemoteEvent)

	remote_event.object = Object_Init(&RemoteEvent_Class, "RemoteEvent")

	return &remote_event.object
}

RemoteEvent_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	remote_event := cast(^RemoteEvent)object

	if remote_event != nil {
		if remote_event.on_server_event != nil {
			signals.Destroy(remote_event.on_server_event)
		}
		if remote_event.on_client_event != nil {
			signals.Destroy(remote_event.on_client_event)
		}
	}

	Object_Destroy(object)
	free(remote_event)
}

RemoteEvent_ensure_signals :: proc(remote_event: ^RemoteEvent) {
	if remote_event == nil ||
	   remote_event.signal_registry == nil ||
	   remote_event.signal_registry.signal_registry == nil {
		return
	}

	registry := remote_event.signal_registry.signal_registry

	if remote_event.on_server_event == nil {
		remote_event.on_server_event = signals.Create(registry)
	}
	if remote_event.on_client_event == nil {
		remote_event.on_client_event = signals.Create(registry)
	}
}

RemoteEvent_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	remote_event := cast(^RemoteEvent)object

	switch key {
	case "OnServerEvent":
		RemoteEvent_ensure_signals(remote_event)
		signals.Push(L, remote_event.on_server_event)
	case "OnClientEvent":
		RemoteEvent_ensure_signals(remote_event)
		signals.Push(L, remote_event.on_client_event)
	case:
		return false
	}
	return true
}

RemoteEvent_Server_Signal :: proc(remote_event: ^RemoteEvent) -> ^signals.Signal {
	RemoteEvent_ensure_signals(remote_event)
	return remote_event.on_server_event
}

RemoteEvent_Client_Signal :: proc(remote_event: ^RemoteEvent) -> ^signals.Signal {
	RemoteEvent_ensure_signals(remote_event)
	return remote_event.on_client_event
}

Register_RemoteEvent :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&RemoteEvent_Class,
		RemoteEvent_construct,
		RemoteEvent_destroy,
		get = RemoteEvent_get,
	)
}