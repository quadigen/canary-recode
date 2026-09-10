package services

import "base:runtime"
import "core:fmt"
import "core:strings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

RunService_Class := classes.Class_Info{name = "RunService", parent = &Service_Class}

Render_Binding :: struct {
	name: string,
	priority: i32,
	callback_ref: i32,
}

RunService :: struct {
	using service: Service,
	callbacks: [dynamic]Render_Binding,
}

run_service_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	service := new(RunService)
	service.service = Service_Init(&RunService_Class, "RunService", data_model)
	return &service.object
}

sort_render_bindings :: proc(service: ^RunService) {
	for index := 1; index < len(service.callbacks); index += 1 {
		cursor := index
		for cursor > 0 && service.callbacks[cursor].priority < service.callbacks[cursor-1].priority {
			service.callbacks[cursor], service.callbacks[cursor-1] = service.callbacks[cursor-1], service.callbacks[cursor]
			cursor -= 1
		}
	}
}

find_render_binding :: proc(service: ^RunService, name: string) -> int {
	for callback, index in service.callbacks {
		if callback.name == name { return index }
	}
	return -1
}

run_service_get :: proc(L: ^vm.State, object: ^classes.Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, key: string) -> bool {
	switch key {
	case "BindToRenderStep", "UnbindFromRenderStep": vm.PushUserdataMethod(L, key)
	case: return false
	}
	return true
}

run_service_namecall :: proc(L: ^vm.State, object: ^classes.Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, method: string) -> (i32, bool) {
	context = runtime.default_context()
	service := cast(^RunService)object
	switch method {
	case "BindToRenderStep":
		name := vm.ArgString(L, 2)
		priority: i32
		callback_index := 4
		if vm.IsFunction(L, 3) { callback_index = 3 } else { priority = i32(vm.ArgNumber(L, 3)) }
		if !vm.IsFunction(L, callback_index) {
			_ = vm.RaiseError(L, "BindToRenderStep callback must be a function")
			return 0, true
		}
		vm.PushValue(L, callback_index)
		callback_ref := vm.RetainValue(L)
		vm.Pop(L)
		existing := find_render_binding(service, name)
		if existing >= 0 {
			vm.ReleaseValue(L, service.callbacks[existing].callback_ref)
			service.callbacks[existing].priority = priority
			service.callbacks[existing].callback_ref = callback_ref
		} else {
			append(&service.callbacks, Render_Binding{name = strings.clone(name), priority = priority, callback_ref = callback_ref})
		}
		sort_render_bindings(service)
		return 0, true
	case "UnbindFromRenderStep":
		index := find_render_binding(service, vm.ArgString(L, 2))
		if index >= 0 {
			vm.ReleaseValue(L, service.callbacks[index].callback_ref)
			delete(service.callbacks[index].name)
			ordered_remove(&service.callbacks, index)
		}
		return 0, true
	}
	return 0, false
}

Run_Service_Step :: proc(service: ^RunService, L: ^vm.State, delta_time: f32) {
	if service == nil || service.destroyed || L == nil { return }
	callback_refs: [dynamic]i32
	for callback in service.callbacks {
		vm.PushRegistryReference(L, callback.callback_ref)
		append(&callback_refs, vm.RetainValue(L))
		vm.Pop(L)
	}
	for callback_ref in callback_refs {
		top := vm.StackTop(L)
		vm.PushRegistryReference(L, callback_ref)
		vm.PushNumber(L, f64(delta_time))
		ok, err := vm.ProtectedCall(L, 1)
		vm.SetStackTop(L, top)
		if !ok {
			fmt.eprintf("Render step callback failed: %s\n", err)
			delete(err)
		}
	}
	for callback_ref in callback_refs { vm.ReleaseValue(L, callback_ref) }
	delete(callback_refs)
}

run_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^RunService)object
	for callback in service.callbacks { delete(callback.name) }
	delete(service.callbacks)
	classes.Object_Destroy(object)
	free(service)
}

Register_RunService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(registry, &RunService_Class, run_service_construct, run_service_destroy, creatable = false, get = run_service_get, namecall = run_service_namecall)
}

