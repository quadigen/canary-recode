package services

// object container, will be used by NetworkService

import "core:fmt"
// wire:service global="ReplicatedStorage"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import guilib "../gui"

ReplicatedStorage_Class := classes.Class_Info{name = "ReplicatedStorage", parent = &Service_Class}

ReplicatedStorage :: struct {
	using service: Service,
	call_count: i64,
}

ReplicatedStorage_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	service := new(ReplicatedStorage)
	service.service = Service_Init(&ReplicatedStorage_Class, "ReplicatedStorage", data_model)
	return &service.object
}


ReplicatedStorage_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^ReplicatedStorage)object)
}

Register_ReplicatedStorage_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(registry, &ReplicatedStorage_Class, ReplicatedStorage_construct, ReplicatedStorage_destroy, creatable = false)
}
