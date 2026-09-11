package services

// wire:service global="LocalizationService"

import "core:strings"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

LocalizationService_Class := classes.Class_Info{
	name   = "LocalizationService",
	parent = &Service_Class,
}

LocalizationService :: struct {
	using service: Service,

	roblox_locale_id: string,
	system_locale_id: string,
}

localization_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(LocalizationService)
	service.service = Service_Init(
		&LocalizationService_Class,
		"LocalizationService",
		data_model,
	)

	// Engine default until platform locale detection is wired.
	service.roblox_locale_id = strings.clone("en-us")
	service.system_locale_id = strings.clone("en-us")

	return &service.object
}

localization_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^LocalizationService)object

	switch key {
	case "RobloxLocaleId":
		vm.PushString(L, service.roblox_locale_id)

	case "SystemLocaleId":
		vm.PushString(L, service.system_locale_id)

	case "SetLocale":
		vm.PushUserdataMethod(L, key)

	case:
		return false
	}

	return true
}

localization_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	service := cast(^LocalizationService)object

	switch method {
	case "SetLocale":
		locale := vm.ArgString(L, 2)
		if len(locale) == 0 {
			return vm.RaiseError(L, "locale must not be empty"), true
		}

		delete(service.roblox_locale_id)
		service.roblox_locale_id = strings.clone(locale)

		if !vm.IsNoneOrNil(L, 3) {
			delete(service.system_locale_id)
			service.system_locale_id =
				strings.clone(vm.ArgString(L, 3))
		}

		return 0, true
	}

	return 0, false
}

localization_service_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	service := cast(^LocalizationService)object

	delete(service.roblox_locale_id)
	delete(service.system_locale_id)

	classes.Object_Destroy(object)
	free(service)
}

Register_LocalizationService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&LocalizationService_Class,
		localization_service_construct,
		localization_service_destroy,
		creatable = false,
		get = localization_service_get,
		namecall = localization_service_namecall,
	)
}
