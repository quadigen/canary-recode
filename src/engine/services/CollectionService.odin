package services

// wire:service global="CollectionService"

import "core:strings"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

Collection_Tag :: struct {
	name:    string,
	objects: [dynamic]^classes.Object,
}

CollectionService_Class := classes.Class_Info{
	name   = "CollectionService",
	parent = &Service_Class,
}

CollectionService :: struct {
	using service: Service,

	tags: [dynamic]Collection_Tag,
}

collection_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(CollectionService)
	service.service = Service_Init(
		&CollectionService_Class,
		"CollectionService",
		data_model,
	)
	return &service.object
}

collection_object_from_argument :: proc(
	L: ^vm.State,
	index: int,
) -> ^classes.Object {
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

collection_find_tag :: proc(
	service: ^CollectionService,
	name: string,
) -> int {
	if service == nil {
		return -1
	}

	for tag, index in service.tags {
		if tag.name == name {
			return index
		}
	}

	return -1
}

collection_contains_object :: proc(
	objects: []^classes.Object,
	object: ^classes.Object,
) -> bool {
	for item in objects {
		if item == object {
			return true
		}
	}
	return false
}

collection_validate_tag :: proc(L: ^vm.State, tag: string) -> bool {
	if len(tag) == 0 {
		_ = vm.RaiseError(L, "tag must not be empty")
		return false
	}

	if len(tag) > 100 {
		_ = vm.RaiseError(L, "tag must be at most 100 characters")
		return false
	}

	return true
}

Collection_AddTag :: proc(
	service: ^CollectionService,
	object: ^classes.Object,
	tag_name: string,
) {
	index := collection_find_tag(service, tag_name)

	if index < 0 {
		append(
			&service.tags,
			Collection_Tag{
				name = strings.clone(tag_name),
			},
		)
		index = len(service.tags)-1
	}

	tag := &service.tags[index]
	if !collection_contains_object(tag.objects[:], object) {
		append(&tag.objects, object)
	}
}

Collection_RemoveTag :: proc(
	service: ^CollectionService,
	object: ^classes.Object,
	tag_name: string,
) {
	index := collection_find_tag(service, tag_name)
	if index < 0 {
		return
	}

	tag := &service.tags[index]
	for item, item_index in tag.objects {
		if item == object {
			ordered_remove(&tag.objects, item_index)
			break
		}
	}

	if len(tag.objects) == 0 {
		delete(tag.objects)
		delete(tag.name)
		ordered_remove(&service.tags, index)
	}
}

Collection_HasTag :: proc(
	service: ^CollectionService,
	object: ^classes.Object,
	tag_name: string,
) -> bool {
	index := collection_find_tag(service, tag_name)
	if index < 0 {
		return false
	}

	return collection_contains_object(
		service.tags[index].objects[:],
		object,
	)
}

collection_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "AddTag",
	     "RemoveTag",
	     "HasTag",
	     "GetTags",
	     "GetTagged",
	     "GetAllTags":
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
) -> (i32, bool) {
	service := cast(^CollectionService)object

	switch method {
	case "AddTag":
		target := collection_object_from_argument(L, 2)
		if target == nil {
			return vm.RaiseError(L, "AddTag expects an Instance"), true
		}

		tag := vm.ArgString(L, 3)
		if !collection_validate_tag(L, tag) {
			return 0, true
		}

		Collection_AddTag(service, target, tag)
		return 0, true

	case "RemoveTag":
		target := collection_object_from_argument(L, 2)
		if target == nil {
			return vm.RaiseError(L, "RemoveTag expects an Instance"), true
		}

		tag := vm.ArgString(L, 3)
		if !collection_validate_tag(L, tag) {
			return 0, true
		}

		Collection_RemoveTag(service, target, tag)
		return 0, true

	case "HasTag":
		target := collection_object_from_argument(L, 2)
		if target == nil {
			return vm.RaiseError(L, "HasTag expects an Instance"), true
		}

		tag := vm.ArgString(L, 3)
		if !collection_validate_tag(L, tag) {
			return 0, true
		}

		vm.PushBoolean(
			L,
			Collection_HasTag(service, target, tag),
		)
		return 1, true

	case "GetTags":
		target := collection_object_from_argument(L, 2)
		if target == nil {
			return vm.RaiseError(L, "GetTags expects an Instance"), true
		}

		count := 0
		for tag in service.tags {
			if collection_contains_object(tag.objects[:], target) {
				count += 1
			}
		}

		vm.NewTable(L, count)

		output_index := 1
		for tag in service.tags {
			if collection_contains_object(tag.objects[:], target) {
				vm.PushString(L, tag.name)
				vm.SetArrayValue(L, -2, output_index)
				output_index += 1
			}
		}

		return 1, true

	case "GetTagged":
		tag_name := vm.ArgString(L, 2)
		if !collection_validate_tag(L, tag_name) {
			return 0, true
		}

		index := collection_find_tag(service, tag_name)
		if index < 0 {
			vm.NewTable(L, 0)
			return 1, true
		}

		tag := &service.tags[index]
		count := 0

		for item in tag.objects {
			if item != nil &&
			   !item.destroyed &&
			   classes.Object_Is_Accessible(L, item) {
				count += 1
			}
		}

		vm.NewTable(L, count)

		output_index := 1
		for item in tag.objects {
			if item == nil ||
			   item.destroyed ||
			   !classes.Object_Is_Accessible(L, item) {
				continue
			}

			classes.Push_Object(L, item)
			vm.SetArrayValue(L, -2, output_index)
			output_index += 1
		}

		return 1, true

	case "GetAllTags":
		vm.NewTable(L, len(service.tags))

		for tag, index in service.tags {
			vm.PushString(L, tag.name)
			vm.SetArrayValue(L, -2, index+1)
		}

		return 1, true
	}

	return 0, false
}

collection_service_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	service := cast(^CollectionService)object

	for tag in service.tags {
		delete(tag.objects)
		delete(tag.name)
	}

	delete(service.tags)

	classes.Object_Destroy(object)
	free(service)
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
