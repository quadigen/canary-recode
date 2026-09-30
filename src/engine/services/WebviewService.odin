package services

import "core:fmt"
// wire:service global="WebviewService"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import kineffi "../bindings"
import vm "../vm"

WebviewService_Class := classes.Class_Info{name = "WebviewService", parent = &Service_Class}

WebviewService :: struct {
	using service: Service,
	call_count: i64,
}

WebviewService_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	service := new(WebviewService)
	service.service = Service_Init(&WebviewService_Class, "WebviewService", data_model)

	return &service.object
}

WebviewService_get :: proc(L: ^vm.State, object: ^classes.Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, key: string) -> bool {
	service := cast(^WebviewService)object
	switch key {
	case "CallCount": vm.PushNumber(L, f64(service.call_count))
	case "Add", "Echo", "MakeColor", "GetService": vm.PushUserdataMethod(L, key)
	case: return false
	}
	return true
}

WebviewService_namecall :: proc(L: ^vm.State, object: ^classes.Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, method: string) -> (i32, bool) {
	service := cast(^WebviewService)object
	switch method {
	case "Add":
		service.call_count += 1
		vm.PushNumber(L, vm.ArgNumber(L, 2)+vm.ArgNumber(L, 3))
		return 1, true
	case "Echo":
		service.call_count += 1
		vm.PushValue(L, 2)
		return 1, true
	case "MakeColor":
		service.call_count += 1
		if datatype_registry == nil { return 0, false }
		datatypes.Push_Color3(L, datatype_registry, datatypes.Color3{f32(vm.ArgNumber(L, 2)), f32(vm.ArgNumber(L, 3)), f32(vm.ArgNumber(L, 4))})
		return 1, true
	case "GetService":
		classes.Push_Object(L, Service_Get_Service(&service.service, vm.ArgString(L, 2)))
		return 1, true
	}
	return 0, false
}

WebviewService_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^WebviewService)object)
}

Register_WebviewService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(registry, &WebviewService_Class, WebviewService_construct, WebviewService_destroy, creatable = false, get = WebviewService_get, namecall = WebviewService_namecall)
}

