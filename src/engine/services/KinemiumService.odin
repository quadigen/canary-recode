#+build !js
// wire:service
package services


import "core:strings"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

Kinemium_Api_Auth :: struct {
	homeserver: string,
	token:      string,
}

KinemiumService :: struct {
	using service: Service,
	api_auth:      Kinemium_Api_Auth,
}

KinemiumService_Class := classes.Class_Info {
	name   = "KinemiumService",
	parent = &Service_Class,
}

kinemium_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(KinemiumService)
	service.service = Service_Init(&KinemiumService_Class, "KinemiumService", data_model)
	return &service.object
}

kinemium_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^KinemiumService)object
	switch key {
	case "ApiHomeserver":
		vm.PushString(L, service.api_auth.homeserver)
		return true
	case "HasApiToken":
		vm.PushBoolean(L, service.api_auth.token != "")
		return true
	case "UseApiToken", "ClearApiToken", "Request", "GetService":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

kinemium_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^KinemiumService)object
	switch method {
	case "UseApiToken":
		homeserver := vm.ArgString(L, 2)
		token := vm.ArgString(L, 3)
		if service.api_auth.token != "" {
			delete(service.api_auth.homeserver)
			delete(service.api_auth.token)
		}
		service.api_auth.homeserver = strings.clone(homeserver)
		service.api_auth.token = strings.clone(token)
		return 0, true
	case "ClearApiToken":
		if service.api_auth.token != "" {
			delete(service.api_auth.homeserver)
			delete(service.api_auth.token)
		}
		service.api_auth = {}
		return 0, true
	case "Request":
		{
			base, token, ok := kinemium_resolve_auth(service.service.data_model.registry, L, 0)
			if !ok {
				vm.PushBoolean(L, false)
				vm.PushString(L, "Not logged in.")
				kinemium_push_meta(L, Kinemium_Meta{})
				return 3, true
			}
			options := kinemium_options_from_table(L, 3)
			defer kinemium_options_destroy(options)
			success, data, body, meta := kinemium_call(
				base,
				token,
				vm.ArgString(L, 2),
				vm.ArgString(L, 3),
				options,
			)
			defer kinemium_call_destroy(data, body, meta)
			kinemium_push_result(L, success, data, body, options.raw || !success, meta)
			return 3, true
		}
	case "GetService":
		classes.Push_Object(L, Service_Get_Service(&service.service, vm.ArgString(L, 2)))
		return 1, true
	}
	return 0, false
}

kinemium_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^KinemiumService)object
	if service.api_auth.token != "" {
		delete(service.api_auth.homeserver)
		delete(service.api_auth.token)
	}
	classes.Object_Destroy(object)
	free(service)
}

Register_KinemiumService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&KinemiumService_Class,
		kinemium_service_construct,
		kinemium_service_destroy,
		creatable = false,
		get = kinemium_service_get,
		namecall = kinemium_service_namecall,
	)
}
