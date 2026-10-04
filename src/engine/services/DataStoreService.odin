package services

// wire:service global="dataStoreService"

import "core:strings"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

DataStore :: struct {
	name:   string,
	signal: ^signals.Signal,
}

DataStoreService :: struct {
	using service: Service,
	stores: [dynamic]DataStore,
	limit_reached: bool,
}

DataStoreService_Class := classes.Class_Info{
	name   = "DataStoreService",
	parent = &Service_Class,
}

data_store_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(DataStoreService)
	service.service = Service_Init(
		&DataStoreService_Class,
		"DataStoreService",
		data_model,
	)
	return &service.object
}

data_store_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^DataStoreService)object
	switch key {
	case "LimitReached":
		vm.PushBoolean(L, service.limit_reached)
		return true
	case "GetDataStore", "GetGlobalDataStore", "GetOrderedDataStore",
	     "CreateDataStore", "CreateGlobalDataStore", "CreateOrderedDataStore",
	     "RemoveDataStore", "UpdateAsync", "SetAsync", "GetAsync", "GetRequestBudgetForRequestType":
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

data_store_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	service := cast(^DataStoreService)object
	switch method {
	case "GetDataStore", "GetGlobalDataStore", "GetOrderedDataStore",
	     "CreateDataStore", "CreateGlobalDataStore", "CreateOrderedDataStore":
		name := vm.ArgString(L, 2)
		vm.NewTable(L, 0, 4)
		vm.PushString(L, name)
		vm.SetField(L, -2, "Name")
		vm.PushInteger(L, 0)
		vm.SetField(L, -2, "DataStoreCapacity")
		vm.PushInteger(L, 0)
		vm.SetField(L, -2, "DataStoreSizeInBytes")
		vm.PushBoolean(L, true)
		vm.SetField(L, -2, "IsOpen")
		vm.PushNil(L)
		vm.SetField(L, -2, "GetAsync")
		vm.PushNil(L)
		vm.SetField(L, -2, "SetAsync")
		vm.PushNil(L)
		vm.SetField(L, -2, "UpdateAsync")
		vm.PushBoolean(L, false)
		vm.SetField(L, -2, "IsLegacy")
		vm.NewTable(L, 0, 0)
		vm.SetField(L, -2, "Service")
		vm.PushBoolean(L, true)
		vm.SetField(L, -2, "Opened")
		return 1, true
	case "RemoveDataStore":
		return 0, true
	case "GetAsync", "SetAsync", "UpdateAsync":
		return vm.RaiseError(L, "DataStoreService: this runtime has no backing data store"), true
	case "GetRequestBudgetForRequestType":
		vm.PushNumber(L, 0)
		return 1, true
	}
	return 0, false
}

data_store_service_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	service := cast(^DataStoreService)object
	for store in service.stores {
		if store.signal != nil {
			signals.Destroy(store.signal)
		}
		delete(store.name)
	}
	delete(service.stores)
	classes.Object_Destroy(object)
	free(service)
}

Register_DataStoreService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&DataStoreService_Class,
		data_store_service_construct,
		data_store_service_destroy,
		creatable = false,
		get       = data_store_service_get,
		namecall  = data_store_service_namecall,
	)
}