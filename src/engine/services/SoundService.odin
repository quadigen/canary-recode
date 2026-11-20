package services

import "core:fmt"
// wire:service global="SoundService"

import audio "../audio"
import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import guilib "../gui"
import vm "../vm"


SoundService_Class := classes.Class_Info {
	name   = "SoundService",
	parent = &Service_Class,
}

SoundService :: struct {
	using service: Service,
	call_count:    i64,
}

SoundService_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(SoundService)
	service.service = Service_Init(&SoundService_Class, "SoundService", data_model)

	return &service.object
}

sound_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
) -> bool {
	if key != "PlayLocalSound" {return false}
	vm.PushUserdataMethod(L, key)
	return true
}

sound_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	if method != "PlayLocalSound" {return 0, false}
	target := classes.Object_From_Argument(L, 2)
	if target == nil || !classes.Is_A(target, "Sound") {
		return vm.RaiseError(L, "PlayLocalSound expects a Sound"), true
	}
	_ = classes.Sound_Play(cast(^classes.Sound)target)
	return 0, true
}

SoundService_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^SoundService)object)
}

Register_SoundService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&SoundService_Class,
		SoundService_construct,
		SoundService_destroy,
		creatable = false,
		get = sound_service_get,
		namecall = sound_service_namecall,
		methods = []string{"PlayLocalSound"},
	)
}
