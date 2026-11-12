package services

// wire:service

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

VRService_Class := classes.Class_Info {
	name   = "VRService",
	parent = &Service_Class,
}

vr_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Service)
	service^ = Service_Init(&VRService_Class, "VRService", data_model)
	return &service.object
}

vr_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^Service)object)
}

vr_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	types: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	if key != "VREnabled" {return false}
	vm.PushBoolean(L, false)
	return true
}

Register_VRService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&VRService_Class,
		vr_service_construct,
		vr_service_destroy,
		creatable = false,
		get = vr_service_get,
		properties = []string{"VREnabled"},
	)
}
