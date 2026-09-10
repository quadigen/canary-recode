package services

// object container, will be used by ScriptContext

import "core:fmt"
// wire:service global="ServerScriptService"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import guilib "../gui"

ServerScriptService_Class := classes.Class_Info{name = "ServerScriptService", parent = &Service_Class}

ServerScriptService :: struct {
	using service: Service,
	call_count: i64,
}

ServerScriptService_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	service := new(ServerScriptService)
	service.service = Service_Init(&ServerScriptService_Class, "ServerScriptService", data_model)
	return &service.object
}


ServerScriptService_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^ServerScriptService)object)
}

Register_ServerScriptService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(registry, &ServerScriptService_Class, ServerScriptService_construct, ServerScriptService_destroy, creatable = false)
}

