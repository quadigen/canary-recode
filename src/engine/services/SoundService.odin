package services

import "core:fmt"
// wire:service global="SoundService"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import guilib "../gui"
import kineffi "../bindings"
import audio "../audio"

SoundService_Class := classes.Class_Info{name = "SoundService", parent = &Service_Class}

SoundService :: struct {
	using service: Service,
	call_count: i64,
}

SoundService_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	service := new(SoundService)
	service.service = Service_Init(&SoundService_Class, "SoundService", data_model)

    // TODO: implement audio

	return &service.object
}

SoundService_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^SoundService)object)
}

Register_SoundService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(registry, &SoundService_Class, SoundService_construct, SoundService_destroy, creatable = false)
}

