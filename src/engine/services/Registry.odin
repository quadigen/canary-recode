package services

import sdl3 "../platform"
import classes "../classes"
import datatypes "../datatypes"
import signals "../signals"
import vm "../vm"

Service_Descriptor :: struct {
	name:         string,
	class_name:   string,
	global_name:  string,
	object:       ^classes.Object,
	constructing: bool,
	security:     vm.Security_Requirement,
}

Registry :: struct {
	classes:         ^classes.Registry,
	services:        [dynamic]Service_Descriptor,
	data_model:      ^DataModel,
	vm_state:        ^vm.VM,
	signal_registry: ^signals.Registry,
}

Registry_Init :: proc(class_registry: ^classes.Registry, signal_registry: ^signals.Registry = nil) -> Registry {
	return Registry{classes = class_registry, signal_registry = signal_registry}
}

Register_Service :: proc(registry: ^Registry, name, class_name: string, global_name: string = "") {
	assert(registry != nil)
	assert(Find_Service(registry, name) == nil)
	append(&registry.services, Service_Descriptor{
		name        = name,
		class_name  = class_name,
		global_name = global_name,
	})
}

Find_Service :: proc(registry: ^Registry, name: string) -> ^Service_Descriptor {
	if registry == nil {
		return nil
	}
	for service, index in registry.services {
		if service.name == name {
			return &registry.services[index]
		}
	}
	return nil
}

Set_Service_Security :: proc(registry: ^Registry, name: string, requirement: vm.Security_Requirement) -> bool {
	descriptor := Find_Service(registry, name)
	if descriptor == nil {
		return false
	}
	descriptor.security = requirement
	if descriptor.object != nil {
		descriptor.object.security_requirement = requirement
	}
	return true
}

Service_Access_Allowed :: proc(L: ^vm.State, descriptor: ^Service_Descriptor) -> bool {
	return descriptor != nil && vm.ThreadMeetsSecurityRequirement(L, descriptor.security)
}

Get_Service_For_Thread :: proc(registry: ^Registry, L: ^vm.State, name: string) -> (^classes.Object, bool) {
	descriptor := Find_Service(registry, name)
	if descriptor == nil || !Service_Access_Allowed(L, descriptor) {
		return nil, false
	}
	return Ensure_Service(registry, name), true
}

Ensure_Service :: proc(registry: ^Registry, name: string) -> ^classes.Object {
	descriptor := Find_Service(registry, name)
	if descriptor == nil || registry.vm_state == nil { return nil }
	if descriptor.object != nil { return descriptor.object }
	if descriptor.constructing { return nil }

	descriptor.constructing = true
	defer descriptor.constructing = false
	object, ok := classes.Push_New(registry.classes, registry.vm_state, descriptor.class_name, false)
	if !ok || object == nil { return nil }
	classes.Set_Name(object, descriptor.name)
	object.security_requirement = descriptor.security
	descriptor.object = object
	classes.Set_Parent(object, &registry.data_model.object)
	vm.Pop(registry.vm_state.L)
	return object
}

Register_Default_Services :: proc(registry: ^Registry) {
	// wire:begin service-classes
	Register_DataModel_Class(registry.classes)
	Register_Service_Class(registry.classes)
	Register_CollectionService_Class(registry.classes)
	Register_ExampleService_Class(registry.classes)
	Register_HttpService_Class(registry.classes)
	Register_Lighting_Class(registry.classes)
	Register_LocalizationService_Class(registry.classes)
	Register_LogService_Class(registry.classes)
	Register_Physics_Class(registry.classes)
	Register_ReplicatedFirst_Class(registry.classes)
	Register_ReplicatedStorage_Class(registry.classes)
	Register_RunService_Class(registry.classes)
	Register_ScriptContext_Class(registry.classes)
	Register_Selection_Class(registry.classes)
	Register_ServerScriptService_Class(registry.classes)
	Register_ServerStorage_Class(registry.classes)
	Register_SoundService_Class(registry.classes)
	Register_StarterGui_Class(registry.classes)
	Register_StarterPack_Class(registry.classes)
	Register_StarterPlayer_Class(registry.classes)
	Register_StudioThemeService_Class(registry.classes)
	Register_TaskScheduler_Class(registry.classes)
	Register_TweenService_Class(registry.classes)
	Register_UserInputService_Class(registry.classes)
	Register_Workspace_Class(registry.classes)
	// wire:end service-classes
	// wire:begin services
	Register_Service(registry, "CollectionService", "CollectionService", "CollectionService")
	Register_Service(registry, "ExampleService", "ExampleService", "exampleService")
	Register_Service(registry, "HttpService", "HttpService", "HttpService")
	Register_Service(registry, "Lighting", "Lighting", "Lighting")
	Register_Service(registry, "LocalizationService", "LocalizationService", "LocalizationService")
	Register_Service(registry, "LogService", "LogService", "logService")
	Register_Service(registry, "Physics", "Physics")
	Register_Service(registry, "ReplicatedFirst", "ReplicatedFirst", "ReplicatedFirst")
	Register_Service(registry, "ReplicatedStorage", "ReplicatedStorage", "ReplicatedStorage")
	Register_Service(registry, "RunService", "RunService")
	Register_Service(registry, "ScriptContext", "ScriptContext")
	Register_Service(registry, "Selection", "Selection", "Selection")
	Register_Service(registry, "ServerScriptService", "ServerScriptService", "ServerScriptService")
	Register_Service(registry, "ServerStorage", "ServerStorage", "ServerStorage")
	Register_Service(registry, "SoundService", "SoundService", "SoundService")
	Register_Service(registry, "StarterGui", "StarterGui", "StarterGui")
	Register_Service(registry, "StarterPack", "StarterPack", "StarterPack")
	Register_Service(registry, "StarterPlayer", "StarterPlayer", "StarterPlayer")
	Register_Service(registry, "StudioThemeService", "StudioThemeService", "StudioThemeService")
	Register_Service(registry, "TaskScheduler", "TaskScheduler")
	Register_Service(registry, "TweenService", "TweenService", "TweenService")
	Register_Service(registry, "UserInputService", "UserInputService")
	Register_Service(registry, "Workspace", "Workspace", "workspace")
	// wire:end services
	Register_Service(registry, "CoreGui", "StarterGui")

	assert(Set_Service_Security(
		registry,
		"ScriptContext",
		vm.SecurityRequirementFromValue(datatypes.SECURITY_CAPABILITY_INTERNAL_SCRIPT_CONTEXT),
	))
	assert(Set_Service_Security(
		registry,
		"StudioThemeService",
		vm.SecurityRequirementFromValue(datatypes.SECURITY_CAPABILITY_INTERNAL_STUDIO_ACCESS),
	))
}

Render_Step :: proc(registry: ^Registry, L: ^vm.State, delta_time: f32) {
	user_input := Find_Service(registry, "UserInputService")
	if user_input != nil && user_input.object != nil {
		User_Input_Begin_Frame(cast(^UserInputService)user_input.object)
	}
	physics := Find_Service(registry, "Physics")
	if physics != nil && physics.object != nil {
		Physics_Step(cast(^Physics)physics.object, delta_time)
	}
	task_scheduler := Find_Service(registry, "TaskScheduler")
	if task_scheduler != nil && task_scheduler.object != nil {
		Task_Scheduler_Step(cast(^TaskScheduler)task_scheduler.object, delta_time)
	}
	run_service := Find_Service(registry, "RunService")
	if run_service != nil && run_service.object != nil {
		Run_Service_Heartbeat(cast(^RunService)run_service.object, L, delta_time)
	}
}

Set_Event :: proc(registry: ^Registry, L: ^vm.State, event: sdl3.Event) {
	user_input_service := Find_Service(registry, "UserInputService")
	if user_input_service != nil && user_input_service.object != nil {
		user_input_service_step(cast(^UserInputService)user_input_service.object, L, event)
	}
}

Prepare_3D :: proc(registry: ^Registry, renderer: ^classes.Renderer_Object) {
	if registry == nil || renderer == nil || renderer.Filament == nil { return }
	lighting := Find_Service(registry, "Lighting")
	if lighting != nil && lighting.object != nil { Lighting_Apply(cast(^Lighting)lighting.object, renderer) }
	workspace_service := Find_Service(registry, "Workspace")
	if workspace_service == nil || workspace_service.object == nil { return }
	workspace_prepare_3d(cast(^Workspace)workspace_service.object, renderer)
}

Render_3D :: proc(registry: ^Registry, L: ^vm.State, renderer: ^classes.Renderer_Object, delta_time: f32) {
	if registry == nil || renderer == nil || renderer.Filament == nil { return }
	workspace_service := Find_Service(registry, "Workspace")
	if workspace_service == nil || workspace_service.object == nil { return }
	ctx := classes.Class_Step_Context{L = L, delta_time = delta_time, renderer = renderer}
	workspace_render_3d(workspace_service.object, &ctx)
}

Install :: proc(registry: ^Registry, vm_state: ^vm.VM) {
	registry.vm_state = vm_state
	model_object, model_ok := classes.Push_New(registry.classes, vm_state, "DataModel", false)
	assert(model_ok && model_object != nil)
	registry.data_model = cast(^DataModel)model_object
	registry.data_model.registry = registry
	classes.Set_Data_Model(registry.classes, registry.data_model)
	vm.Pop(vm_state.L)

	for service in registry.services {
		assert(Ensure_Service(registry, service.name) != nil)
	}
	workspace := cast(^Workspace)Ensure_Service(registry, "Workspace")
	camera, camera_ok := classes.Push_New(registry.classes, vm_state, "Camera")
	assert(camera_ok && camera != nil)
	classes.Set_Parent(camera, &workspace.object)
	workspace.current_camera = cast(^classes.Camera)camera
	if registry.classes.renderer != nil { registry.classes.renderer.ActiveCamera = camera }
	vm.Pop(vm_state.L)
	task_scheduler := Find_Service(registry, "TaskScheduler")
	assert(task_scheduler != nil && task_scheduler.object != nil)
	Install_Task_Library(cast(^TaskScheduler)task_scheduler.object, vm_state)

	classes.Push_Object(vm_state.L, &registry.data_model.object)
	vm.SetGlobalFromStack(vm_state, "game")

	// A protected service cannot safely be installed as a shared VM global:
	// globals are common to every Luau thread, regardless of its capabilities.
	for service in registry.services {
		if service.global_name != "" && vm.SecurityRequirementIsNone(service.security) {
			classes.Push_Object(vm_state.L, service.object)
			vm.SetGlobalFromStack(vm_state, service.global_name)
		}
	}
}

Registry_Destroy :: proc(registry: ^Registry) {
	if registry == nil {
		return
	}
	delete(registry.services)
	registry.services = nil
	registry.data_model = nil
	registry.vm_state = nil
}
