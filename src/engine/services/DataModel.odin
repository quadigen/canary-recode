package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

DataModel_Class := classes.Class_Info{
	name = "DataModel",
	parent = &classes.Instance_Class,
}

DataModel :: struct {
	using object: classes.Object,
	registry:     ^Registry,
}

data_model_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	model := new(DataModel)
	model.object = classes.Object_Init(&DataModel_Class, "game")
	return &model.object
}

data_model_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	model := cast(^DataModel)object
	model.registry = nil
	classes.Object_Destroy(object)
	free(model)
}

// Native engine access. This intentionally bypasses Luau thread security.
DataModel_Get_Service :: proc(model: ^DataModel, name: string) -> ^classes.Object {
	if model == nil || model.destroyed || model.registry == nil { return nil }
	return Ensure_Service(model.registry, name)
}

data_model_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	model := cast(^DataModel)object
	descriptor := Find_Service(model.registry, key)
	if descriptor != nil {
		if !Service_Access_Allowed(L, descriptor) {
			_ = vm.RaiseError(L, "insufficient security capabilities to access this service")
			return true
		}
		service := Ensure_Service(model.registry, key)
		if service != nil {
			classes.Push_Object(L, service)
			return true
		}
	}
	switch key {
	case "GetService", "FindService": vm.PushUserdataMethod(L, key)
	case: return false
	}
	return true
}

data_model_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	model := cast(^DataModel)object
	switch method {
	case "GetService":
		name := vm.ArgString(L, 2)
		descriptor := Find_Service(model.registry, name)
		if descriptor == nil {
			return vm.RaiseError(L, "unknown service"), true
		}
		if !Service_Access_Allowed(L, descriptor) {
			return vm.RaiseError(L, "insufficient security capabilities to access this service"), true
		}
		service := Ensure_Service(model.registry, name)
		if service == nil {
			return vm.RaiseError(L, "service is unavailable"), true
		}
		classes.Push_Object(L, service)
		return 1, true
	case "FindService":
		name := vm.ArgString(L, 2)
		descriptor := Find_Service(model.registry, name)
		if descriptor == nil || !Service_Access_Allowed(L, descriptor) {
			vm.PushNil(L)
			return 1, true
		}
		classes.Push_Object(L, Ensure_Service(model.registry, name))
		return 1, true
	}
	return 0, false
}

Register_DataModel_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&DataModel_Class,
		data_model_construct,
		data_model_destroy,
		creatable = false,
		get = data_model_get,
		namecall = data_model_namecall,
	)
}
