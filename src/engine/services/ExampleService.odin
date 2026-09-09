package services

// wire:service global="exampleService"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

ExampleService_Class := classes.Class_Info{name = "ExampleService", parent = &Service_Class}

ExampleService :: struct {
	using service: Service,
	call_count: i64,
}

example_service_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	service := new(ExampleService)
	service.service = Service_Init(&ExampleService_Class, "ExampleService", data_model)
	return &service.object
}

example_service_get :: proc(L: ^vm.State, object: ^classes.Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, key: string) -> bool {
	service := cast(^ExampleService)object
	switch key {
	case "CallCount": vm.PushNumber(L, f64(service.call_count))
	case "Add", "Echo", "MakeColor", "GetService": vm.PushUserdataMethod(L, key)
	case: return false
	}
	return true
}

example_service_namecall :: proc(L: ^vm.State, object: ^classes.Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, method: string) -> (i32, bool) {
	service := cast(^ExampleService)object
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

example_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^ExampleService)object)
}

Register_ExampleService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(registry, &ExampleService_Class, example_service_construct, example_service_destroy, creatable = false, get = example_service_get, namecall = example_service_namecall)
}
