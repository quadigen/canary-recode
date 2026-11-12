package services

// wire:service global="CollectionService"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

CollectionService_Class := classes.Class_Info {
	name   = "CollectionService",
	parent = &Service_Class,
}

CollectionService :: struct {
	using service: Service,
}

collection_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(CollectionService)
	service.service = Service_Init(&CollectionService_Class, "CollectionService", data_model)
	return &service.object
}

collection_object_from_argument :: proc(L: ^vm.State, index: int) -> ^classes.Object {
	binding := vm.UserdataBindingOf(L, index)
	if binding == nil || binding.name != "Instance" {
		return nil
	}

	object := cast(^classes.Object)vm.UserdataValue(L, index)
	if object == nil || object.destroyed {
		return nil
	}

	return object
}

collection_validate_tag :: proc(L: ^vm.State, tag: string) -> bool {
	if !classes.Tag_Name_Is_Valid(tag) {
		_ = vm.RaiseError(L, "tag must be 1-100 characters")
		return false
	}
	return true
}

collection_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "AddTag", "RemoveTag", "HasTag", "GetTags", "GetTagged", "GetAllTags":
		vm.PushUserdataMethod(L, key)

	case:
		return false
	}

	return true
}

collection_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^CollectionService)object

	switch method {
	case "AddTag", "RemoveTag", "HasTag", "GetTags":
		target := collection_object_from_argument(L, 2)
		if target == nil || !classes.Object_Is_Accessible(L, target) {
			return vm.RaiseError(L, "expected an accessible Instance"), true
		}
		if method == "GetTags" {
			classes.Object_Push_Tags(L, target)
			return 1, true
		}
		tag := vm.ArgString(L, 3)
		if !collection_validate_tag(L, tag) {return 0, true}
		switch method {
		case "AddTag": classes.Object_Add_Tag(target, tag)
		case "RemoveTag": classes.Object_Remove_Tag(target, tag)
		case "HasTag": vm.PushBoolean(L, classes.Object_Has_Tag(target, tag)); return 1, true
		}
		return 0, true

	case "GetTagged":
		tag := vm.ArgString(L, 2)
		if !collection_validate_tag(L, tag) {return 0, true}
		vm.NewTable(L, 0)
		index := 1
		for item in service.signal_registry.tagged_objects {
			if item.destroyed || !classes.Object_Is_Accessible(L, item) ||
			   !classes.Object_Has_Tag(item, tag) {continue}
			classes.Push_Object(L, item)
			vm.SetArrayValue(L, -2, index)
			index += 1
		}
		return 1, true

	case "GetAllTags":
		seen: map[string]bool
		defer delete(seen)
		vm.NewTable(L, 0)
		index := 1
		for item in service.signal_registry.tagged_objects {
			if item.destroyed || !classes.Object_Is_Accessible(L, item) {continue}
			for tag in item.tags {
				if seen[tag] {continue}
				seen[tag] = true
				vm.PushString(L, tag)
				vm.SetArrayValue(L, -2, index)
				index += 1
			}
		}
		return 1, true
	}

	return 0, false
}

collection_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^CollectionService)object)
}

Register_CollectionService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&CollectionService_Class,
		collection_service_construct,
		collection_service_destroy,
		creatable = false,
		get = collection_service_get,
		namecall = collection_service_namecall,
	)
}
