#+build !js

package services

// wire:service global="ExportService"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import serializer "../serializer"
import vm "../vm"

ExportService_Class := classes.Class_Info {
	name   = "ExportService",
	parent = &Service_Class,
}

ExportService :: struct {
	using service: Service,
}

export_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(ExportService)
	service.service = Service_Init(&ExportService_Class, "ExportService", data_model)
	return &service.object
}

export_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^ExportService)object)
}

export_datamodel_to_file :: proc(service: ^ExportService, L: ^vm.State, path: string) -> bool {
	if service == nil || L == nil || path == "" {
		return false
	}
	model := service.data_model
	if model == nil || model.registry == nil || model.registry.classes == nil {
		return false
	}
	return serializer.Serialize_To_File(
		model.registry.classes,
		L,
		&model.object,
		path,
		export_content_service_filter,
	)
}

export_content_service_filter :: proc(parent: ^classes.Object, object: ^classes.Object) -> bool {
	if object == nil || object.class == nil {
		return true
	}

	if parent == nil || !classes.Is_A(parent, "DataModel") {
		return false
	}
	if !classes.Is_A(object, "Service") {
		return false
	}
	return !Map_Content_Service(object.name)
}

export_object_to_file :: proc(service: ^ExportService, L: ^vm.State, object: ^classes.Object, path: string) -> bool {
	if service == nil || L == nil || object == nil || path == "" {
		return false
	}
	model := service.data_model
	if model == nil || model.registry == nil || model.registry.classes == nil {
		return false
	}
	return serializer.Serialize_To_File(model.registry.classes, L, object, path)
}

export_object_from_argument :: proc(L: ^vm.State, index: int) -> ^classes.Object {
	binding := vm.UserdataBindingOf(L, index)
	if binding == nil || binding.name != "Instance" {
		return nil
	}
	object := cast(^classes.Object)vm.UserdataValue(L, index)
	if !classes.Object_Is_Accessible(L, object) {
		return nil
	}
	return object
}

export_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "ExportToFile", "Export":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

export_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^ExportService)object
	switch method {
	case "ExportToFile":
		path := vm.ArgString(L, 2)
		if path == "" {
			return vm.RaiseError(L, "ExportService:ExportToFile expects a file path"), true
		}
		vm.PushBoolean(L, export_datamodel_to_file(service, L, path))
		return 1, true
	case "Export":
		target := export_object_from_argument(L, 2)
		if target == nil {
			return vm.RaiseError(L, "ExportService:Export expects an Instance"), true
		}
		path := vm.ArgString(L, 3)
		if path == "" {
			return vm.RaiseError(L, "ExportService:Export expects a file path"), true
		}
		vm.PushBoolean(L, export_object_to_file(service, L, target, path))
		return 1, true
	}
	return 0, false
}

Register_ExportService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&ExportService_Class,
		export_service_construct,
		export_service_destroy,
		creatable = false,
		get = export_service_get,
		namecall = export_service_namecall,
	)
}