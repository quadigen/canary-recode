package services

// wire:service global="StarterPack"

import classes "../classes"

StarterPack_Class := classes.Class_Info{
	name   = "StarterPack",
	parent = &Service_Class,
}

StarterPack :: struct {
	using service: Service,
}

starter_pack_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(StarterPack)
	service.service = Service_Init(
		&StarterPack_Class,
		"StarterPack",
		data_model,
	)
	return &service.object
}

starter_pack_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	classes.Object_Destroy(object)
	free(cast(^StarterPack)object)
}

Register_StarterPack_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&StarterPack_Class,
		starter_pack_construct,
		starter_pack_destroy,
		creatable = false,
	)
}
