package services

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import debuglog "../debuglog"
import sdl3 "../platform"
import profiling "../profiling"
import signals "../signals"
import target "../target"
import tracy "../util/odin-tracy"
import vm "../vm"
import "core:fmt"

Service_Descriptor :: struct {
	name:         string,
	class_name:   string,
	global_name:  string,
	object:       ^classes.Object,
	constructing: bool,
	security:     vm.Security_Requirement,
}

Registry :: struct {
	classes:              ^classes.Registry,
	services:             [dynamic]Service_Descriptor,
	service_index:        map[string]int,
	data_model:           ^DataModel,
	vm_state:             ^vm.VM,
	signal_registry:      ^signals.Registry,
	mode:                 target.Mode,
	fast_editor_viewport: bool,
}

Registry_Init :: proc(
	class_registry: ^classes.Registry,
	signal_registry: ^signals.Registry = nil,
	mode: target.Mode = target.current_mode,
) -> Registry {
	return Registry {
		classes = class_registry,
		signal_registry = signal_registry,
		mode = mode,
		service_index = make(map[string]int),
	}
}

Register_Service :: proc(registry: ^Registry, name, class_name: string, global_name: string = "") {
	assert(registry != nil)
	assert(Find_Service(registry, name) == nil)


	registry.service_index[name] = len(registry.services)
	append(
		&registry.services,
		Service_Descriptor{name = name, class_name = class_name, global_name = global_name},
	)
}

Find_Service :: proc(registry: ^Registry, name: string) -> ^Service_Descriptor {
	if registry == nil {
		return nil
	}
	index, ok := registry.service_index[name]
	if !ok || index < 0 || index >= len(registry.services) {
		return nil
	}
	return &registry.services[index]
}


Unregister_Service :: proc(registry: ^Registry, name: string) {
	if registry == nil {
		return
	}
	index, ok := registry.service_index[name]
	if !ok || index < 0 || index >= len(registry.services) {
		return
	}

	ordered_remove(&registry.services, index)


	clear(&registry.service_index)
	for descriptor, position in registry.services {
		registry.service_index[descriptor.name] = position
	}
}

Set_Service_Security :: proc(
	registry: ^Registry,
	name: string,
	requirement: vm.Security_Requirement,
) -> bool {
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

Get_Service_For_Thread :: proc(
	registry: ^Registry,
	L: ^vm.State,
	name: string,
) -> (
	^classes.Object,
	bool,
) {
	descriptor := Find_Service(registry, name)
	if descriptor == nil || !Service_Access_Allowed(L, descriptor) {
		return nil, false
	}
	return Ensure_Service(registry, name), true
}

Ensure_Service :: proc(registry: ^Registry, name: string) -> ^classes.Object {
	descriptor := Find_Service(registry, name)
	if descriptor == nil || registry.vm_state == nil {return nil}
	if descriptor.object != nil {return descriptor.object}
	if descriptor.constructing {return nil}

	descriptor.constructing = true
	defer descriptor.constructing = false
	object, ok := classes.Push_New(
		registry.classes,
		registry.vm_state,
		descriptor.class_name,
		false,
	)
	if !ok || object == nil {return nil}
	classes.Set_Name(object, descriptor.name)
	object.security_requirement = descriptor.security
	descriptor.object = object
	classes.Set_Parent(object, &registry.data_model.object)
	vm.Pop(registry.vm_state.L)
	return object
}

MAP_CONTENT_SERVICES := [?]string {
	"Workspace",
	"ReplicatedFirst",
	"ReplicatedStorage",
	"Lighting",
	"SoundService",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
	"CharacterService",
	"ServerScriptService",
	"ServerStorage",
	"MaterialService",
	"Teams",
}

Map_Content_Service :: proc(name: string) -> bool {
	for candidate in MAP_CONTENT_SERVICES {
		if candidate == name {
			return true
		}
	}
	return false
}

Register_Default_Services :: proc(registry: ^Registry) {
	when #config(KINE_ANDROID, false) {
		debuglog.Log(
			fmt.tprintf(
				"Register_Default_Services: enter classes=%v registered=%d",
				registry.classes,
				classes.Class_Count(registry.classes),
			),
		)
	}

	Register_DataModel_Class(registry.classes)
	Register_Service_Class(registry.classes)
	when ODIN_OS != .JS {Register_AccountService_Class(registry.classes)}
	Register_Aerodynamics_Class(registry.classes)
	Register_AsepriteService_Class(registry.classes)
	Register_AssetService_Class(registry.classes)
	Register_ChangeHistoryService_Class(registry.classes)
	Register_CharacterService_Class(registry.classes)
	when ODIN_OS != .JS {Register_CollaborationService_Class(registry.classes)}
	Register_CollectionService_Class(registry.classes)
	when ODIN_OS != .JS {Register_ContentProvider_Class(registry.classes)}
	Register_ContextActionService_Class(registry.classes)
	when ODIN_OS != .JS {Register_DataStoreService_Class(registry.classes)}
	Register_Debris_Class(registry.classes)
	when ODIN_OS != .JS {Register_DialogService_Class(registry.classes)}
	when ODIN_OS != .JS {Register_DiscordRPC_Class(registry.classes)}
	when ODIN_OS != .JS {Register_EditorService_Class(registry.classes)}
	Register_EncodingService_Class(registry.classes)
	Register_ExampleService_Class(registry.classes)
	when ODIN_OS != .JS {Register_ExporterService_Class(registry.classes)}
	when ODIN_OS != .JS {Register_ExportService_Class(registry.classes)}
	when ODIN_OS != .JS {Register_Filesystem_Class(registry.classes)}
	Register_GuiService_Class(registry.classes)
	when ODIN_OS != .JS {Register_HttpService_Class(registry.classes)}
	Register_IconService_Class(registry.classes)
	Register_InsertService_Class(registry.classes)
	when ODIN_OS != .JS {Register_KinemiumService_Class(registry.classes)}
	Register_Lighting_Class(registry.classes)
	Register_LocalizationService_Class(registry.classes)
	Register_LogService_Class(registry.classes)
	Register_LuauService_Class(registry.classes)
	Register_MarketplaceService_Class(registry.classes)
	Register_MaterialService_Class(registry.classes)
	when ODIN_OS != .JS {Register_MatrixService_Class(registry.classes)}
	Register_MemoryStoreService_Class(registry.classes)
	Register_MessagingService_Class(registry.classes)
	Register_Mouse_Class(registry.classes)
	Register_NetworkEmulator_Class(registry.classes)
	when ODIN_OS != .JS {Register_Packages_Class(registry.classes)}
	Register_Path_Class(registry.classes)
	Register_PathfindingService_Class(registry.classes)
	Register_Pathtracer_Class(registry.classes)
	Register_Physics_Class(registry.classes)
	Register_PhysicsService_Class(registry.classes)
	Register_PlayerGui_Class(registry.classes)
	Register_Players_Class(registry.classes)
	Register_PlayerScripts_Class(registry.classes)
	when ODIN_OS != .JS {Register_PlaytestService_Class(registry.classes)}
	when ODIN_OS != .JS {Register_Plugin_Class(registry.classes)}
	when ODIN_OS != .JS {Register_PluginMarketplace_Class(registry.classes)}
	when ODIN_OS != .JS {Register_PluginLoader_Class(registry.classes)}
	when (ODIN_OS == .Linux ||
		ODIN_OS == .Darwin ||
		ODIN_OS == .Windows) && !#config(KINE_ANDROID, false) {
		if registry.mode == .Editor &&
		   target.IS_EDITOR {Register_TerminalService_Class(registry.classes)}
	}
	Register_ConsoleService_Class(registry.classes)
	Register_ProfilerService_Class(registry.classes)
	when ODIN_OS != .JS {Register_Project_Class(registry.classes)}
	Register_ReflectionService_Class(registry.classes)
	Register_ReplicatedFirst_Class(registry.classes)
	Register_ReplicatedStorage_Class(registry.classes)
	Register_ReplicatorService_Class(registry.classes)
	Register_RunService_Class(registry.classes)
	Register_ScriptContext_Class(registry.classes)
	Register_ScriptEditorService_Class(registry.classes)
	Register_Selection_Class(registry.classes)
	Register_SerializationService_Class(registry.classes)
	Register_ServerScriptService_Class(registry.classes)
	Register_ServerStorage_Class(registry.classes)
	Register_SoundService_Class(registry.classes)
	when ODIN_OS != .JS {Register_SpaceService_Class(registry.classes)}
	Register_StarterCharacterScripts_Class(registry.classes)
	Register_StarterGui_Class(registry.classes)
	Register_StarterPack_Class(registry.classes)
	Register_StarterPlayer_Class(registry.classes)
	Register_Stats_Class(registry.classes)
	Register_Studio_Class(registry.classes)
	Register_StudioService_Class(registry.classes)
	Register_StudioThemeService_Class(registry.classes)
	Register_TaskScheduler_Class(registry.classes)
	Register_Team_Class(registry.classes)
	Register_Teams_Class(registry.classes)
	Register_TeleportService_Class(registry.classes)
	when ODIN_OS != .JS {Register_TemplateService_Class(registry.classes)}
	Register_Terrain_Class(registry.classes)
	Register_TextChatService_Class(registry.classes)
	Register_TextService_Class(registry.classes)
	Register_Tween_Class(registry.classes)
	Register_TweenService_Class(registry.classes)
	when ODIN_OS != .JS {Register_UpdateService_Class(registry.classes)}
	Register_UserInputService_Class(registry.classes)
	Register_VRService_Class(registry.classes)
	Register_WebviewService_Class(registry.classes)
	Register_Window_Class(registry.classes)
	Register_Workspace_Class(registry.classes)
	Register_Workspace2D_Class(registry.classes)
	when ODIN_OS != .JS {Register_ZipService_Class(registry.classes)}


	when ODIN_OS != .JS {Register_Service(registry, "AccountService", "AccountService", "accountService")}
	Register_Service(registry, "Aerodynamics", "Aerodynamics")
	Register_Service(registry, "AsepriteService", "AsepriteService")
	Register_Service(registry, "AssetService", "AssetService")
	Register_Service(registry, "ChangeHistoryService", "ChangeHistoryService")
	Register_Service(registry, "CharacterService", "CharacterService")
	when ODIN_OS != .JS {Register_Service(registry, "CollaborationService", "CollaborationService")}
	Register_Service(registry, "CollectionService", "CollectionService", "CollectionService")
	when ODIN_OS != .JS {Register_Service(registry, "ContentProvider", "ContentProvider", "ContentProvider")}
	Register_Service(registry, "ContextActionService", "ContextActionService")
	when ODIN_OS != .JS {Register_Service(registry, "DataStoreService", "DataStoreService")}
	Register_Service(registry, "Debris", "Debris", "debris")
	when ODIN_OS != .JS {Register_Service(registry, "DialogService", "DialogService", "DialogService")}
	when ODIN_OS != .JS {Register_Service(registry, "DiscordRPC", "DiscordRPC")}
	when ODIN_OS != .JS {Register_Service(registry, "EditorService", "EditorService", "EditorService")}
	Register_Service(registry, "EncodingService", "EncodingService", "EncodingService")
	Register_Service(registry, "ExampleService", "ExampleService")
	when ODIN_OS != .JS {Register_Service(registry, "ExporterService", "ExporterService", "ExporterService")}
	when ODIN_OS != .JS {Register_Service(registry, "ExportService", "ExportService", "ExportService")}
	when ODIN_OS != .JS {Register_Service(registry, "Filesystem", "Filesystem", "Filesystem")}
	Register_Service(registry, "GuiService", "GuiService")
	when ODIN_OS != .JS {Register_Service(registry, "HttpService", "HttpService")}
	Register_Service(registry, "IconService", "IconService")
	Register_Service(registry, "InsertService", "InsertService")
	when ODIN_OS != .JS {Register_Service(registry, "KinemiumService", "KinemiumService")}
	Register_Service(registry, "Lighting", "Lighting")
	Register_Service(registry, "LocalizationService", "LocalizationService", "LocalizationService")
	Register_Service(registry, "LogService", "LogService")
	Register_Service(registry, "LuauService", "LuauService")
	Register_Service(registry, "MarketplaceService", "MarketplaceService", "marketplaceService")
	Register_Service(registry, "MaterialService", "MaterialService")
	when ODIN_OS != .JS {Register_Service(registry, "MatrixService", "MatrixService")}
	Register_Service(registry, "MemoryStoreService", "MemoryStoreService", "memoryStoreService")
	Register_Service(registry, "MessagingService", "MessagingService", "messagingService")
	when ODIN_OS != .JS {Register_Service(registry, "Packages", "Packages")}
	Register_Service(registry, "PathfindingService", "PathfindingService")
	Register_Service(registry, "Pathtracer", "Pathtracer", "Pathtracer")
	Register_Service(registry, "Physics", "Physics")
	Register_Service(registry, "PhysicsService", "PhysicsService")
	Register_Service(registry, "Players", "Players")
	when ODIN_OS != .JS {Register_Service(registry, "PlaytestService", "PlaytestService")}
	when ODIN_OS != .JS {Register_Service(registry, "Plugin", "Plugin", "plugin")}
	when ODIN_OS != .JS {Register_Service(registry, "PluginMarketplace", "PluginMarketplace", "PluginMarketplace")}
	when ODIN_OS != .JS {Register_Service(registry, "PluginLoader", "PluginLoader")}
	when (ODIN_OS == .Linux ||
		ODIN_OS == .Darwin ||
		ODIN_OS == .Windows) && !#config(KINE_ANDROID, false) {
		if registry.mode == .Editor && target.IS_EDITOR {
			Register_Service(registry, "TerminalService", "TerminalService")
			assert(
				Set_Service_Security(
					registry,
					"TerminalService",
					vm.SecurityRequirementFromValue(
						datatypes.SECURITY_CAPABILITY_INTERNAL_TERMINAL,
					),
				),
			)
		}
	}
	Register_Service(registry, "ConsoleService", "ConsoleService")
	Register_Service(registry, "ProfilerService", "ProfilerService")
	when ODIN_OS != .JS {Register_Service(registry, "Project", "Project")}
	Register_Service(registry, "ReflectionService", "ReflectionService", "ReflectionService")
	Register_Service(registry, "ReplicatedFirst", "ReplicatedFirst", "ReplicatedFirst")
	Register_Service(registry, "ReplicatedStorage", "ReplicatedStorage", "ReplicatedStorage")
	Register_Service(registry, "ReplicatorService", "ReplicatorService")
	Register_Service(registry, "RunService", "RunService")
	Register_Service(registry, "ScriptContext", "ScriptContext")
	Register_Service(registry, "ScriptEditorService", "ScriptEditorService")
	Register_Service(registry, "Selection", "Selection", "Selection")
	Register_Service(registry, "SerializationService", "SerializationService")
	Register_Service(registry, "ServerScriptService", "ServerScriptService", "ServerScriptService")
	Register_Service(registry, "ServerStorage", "ServerStorage", "ServerStorage")
	Register_Service(registry, "SoundService", "SoundService", "SoundService")
	when ODIN_OS != .JS {Register_Service(registry, "SpaceService", "SpaceService")}
	Register_Service(registry, "StarterGui", "StarterGui")
	Register_Service(registry, "StarterPack", "StarterPack", "StarterPack")
	Register_Service(registry, "StarterPlayer", "StarterPlayer", "StarterPlayer")
	Register_Service(registry, "Stats", "Stats")
	Register_Service(registry, "Studio", "Studio")
	Register_Service(registry, "StudioService", "StudioService")
	Register_Service(registry, "StudioThemeService", "StudioThemeService")
	Register_Service(registry, "TaskScheduler", "TaskScheduler")
	Register_Service(registry, "Teams", "Teams", "team")
	Register_Service(registry, "TeleportService", "TeleportService", "teleportService")
	when ODIN_OS != .JS {Register_Service(registry, "TemplateService", "TemplateService")}
	Register_Service(registry, "Terrain", "Terrain")
	Register_Service(registry, "TextChatService", "TextChatService")
	Register_Service(registry, "TextService", "TextService")
	Register_Service(registry, "TweenService", "TweenService", "TweenService")
	when ODIN_OS != .JS {Register_Service(registry, "UpdateService", "UpdateService")}
	Register_Service(registry, "UserInputService", "UserInputService")
	Register_Service(registry, "VRService", "VRService")
	Register_Service(registry, "WebviewService", "WebviewService")
	Register_Service(registry, "Window", "Window")
	Register_Service(registry, "Workspace", "Workspace", "workspace")
	Register_Service(registry, "Workspace2D", "Workspace2D")
	when ODIN_OS != .JS {Register_Service(registry, "ZipService", "ZipService")}


	when ODIN_OS == .JS {
		Register_Web_Service_Classes(registry.classes)
		Register_Web_Services(registry)
	}
	when #config(KINE_ANDROID, false) {
		debuglog.Log(
			fmt.tprintf(
				"Register_Default_Services: classes=%d services=%d",
				classes.Class_Count(registry.classes),
				len(registry.services),
			),
		)
	}
	Register_Service(registry, "CoreGui", "StarterGui")

	assert(
		Set_Service_Security(
			registry,
			"ScriptContext",
			vm.SecurityRequirementFromValue(datatypes.SECURITY_CAPABILITY_INTERNAL_SCRIPT_CONTEXT),
		),
	)
	when ODIN_OS != .JS {
		assert(
			Set_Service_Security(
				registry,
				"PlaytestService",
				vm.SecurityRequirementFromValue(
					datatypes.SECURITY_CAPABILITY_INTERNAL_STUDIO_ACCESS,
				),
			),
		)
		assert(
			Set_Service_Security(
				registry,
				"ExportService",
				vm.SecurityRequirementFromValue(
					datatypes.SECURITY_CAPABILITY_INTERNAL_STUDIO_ACCESS,
				),
			),
		)
	}
}

Render_Step :: proc(registry: ^Registry, L: ^vm.State, delta_time: f32) {
	when (ODIN_OS == .Linux ||
		ODIN_OS == .Darwin ||
		ODIN_OS == .Windows) && !#config(KINE_ANDROID, false) {
		if registry.mode == .Editor && target.IS_EDITOR {Terminal_Service_Step(registry)}
	}
	{
		when ODIN_OS != .JS {
			tracy.ZoneNC("Project Autosave", 0xD19A66)
			Project_Autosave(registry, L, delta_time)
		}
	}
	if workspace := Find_Service(registry, "Workspace");
	   workspace != nil && workspace.object != nil {
		(cast(^Workspace)workspace.object).water_time += f64(max(delta_time, 0))
	}
	Install_Part_Body_Access(registry)
	{
		replicator := Find_Service(registry, "ReplicatorService")
		if replicator != nil && replicator.object != nil {
			Replication_Step(cast(^ReplicatorService)replicator.object, L, delta_time)
		}
	}
	{
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
			service := cast(^UserInputService)user_input.object
			User_Input_Begin_Frame(service)
			Mouse_Begin_Frame(service.mouse, L, delta_time)
		}
	}
	{
		tracy.ZoneNC("Physics Step", 0xE06C75)
		z := profiling.Begin("Physics Step", 0xE06C75)
		if run_service := Find_Service(registry, "RunService");
		   run_service != nil && run_service.object != nil {
			Run_Service_Stepped(cast(^RunService)run_service.object, L, delta_time)
		}
		workspace := Find_Service(registry, "Workspace")
		world2d := Find_Service(registry, "Workspace2D")
		is_2d :=
			workspace != nil &&
			workspace.object != nil &&
			(cast(^Workspace)workspace.object).dimension == .D2
		if is_2d && world2d != nil && world2d.object == nil {
			_ = DataModel_Get_Service(registry.data_model, "Workspace2D")
			world2d = Find_Service(registry, "Workspace2D")
		}
		if world2d != nil && world2d.object != nil {
			world := cast(^Workspace2D)world2d.object
			if is_2d {
				Workspace2D_Step(world, cast(^Workspace)workspace.object, delta_time)
			} else {
				Workspace2D_Clear(world)
			}
		}
		if !is_2d {
			physics := Find_Service(registry, "Physics")
			if physics != nil && physics.object != nil {
				Physics_Step(cast(^Physics)physics.object, delta_time)
			}
		}
		if registry.classes.renderer != nil {
			ParticleEmitter_Physics_Step(registry, delta_time)
		}
		if run_service := Find_Service(registry, "RunService");
		   run_service != nil && run_service.object != nil {
			Run_Service_Post_Simulation(cast(^RunService)run_service.object, L, delta_time)
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
	when ODIN_OS != .JS {
		if service := Find_Service(registry, "HttpService");
		   service != nil && service.object != nil {
			http_service_step_web_streams(cast(^HttpService)service.object, L)
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
	{
		tracy.ZoneNC("RunService RenderStepped", 0x98C379)
		z := profiling.Begin("RunService RenderStepped", 0x98C379)
		run_service := Find_Service(registry, "RunService")
		if run_service != nil && run_service.object != nil {
			Run_Service_Render_Step(cast(^RunService)run_service.object, L, delta_time)
		}
	}
	when ODIN_OS != .JS {
		matrix_service := Find_Service(registry, "MatrixService")
		if matrix_service != nil && matrix_service.object != nil {
			Matrix_Service_Step(cast(^MatrixService)matrix_service.object, L, f64(delta_time))
		}
	}
}

Set_Event :: proc(registry: ^Registry, L: ^vm.State, event: sdl3.Event) {
	Console_Handle_Event(registry, event)
	user_input_service := Find_Service(registry, "UserInputService")
	if user_input_service != nil && user_input_service.object != nil {
		user_input_service_step(cast(^UserInputService)user_input_service.object, L, event)
	}
}

Prepare_3D :: proc(registry: ^Registry, renderer: ^classes.Renderer_Object) {
	if registry == nil || renderer == nil || renderer.Filament == nil {return}
	if workspace := Find_Service(registry, "Workspace");
	   workspace != nil && workspace.object != nil {
		ws := cast(^Workspace)workspace.object
		renderer.RenderFilament = ws.dimension == .D3 && ws.enable_3d
		if !renderer.RenderFilament {return}
	}
	{
		tracy.ZoneNC("Lighting Apply", 0xC586C0)
		z := profiling.Begin("Lighting Apply", 0xC586C0)
		lighting := Find_Service(registry, "Lighting")
		if lighting != nil && lighting.object != nil {
			Lighting_Apply(
				cast(^Lighting)lighting.object,
				renderer,
				registry.fast_editor_viewport && registry.mode == .Editor,
			)
		}
	}

	tracer := cast(^Pathtracer)Find_Service(registry, "Pathtracer").object
	if tracer != nil {
		Pathtracer_Prepare_3D(tracer, renderer)
	}
	workspace_service := Find_Service(registry, "Workspace")
	terrain_service := Find_Service(registry, "Terrain")
	if workspace_service == nil || workspace_service.object == nil {return}
	if terrain_service == nil || terrain_service.object == nil {return}
	workspace_prepare_3d(cast(^Workspace)workspace_service.object, renderer)
	{
		tracy.ZoneNC("Water Prepare 3D", 0xC678DD)
		water_params := Water_Parameters(registry.data_model)
		kineffi.Kine_Filament_SetWaterTime(renderer.Filament, Water_Time(registry.data_model))
		kineffi.Kine_Filament_SetWaterParams(renderer.Filament, &water_params)
	}
	Terrain_Prepare_3D(cast(^Terrain)terrain_service.object, renderer)
}

Render_3D :: proc(
	registry: ^Registry,
	L: ^vm.State,
	renderer: ^classes.Renderer_Object,
	delta_time: f32,
) {
	if registry == nil || renderer == nil || renderer.Filament == nil {return}
	workspace_service := Find_Service(registry, "Workspace")
	terrain_service := Find_Service(registry, "Terrain")
	if workspace_service == nil || workspace_service.object == nil {return}
	ws := cast(^Workspace)workspace_service.object
	renderer.RenderFilament = ws.dimension == .D3 && ws.enable_3d
	if !renderer.RenderFilament {return}
	ctx := classes.Class_Step_Context {
		L          = L,
		delta_time = delta_time,
		renderer   = renderer,
	}
	if terrain_service != nil && terrain_service.object != nil {
		Terrain_Render_3D(cast(^Terrain)terrain_service.object, ctx.renderer)
	}
	workspace_render(workspace_service.object, &ctx)
	classes.ParticleEmitter_Render(registry.classes, renderer)
}

Resize :: proc(registry: ^Registry, datatype_registry: ^datatypes.Registry, width, height: i32) {
	if registry == nil ||
	   registry.vm_state == nil ||
	   registry.vm_state.L == nil ||
	   datatype_registry == nil {
		return
	}

	scale := sdl3.UI_Scale
	safe_w := f32(width) - sdl3.UI_Safe_Left - sdl3.UI_Safe_Right
	safe_h := f32(height) - sdl3.UI_Safe_Top - sdl3.UI_Safe_Bottom
	layout_width := max(i32(safe_w / scale), 1)
	layout_height := max(i32(safe_h / scale), 1)

	StudioThemeService_Update_Layout(
		registry,
		registry.vm_state.L,
		datatype_registry,
		layout_width,
		layout_height,
	)
}

Install :: proc(registry: ^Registry, vm_state: ^vm.VM) {
	when #config(KINE_ANDROID, false) {
		debuglog.Log(
			fmt.tprintf(
				"services.Install: begin classes=%d services=%d mode=%v",
				classes.Class_Count(registry.classes),
				len(registry.services),
				registry.mode,
			),
		)
	}
	registry.vm_state = vm_state
	registry.classes.destroy_hook = services_destroy_hook
	registry.classes.destroy_hook_ctx = registry
	registry.classes.screen_gui_can_display = PlayerGui_Can_Display
	registry.classes.localize_text = localization_render_text
	model_object, model_ok := classes.Push_New(registry.classes, vm_state, "DataModel", false)
	assert(model_ok && model_object != nil)
	registry.data_model = cast(^DataModel)model_object
	registry.data_model.registry = registry
	classes.Set_Data_Model(registry.classes, registry.data_model)


	classes.Set_Mode(registry.classes, registry.mode)


	classes.Set_Network_Ownership(
		registry.classes,
		network_ownership_namecall,
		registry.data_model,
	)
	classes.Set_Remote_Call(registry.classes, remote_call_dispatch, registry.data_model)
	registry.classes.model_pivoted = replication_model_pivoted
	registry.classes.camera_obstruction = camera_resolve_obstruction
	vm.Pop(vm_state.L)

	for service in registry.services {
		assert(Ensure_Service(registry, service.name) != nil)
	}
	workspace := cast(^Workspace)Ensure_Service(registry, "Workspace")
	camera, camera_ok := classes.Push_New(registry.classes, vm_state, "Camera")
	assert(camera_ok && camera != nil)
	classes.Set_Parent(camera, &workspace.object)
	workspace.current_camera = cast(^classes.Camera)camera
	if registry.classes.renderer != nil {registry.classes.renderer.ActiveCamera = camera}
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


	profiling.install_thread_hooks(vm_state.L)
	Register_ProfilerOverlay(registry, vm_state)
	Register_ConsoleOverlay(registry, vm_state)
}

Registry_Destroy :: proc(registry: ^Registry) {
	if registry == nil {
		return
	}
	if service := Find_Service(registry, "Workspace2D"); service != nil && service.object != nil {
		Workspace2D_Clear(cast(^Workspace2D)service.object)
	}
	{
		replicator := Find_Service(registry, "ReplicatorService")
		if registry.vm_state != nil &&
		   registry.vm_state.L != nil &&
		   replicator != nil &&
		   replicator.object != nil {
			replication_stop(cast(^ReplicatorService)replicator.object)
		}
	}
	delete(registry.services)
	registry.services = nil
	delete(registry.service_index)
	registry.service_index = nil
	registry.data_model = nil
	registry.vm_state = nil
}


services_destroy_hook :: proc(object: ^classes.Object, ctx: rawptr) {
	if object == nil || ctx == nil {
		return
	}
	registry := cast(^Registry)ctx
	if classes.Is_A_Class(object, &classes.Part_Class) {

		if descriptor := classes.Find_Class(registry.classes, "WeldConstraint");
		   descriptor != nil {
			for instance in descriptor.instances {
				if instance == nil {continue}
				weld := cast(^classes.WeldConstraint)instance
				if weld.part0 != object && weld.part1 != object {continue}
				if weld.part0 == object {weld.part0 = nil}
				if weld.part1 == object {weld.part1 = nil}
				classes.WeldConstraint_release(weld)
			}
		}
		if descriptor := Find_Service(registry, "Physics");
		   descriptor != nil && descriptor.object != nil {
			physics_forget_part(cast(^Physics)descriptor.object, cast(^classes.Part)object)
		}
	}
	if object.class == &classes.Attachment_Class {
		for descriptor in registry.classes.classes {
			if descriptor == nil ||
			   !classes.Is_Class_A(descriptor.info, &classes.Constraint_Class) {continue}
			for instance in descriptor.instances {
				if instance == nil {continue}
				constraint := cast(^classes.Constraint)instance
				if constraint.attachment0 != object && constraint.attachment1 != object {continue}
				if constraint.attachment0 == object {constraint.attachment0 = nil}
				if constraint.attachment1 == object {constraint.attachment1 = nil}
				switch instance.class {
				case &classes.HingeConstraint_Class:
					classes.HingeConstraint_release(cast(^classes.HingeConstraint)instance)
				case &classes.SpringConstraint_Class:
					classes.SpringConstraint_release(cast(^classes.SpringConstraint)instance)
				case &classes.RopeConstraint_Class:
					classes.RopeConstraint_release(cast(^classes.RopeConstraint)instance)
				case:
					if classes.Is_Attachment_Joint(instance.class) {
						classes.Attachment_Joint_release(cast(^classes.Attachment_Joint)instance)
					}
				}
			}
		}
	}
	for &descriptor in registry.services {
		if descriptor.object == object {descriptor.object = nil; break}
	}


	if classes.Script_Is_Script(object) {
		descriptor := Find_Service(registry, "ScriptContext")
		if descriptor != nil && descriptor.object != nil {
			script_context := cast(^ScriptContext)descriptor.object
			if !script_context.destroyed {
				ScriptContext_Forget_Script(script_context, object)
			}
		}
	}


	{
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
