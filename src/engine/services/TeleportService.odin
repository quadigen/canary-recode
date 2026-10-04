package services

// wire:service global="teleportService"

import "core:strings"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

TeleportService_Class := classes.Class_Info{
	name   = "TeleportService",
	parent = &Service_Class,
}

TeleportService :: struct {
	using service: Service,
}

teleport_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(TeleportService)
	service.service = Service_Init(
		&TeleportService_Class,
		"TeleportService",
		data_model,
	)
	return &service.object
}

teleport_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "TeleportAsync", "Teleport", "TeleportToPlaceInstance", "SetTeleportGui":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

teleport_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	switch method {
	case "TeleportAsync", "Teleport", "TeleportToPlaceInstance":
		return 0, true
	case "SetTeleportGui":
		vm.PushNil(L)
		return 1, true
	}
	return 0, false
}

teleport_service_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	classes.Object_Destroy(object)
	free(cast(^TeleportService)object)
}

Register_TeleportService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&TeleportService_Class,
		teleport_service_construct,
		teleport_service_destroy,
		creatable = false,
		get       = teleport_service_get,
		namecall  = teleport_service_namecall,
	)
}