package services

import "core:fmt"
import sdl3 "../platform"
import classes "../classes"
import datatypes "../datatypes"
import signals "../signals"
import vm "../vm"
import tracy "../util/odin-tracy"
import profiling "../profiling"

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

Registry_Init :: proc(
	class_registry: ^classes.Registry,
	signal_registry: ^signals.Registry = nil,
) -> Registry {
	return Registry{
		classes = class_registry,
		signal_registry = signal_registry,
	}
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
	Register_CharacterService_Class(registry.classes)
	Register_CollectionService_Class(registry.classes)
	Register_ContentProvider_Class(registry.classes)
	Register_DialogService_Class(registry.classes)
	Register_EditorService_Class(registry.classes)
	Register_ExampleService_Class(registry.classes)
	Register_HttpService_Class(registry.classes)
	Register_Lighting_Class(registry.classes)
	Register_LocalizationService_Class(registry.classes)
	Register_LogService_Class(registry.classes)
	Register_NetworkEmulator_Class(registry.classes)
	Register_Physics_Class(registry.classes)
	Register_Players_Class(registry.classes)
	Register_Plugin_Class(registry.classes)
	Register_PluginMarketplace_Class(registry.classes)
	Register_ProfilerService_Class(registry.classes)
	Register_Project_Class(registry.classes)
	Register_ReplicatedFirst_Class(registry.classes)
	Register_ReplicatedStorage_Class(registry.classes)
	Register_ReplicatorService_Class(registry.classes)
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
	Register_TextService_Class(registry.classes)
	Register_Tween_Class(registry.classes)
	Register_TweenService_Class(registry.classes)
	Register_UserInputService_Class(registry.classes)
	Register_Workspace_Class(registry.classes)
	// wire:end service-classes
	// wire:begin services
	Register_Service(registry, "CharacterService", "CharacterService")
	Register_Service(registry, "CollectionService", "CollectionService", "CollectionService")
	Register_Service(registry, "ContentProvider", "ContentProvider", "ContentProvider")
	Register_Service(registry, "DialogService", "DialogService")
	Register_Service(registry, "EditorService", "EditorService", "EditorService")
	Register_Service(registry, "ExampleService", "ExampleService", "exampleService")
	Register_Service(registry, "HttpService", "HttpService")
	Register_Service(registry, "Lighting", "Lighting", "Lighting")
	Register_Service(registry, "LocalizationService", "LocalizationService", "LocalizationService")
	Register_Service(registry, "LogService", "LogService")
	Register_Service(registry, "Physics", "Physics")
	Register_Service(registry, "Players", "Players")
	Register_Service(registry, "Plugin", "Plugin", "Plugin")
	Register_Service(registry, "PluginMarketplace", "PluginMarketplace")
	Register_Service(registry, "ProfilerService", "ProfilerService", "profilerService")
	Register_Service(registry, "Project", "Project")
	Register_Service(registry, "ReplicatedFirst", "ReplicatedFirst", "ReplicatedFirst")
	Register_Service(registry, "ReplicatedStorage", "ReplicatedStorage", "ReplicatedStorage")
	Register_Service(registry, "ReplicatorService", "ReplicatorService")
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
	Register_Service(registry, "TextService", "TextService", "TextService")
	Register_Service(registry, "TweenService", "TweenService")
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
	when ODIN_OS != .JS {
		replicator := Find_Service(registry, "ReplicatorService")
		if replicator != nil && replicator.object != nil {
			Replication_Step(cast(^ReplicatorService)replicator.object, L, delta_time)
		}
	}
	when ODIN_OS != .JS {
		character_service := Find_Service(registry, "CharacterService")
		if character_service != nil && character_service.object != nil {
			CharacterService_Step(cast(^CharacterService)character_service.object, delta_time)
		}
	}
	{
		tracy.ZoneNC("User Input BeginFrame", 0x56B6C2)
		z := profiling.Begin("User Input BeginFrame", 0x56B6C2)
		user_input := Find_Service(registry, "UserInputService")
		if user_input != nil && user_input.object != nil {
			User_Input_Begin_Frame(cast(^UserInputService)user_input.object)
		}
	}
	{
		tracy.ZoneNC("Physics Step", 0xE06C75)
		z := profiling.Begin("Physics Step", 0xE06C75)
		physics := Find_Service(registry, "Physics")
		if physics != nil && physics.object != nil {
			Physics_Step(cast(^Physics)physics.object, delta_time)
		}
	}
	{
		tracy.ZoneNC("TaskScheduler Step", 0xD19A66)
		z := profiling.Begin("TaskScheduler Step", 0xD19A66)
		task_scheduler := Find_Service(registry, "TaskScheduler")
		if task_scheduler != nil && task_scheduler.object != nil {
			Task_Scheduler_Step(cast(^TaskScheduler)task_scheduler.object, delta_time)
		}
	}
	{
		tracy.ZoneNC("RunService Heartbeat", 0xE5C07B)
		z := profiling.Begin("RunService Heartbeat", 0xE5C07B)
		run_service := Find_Service(registry, "RunService")
		if run_service != nil && run_service.object != nil {
			Run_Service_Heartbeat(cast(^RunService)run_service.object, L, delta_time)
		}
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
	{
		tracy.ZoneNC("Lighting Apply", 0xC586C0)
		z := profiling.Begin("Lighting Apply", 0xC586C0)
		lighting := Find_Service(registry, "Lighting")
		if lighting != nil && lighting.object != nil { Lighting_Apply(cast(^Lighting)lighting.object, renderer) }
	}
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

Resize :: proc(
    registry: ^Registry,
    datatype_registry: ^datatypes.Registry,
    width, height: i32,
) {
    if registry == nil ||
       registry.vm_state == nil ||
       registry.vm_state.L == nil ||
       datatype_registry == nil {
        return
    }

    StudioThemeService_Update_Layout(
        registry,
        registry.vm_state.L,
        datatype_registry,
        width,
        height,
    )
}

Install :: proc(registry: ^Registry, vm_state: ^vm.VM) {
	registry.vm_state = vm_state
	registry.classes.destroy_hook = services_destroy_hook
	registry.classes.destroy_hook_ctx = registry
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

	for service in registry.services {
		if service.global_name != "" && vm.SecurityRequirementIsNone(service.security) {
			classes.Push_Object(vm_state.L, service.object)
			vm.SetGlobalFromStack(vm_state, service.global_name)
		}
	}
	Install_Log_Globals(registry, vm_state)
	Register_ProfilerOverlay(registry, vm_state)
}

Registry_Destroy :: proc(registry: ^Registry) {
	if registry == nil {
		return
	}
	when ODIN_OS != .JS {
		replicator := Find_Service(registry, "ReplicatorService")
		if registry.vm_state != nil && registry.vm_state.L != nil && replicator != nil && replicator.object != nil {
			replication_stop(cast(^ReplicatorService)replicator.object)
		}
	}
	delete(registry.services)
	registry.services = nil
	registry.data_model = nil
	registry.vm_state = nil
}

// services_destroy_hook runs right before a destroyed Instance's native memory
// is freed. Services drop their references to the object here so they never
// read a dangling pointer afterwards.
services_destroy_hook :: proc(object: ^classes.Object, ctx: rawptr) {
	if object == nil || ctx == nil {
		return
	}
	registry := cast(^Registry)ctx
	for &descriptor in registry.services {
		if descriptor.object == object { descriptor.object = nil; break }
	}
	when ODIN_OS != .JS {
		replicator := Find_Service(registry, "ReplicatorService")
		if replicator != nil && replicator.object != nil {
			replication_forget_destroyed(cast(^ReplicatorService)replicator.object, object)
		}
	}

	selection := Find_Service(registry, "Selection")
	if selection != nil && selection.object != nil {
		sel := cast(^Selection)selection.object
		for index := len(sel.selected) - 1; index >= 0; index -= 1 {
			if sel.selected[index] == object {
				ordered_remove(&sel.selected, index)
			}
		}
	}

	workspace_service := Find_Service(registry, "Workspace")
	if workspace_service != nil && workspace_service.object != nil {
		workspace := cast(^Workspace)workspace_service.object
		if workspace.current_camera == object {
			workspace.current_camera = nil
		}
	}
}
