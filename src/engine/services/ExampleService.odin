package services


import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"
import "core:sync"

ExampleService_Class := classes.Class_Info {
	name   = "ExampleService",
	parent = &Service_Class,
}

ExampleService :: struct {
	using service:  Service,
	call_count:     i64,
	parallel_value: i64,
}

example_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(ExampleService)
	service.service = Service_Init(&ExampleService_Class, "ExampleService", data_model)
	return &service.object
}

example_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^ExampleService)object
	switch key {
	case "CallCount":
		vm.PushNumber(L, f64(sync.atomic_load(&service.call_count)))
	case "ParallelValue":
		vm.PushNumber(L, f64(sync.atomic_load(&service.parallel_value)))
	case "Add", "Echo", "MakeColor", "GetService":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

example_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^ExampleService)object
	switch method {
	case "Add":
		_ = sync.atomic_add(&service.call_count, 1)
		vm.PushNumber(L, vm.ArgNumber(L, 2) + vm.ArgNumber(L, 3))
		return 1, true
	case "Echo":
		_ = sync.atomic_add(&service.call_count, 1)
		vm.PushValue(L, 2)
		return 1, true
	case "MakeColor":
		_ = sync.atomic_add(&service.call_count, 1)
		if datatype_registry == nil {return 0, false}
		datatypes.Push_Color3(
			L,
			datatype_registry,
			datatypes.Color3 {
				f32(vm.ArgNumber(L, 2)),
				f32(vm.ArgNumber(L, 3)),
				f32(vm.ArgNumber(L, 4)),
			},
		)
		return 1, true
	case "GetService":
		classes.Push_Object(L, Service_Get_Service(&service.service, vm.ArgString(L, 2)))
		return 1, true
	}
	return 0, false
}


example_service_parallel_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "CallCount", "ParallelValue", "Add", "Echo":
		return example_service_get(L, object, datatype_registry, enum_registry, key)
	}
	return false
}

example_service_parallel_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	if key != "ParallelValue" {return false}
	service := cast(^ExampleService)object
	value := vm.ArgNumber(L, value_index)
	if math.is_nan(value) ||
	   math.is_inf(value) ||
	   math.floor(value) != value ||
	   abs(value) > 9007199254740991.0 {
		_ = vm.RaiseError(L, "ParallelValue expects a safe integer")
		return true
	}
	sync.atomic_store(&service.parallel_value, i64(value))
	return true
}

example_service_parallel_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "Add", "Echo":
		return example_service_namecall(L, object, datatype_registry, enum_registry, method)
	}

	return 0, false
}

example_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^ExampleService)object)
}

Register_ExampleService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&ExampleService_Class,
		example_service_construct,
		example_service_destroy,
		creatable = false,
		get = example_service_get,
		set = example_service_parallel_set,
		namecall = example_service_namecall,
		parallel_get = example_service_parallel_get,
		parallel_set = example_service_parallel_set,
		parallel_namecall = example_service_parallel_namecall,
		properties = []string{"CallCount", "ParallelValue"},
		methods = []string{"Add", "Echo", "MakeColor", "GetService"},
	)
}
