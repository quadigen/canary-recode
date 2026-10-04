package services

// wire:service global="memoryStoreService"

import "core:strings"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

MemoryStoreService_Class := classes.Class_Info{
	name   = "MemoryStoreService",
	parent = &Service_Class,
}

MemoryStoreService :: struct {
	using service: Service,
}

memory_store_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(MemoryStoreService)
	service.service = Service_Init(
		&MemoryStoreService_Class,
		"MemoryStoreService",
		data_model,
	)
	return &service.object
}

memory_store_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "GetMap", "GetSortedMap", "GetQueue", "GetHashMap", "CreateQueue",
	     "CreateHashMap", "CreateMemoryStore", "CreateSortedMap", "CreateMemoryQueue":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

memory_store_empty_table :: proc(L: ^vm.State) {
	vm.NewTable(L, 0, 3)
	vm.PushString(L, "memory")
	vm.SetField(L, -2, "DataStoreType")
	vm.PushString(L, "MemoryStore")
	vm.SetField(L, -2, "DataStoreTypeName")
	vm.PushInteger(L, 0)
	vm.SetField(L, -2, "DataStoreCapacity")
}

memory_store_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	switch method {
	case "GetMap", "CreateMemoryStore":
		memory_store_empty_table(L)
		return 1, true
	case "GetSortedMap", "CreateSortedMap", "GetHashMap", "CreateHashMap",
	     "GetQueue", "CreateMemoryQueue", "CreateQueue":
		memory_store_empty_table(L)
		return 1, true
	}
	return 0, false
}

memory_store_service_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	classes.Object_Destroy(object)
	free(cast(^MemoryStoreService)object)
}

Register_MemoryStoreService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&MemoryStoreService_Class,
		memory_store_service_construct,
		memory_store_service_destroy,
		creatable = false,
		get       = memory_store_service_get,
		namecall  = memory_store_service_namecall,
	)
}