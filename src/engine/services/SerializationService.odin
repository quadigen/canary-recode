package services

// wire:service

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import serializer "../serializer"
import vm "../vm"
import "core:strings"

SerializationService_Class := classes.Class_Info {
	name   = "SerializationService",
	parent = &Service_Class,
}

serialization_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Service)
	service^ = Service_Init(&SerializationService_Class, "SerializationService", data_model)
	return &service.object
}

serialization_service_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	classes.Object_Destroy(object)
	free(cast(^Service)object)
}

serialization_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	key: string,
) -> bool {
	if key != "SerializeInstancesAsync" && key != "DeserializeInstancesAsync" {return false}
	vm.PushUserdataMethod(L, key)
	return true
}

serialization_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	dt: ^datatypes.Registry,
	en: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	registry := object.signal_registry
	switch method {
	case "SerializeInstancesAsync":
		if !vm.IsTable(L, 2) {return vm.RaiseError(L, "expected an array of instances"), true}
		roots := make([dynamic]^classes.Object, 0, vm.RawLen(L, 2), context.temp_allocator)
		defer delete(roots)
		for i := 1; i <= vm.RawLen(L, 2); i += 1 {
			_ = vm.RawGetIndex(L, 2, i)
			root := classes.Object_From_Argument(L, -1)
			vm.Pop(L)
			if root == nil ||
			   root.destroyed {return vm.RaiseError(L, "expected a live instance"), true}
			append(&roots, root)
		}
		container := classes.Object_Init(&classes.Folder_Class, "SerializedInstances")
		container.children = roots
		data, err := serializer.Serialize(registry, L, &container)
		defer delete(data)
		if !serializer.Error_Is_None(err) {
			return serialization_service_error(L, &err), true
		}
		vm.PushBuffer(L, data)
		return 1, true
	case "DeserializeInstancesAsync":
		data := vm.ArgBuffer(L, 2)
		root, err := serializer.Deserialize(registry, L, nil, data)
		if !serializer.Error_Is_None(err) {
			return serialization_service_error(L, &err), true
		}
		if root.class != &classes.Folder_Class || root.name != "SerializedInstances" {
			vm.NewTable(L, 1, 0)
			classes.Push_Object(L, root)
			vm.RawSetIndex(L, -2, 1)
			return 1, true
		}
		vm.NewTable(L, len(root.children), 0)
		index := len(root.children)
		for index > 0 {
			child := root.children[index - 1]
			classes.Set_Parent(child, nil)
			classes.Push_Object(L, child)
			vm.RawSetIndex(L, -2, index)
			index -= 1
		}
		classes.Destroy_Hierarchy(root)
		return 1, true
	}
	return 0, false
}

serialization_service_error :: proc(L: ^vm.State, err: ^serializer.Error) -> i32 {
	message := serializer.Error_String(err^)
	text := strings.clone(message, context.temp_allocator)
	delete(message)
	serializer.Error_Delete(err)
	return vm.RaiseError(L, text)
}

Register_SerializationService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&SerializationService_Class,
		serialization_service_construct,
		serialization_service_destroy,
		creatable = false,
		get = serialization_service_get,
		namecall = serialization_service_namecall,
		methods = []string{"SerializeInstancesAsync", "DeserializeInstancesAsync"},
	)
}
