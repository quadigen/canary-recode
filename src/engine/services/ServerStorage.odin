package services

// wire:service global="ServerStorage"

import classes "../classes"

ServerStorage_Class := classes.Class_Info{
	name   = "ServerStorage",
	parent = &Service_Class,
}

ServerStorage :: struct {
	using service: Service,
}

server_storage_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(ServerStorage)
	service.service = Service_Init(
		&ServerStorage_Class,
		"ServerStorage",
		data_model,
	)
	return &service.object
}

server_storage_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	classes.Object_Destroy(object)
	free(cast(^ServerStorage)object)
}

Register_ServerStorage_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&ServerStorage_Class,
		server_storage_construct,
		server_storage_destroy,
		creatable = false,
	)
}
