package services

// wire:service global="ReplicatedFirst"

import classes "../classes"

ReplicatedFirst_Class := classes.Class_Info{
	name   = "ReplicatedFirst",
	parent = &Service_Class,
}

ReplicatedFirst :: struct {
	using service: Service,
}

replicated_first_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(ReplicatedFirst)
	service.service = Service_Init(
		&ReplicatedFirst_Class,
		"ReplicatedFirst",
		data_model,
	)
	return &service.object
}

replicated_first_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	classes.Object_Destroy(object)
	free(cast(^ReplicatedFirst)object)
}

Register_ReplicatedFirst_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&ReplicatedFirst_Class,
		replicated_first_construct,
		replicated_first_destroy,
		creatable = false,
	)
}
