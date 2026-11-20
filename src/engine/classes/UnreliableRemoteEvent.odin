package classes

UnreliableRemoteEvent_Class := Class_Info {
	name   = "UnreliableRemoteEvent",
	parent = &Instance_Class,
}

UnreliableRemoteEvent :: RemoteEvent

UnreliableRemoteEvent_construct :: proc(
	renderer: ^Renderer_Object,
	data_model: rawptr,
) -> ^Object {
	event := new(UnreliableRemoteEvent)
	event.object = Object_Init(&UnreliableRemoteEvent_Class, "UnreliableRemoteEvent")
	return &event.object
}

Register_UnreliableRemoteEvent :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&UnreliableRemoteEvent_Class,
		UnreliableRemoteEvent_construct,
		RemoteEvent_destroy,
		get = RemoteEvent_get,
		methods = []string{"FireServer", "FireClient", "FireAllClients"},
		events = []string{"OnServerEvent", "OnClientEvent"},
	)
}
