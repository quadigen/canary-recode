package services

// wire:service

import classes "../classes"

MaterialService_Class := classes.Class_Info{
	name   = "MaterialService",
	parent = &Service_Class,
}

material_service_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	service := new(Service)
	service^ = Service_Init(&MaterialService_Class, "MaterialService", data_model)
	return &service.object
}

material_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^Service)object)
}

Register_MaterialService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry, &MaterialService_Class, material_service_construct, material_service_destroy,
		creatable = false,
	)
}
