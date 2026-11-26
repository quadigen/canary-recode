#+build !js
package main

import tracy "./engine/util/odin-tracy"
import sandbox "./sandboxed"
import "core:fmt"
import "core:os"
import "core:time"
import audio "engine/audio"
import classes "engine/classes"
import extensions "engine/extensions"
import sdl3 "engine/platform"
import profiling "engine/profiling"
import renderer "engine/renderer"
import engine_runtime "engine/runtime"
import services "engine/services"
import target "engine/target"
import vm "engine/vm"
import native_sdl "vendor:sdl3"

Runtime_Render_Context :: struct {
	environment:       ^engine_runtime.Environment,
	vm_state:          ^vm.VM,
	playtest_tree_dir: string,
}

runtime_update_step :: proc(user_data: rawptr, delta_time: f32) {
	ctx := cast(^Runtime_Render_Context)user_data
	if ctx == nil {
		return
	}
	services.Playtest_Tree_Pump(ctx.playtest_tree_dir, &ctx.environment.services, ctx.vm_state.L)
	if !services.Log_Is_Playtest_Paused() {
		engine_runtime.Environment_Update_Step(ctx.environment, ctx.vm_state, delta_time)
		if extensions.Game_Exit_Requested(&ctx.environment.extensions) {
			event := native_sdl.Event{}
			event.type = .QUIT
			_ = native_sdl.PushEvent(&event)
		}
	}
}

runtime_render_3d :: proc(
	user_data: rawptr,
	filament: ^renderer.Filament_Context,
	delta_time: f32,
) {
	ctx := cast(^Runtime_Render_Context)user_data
	if ctx == nil {return}
	engine_runtime.Environment_Render_3D(ctx.environment, ctx.vm_state, delta_time)
}

runtime_resize :: proc(user_data: rawptr, width, height: i32) {
	ctx := cast(^Runtime_Render_Context)user_data

	if ctx == nil || ctx.environment == nil {
		return
	}

	services.Resize(&ctx.environment.services, &ctx.environment.datatypes, width, height)
}

last_ui_width: i32 = -1
last_ui_height: i32 = -1

runtime_background_playtest :: proc(user_data: rawptr) -> bool {
	ctx := cast(^Runtime_Render_Context)user_data
	if ctx == nil || ctx.environment == nil {return false}
	descriptor := services.Find_Service(&ctx.environment.services, "PlaytestService")
	if descriptor == nil || descriptor.object == nil {return false}
	service := cast(^services.PlaytestService)descriptor.object
	return service.running && service.client_process.pid != 0
}

runtime_render_3d_dirty :: proc(user_data: rawptr) -> bool {
	ctx := cast(^Runtime_Render_Context)user_data
	if ctx == nil {return true}
	return engine_runtime.Environment_3D_Dirty(ctx.environment)
}

runtime_render_2d :: proc(
	user_data: rawptr,
	surface: ^renderer.Skia_Surface,
	width, height: i32,
	delta_time: f32,
) {
	if width != last_ui_width || height != last_ui_height {
		last_ui_width = width
		last_ui_height = height
	}

	ctx := cast(^Runtime_Render_Context)user_data
	if ctx == nil {return}
	engine_runtime.Environment_Render_2D(
		ctx.environment,
		ctx.vm_state,
		surface,
		width,
		height,
		delta_time,
	)
}

runtime_global_settings :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	registry := cast(^services.Registry)vm.UpvaluePointer(L)
	if registry == nil || registry.data_model == nil {
		vm.PushNil(L)
		return 1
	}
	classes.Push_Object(L, &registry.data_model.object)
	return 1
}

runtime_render_overlay :: proc(
	user_data: rawptr,
	surface: ^renderer.Skia_Surface,
	width, height: i32,
	delta_time: f32,
) {
	ctx := cast(^Runtime_Render_Context)user_data
	if ctx == nil {return}
	engine_runtime.Environment_Render_Overlay(
		ctx.environment,
		ctx.vm_state,
		surface,
		width,
		height,
		delta_time,
	)
}

runtime_render_vr_ui :: proc(
	user_data: rawptr,
	surface: ^renderer.Skia_Surface,
	width, height, panel_width, panel_height: i32,
) {
	ctx := cast(^Runtime_Render_Context)user_data
	if ctx == nil {return}
	engine_runtime.Environment_Update_VR_Pointer(
		ctx.environment,
		ctx.vm_state,
		width,
		height,
		surface != nil,
	)
	if surface == nil {return}
	engine_runtime.Environment_Render_VR_UI(
		ctx.environment,
		ctx.vm_state,
		surface,
		width,
		height,
		panel_width,
		panel_height,
	)
}

runtime_frame_maintenance :: proc(user_data: rawptr, budget_ns: u64) {
	ctx := cast(^Runtime_Render_Context)user_data
	if ctx == nil || ctx.vm_state == nil || services.Log_Is_Playtest_Paused() {return}
	z := profiling.Begin("Luau GC Maintenance", 0xB48EAD)
	_ = vm.GC_Step_Budgeted(ctx.vm_state.L, budget_ns)
}

runtime_overlay_needs_backdrop :: proc(user_data: rawptr) -> bool {
	ctx := cast(^Runtime_Render_Context)user_data
	return(
		ctx != nil &&
		ctx.environment != nil &&
		classes.Gui_Overlay_Needs_Backdrop(&ctx.environment.classes) \
	)
}

runtime_input_event :: proc(user_data: rawptr, event: sdl3.Event) {
	ctx := cast(^Runtime_Render_Context)user_data
	if ctx == nil {return}
	if services.Log_Is_Playtest_Paused() {
		if event.type == .KEY_DOWN && event.key.scancode == .F6 {
			services.Log_Resume_Playtest()
		}
		return
	}
	if !target.is_editor() || services.Studio_Keyboard_Shortcuts(&ctx.environment.services) {
		profiling.trigger_event(event)
	}
	engine_runtime.Environment_SetEvent(ctx.environment, ctx.vm_state, event)
}

run_desktop :: proc(options: Startup_Options) -> bool {
	tracy.SetThreadName("Main")
	startup_started := time.tick_now()
	if target.is_client() && !options.standalone {
		if !options.playtest && (options.address == "" || options.address == "0.0.0.0") {
			fmt.eprintln(
				"Network client needs a reachable server address; use 127.0.0.1 for a server on this computer",
			)
			return false
		}
		if options.map_path != "" && !options.playtest {
			fmt.eprintln(
				"Load the map on the server with --map; clients receive it through replication",
			)
			return false
		}
	}
	script_vm := vm.New()
	services.Log_Pause_On_Playtest_Error(options.playtest && options.pause_on_error)
	if !audio.init() {
		return false
	}
	defer audio.shutdown()

	environment: engine_runtime.Environment
	render_context := Runtime_Render_Context {
		environment       = &environment,
		vm_state          = &script_vm,
		playtest_tree_dir = options.playtest_tree_dir,
	}

	renderer_object := renderer.RendererObject {
		Step = runtime_update_step,
		Draw3D = runtime_render_3d,
		Draw2D = runtime_render_2d,
		DrawOverlay = runtime_render_overlay,
		DrawVRUI = runtime_render_vr_ui,
		UserData = &render_context,
		RenderFilament = true,
		KeyDown = proc(scancode: sdl3.Scancode) {
		},
		KeyUp = proc(scancode: sdl3.Scancode) {
		},
		MouseClick = proc(button: sdl3.MouseButtonEvent) {
		},
		OnClose = proc(user_data: rawptr) {
			render_context := cast(^Runtime_Render_Context)user_data
			if render_context.vm_state.L == nil {return}
			services.Project_Autosave(
				&render_context.environment.services,
				render_context.vm_state.L,
				closing = true,
			)
			services.data_model_runclose(
				render_context.vm_state.L,
				render_context.environment.services.data_model,
			)
			extensions.Game_Unload(&render_context.environment.extensions)
			vm.Close(render_context.vm_state)
		},
		CanClose = proc(user_data: rawptr) -> bool {
			ctx := cast(^Runtime_Render_Context)user_data
			return services.Project_Request_Window_Close(&ctx.environment.services, ctx.vm_state.L)
		},
		OnResize = runtime_resize,
		OnEvent = runtime_input_event,
	}
	when !renderer.KINE_RENDERER_GL {
		renderer_object.Cache2D = true
		renderer_object.Render3DCheck = runtime_render_3d_dirty
		renderer_object.BackgroundPlaytest = runtime_background_playtest
		renderer_object.OverlayNeedsBackdrop = runtime_overlay_needs_backdrop
		if !target.is_editor() && os.get_env("KINE_GC_PACING", context.temp_allocator) == "1" {
			renderer_object.FrameMaintenance = runtime_frame_maintenance
		}
	}

	target.set_playtest(options.playtest)
	vm.AddGlobal_Boolean(&script_vm, "IsPlaytest", options.playtest)
	vm.AddGlobal_String(&script_vm, "ProjectPath", options.project)
	vm.PushLightUserdata(script_vm.L, &environment.services)
	vm.PushFunction(script_vm.L, "settings", runtime_global_settings, 1)
	vm.SetGlobalFromStack(&script_vm, "settings")

	fmt.eprintf(
		"[Startup] VM and audio: %.1f ms\n",
		time.duration_milliseconds(time.tick_since(startup_started)),
	)
	if options.standalone {
		sandbox.init_runtime(
			cast(^vm.VM)uintptr(&script_vm),
			cast(^engine_runtime.Environment)uintptr(&environment),
			cast(^renderer.RendererObject)uintptr(&renderer_object),
		)
	} else {
		sandbox.init(
			cast(^vm.VM)uintptr(&script_vm),
			cast(^engine_runtime.Environment)uintptr(&environment),
			cast(^renderer.RendererObject)uintptr(&renderer_object),
		)
	}
	if options.standalone {
		engine_runtime.Environment_Set_Mode(&environment, target.Mode.Standalone)
		vm.AddGlobal_Boolean(&script_vm, "IsServer", true)
		vm.AddGlobal_Boolean(&script_vm, "IsClient", true)
	}
	fmt.eprintf(
		"[Startup] runtime and editor initialized: %.1f ms\n",
		time.duration_milliseconds(time.tick_since(startup_started)),
	)
	environment.services.fast_editor_viewport = options.fast_viewport


	if environment.mode != .Editor {
		loaded, extension_error := extensions.Discover_Default(&environment.extensions)
		if loaded > 0 {
			fmt.printf("Loaded %d native KNE extension(s)\n", loaded)
		}
		if extension_error != "" {
			fmt.eprintln(extension_error)
			delete(extension_error)
		}
	}

	if options.singleplayer {
		vm.AddGlobal_Boolean(&script_vm, "IsServer", true)
		vm.AddGlobal_Boolean(&script_vm, "IsClient", true)
	}
	defer sandbox.shutdown()
	defer vm.Close(&script_vm)
	defer extensions.Game_Unload(&environment.extensions)

	_ = services.Playtest_Debugger_Bootstrap(&script_vm, options.playtest_tree_dir)
	if target.is_server() || options.singleplayer {
		if !load_game_map(&environment, &script_vm, options) {
			return false
		}
	} else if options.playtest || options.standalone {
		if !load_game_map(&environment, &script_vm, options) {
			return false
		}
	} else if target.is_client() && !load_client_asset_bundle() {
		return false
	}

	if options.standalone || options.singleplayer {
		players_object := services.Ensure_Service(&environment.services, "Players")
		if players_object != nil {
			players := cast(^services.Players)players_object
			if players != nil && players.local_player == nil {
				players.local_player = services.Players_Add(
					players,
					script_vm.L,
					1,
					options.username,
				)
			}
		}
	}

	if !load_game_library(&environment, options) {return false}

	if target.is_server() || options.singleplayer || options.standalone {
		server_script_service := cast(^services.ServerScriptService)(services.Ensure_Service(
				&environment.services,
				"ServerScriptService",
			))
		if server_script_service != nil {
			script_context := services.ScriptContext_From_Registry(&environment.services)
			if services.ScriptContext_Runs_Server_Scripts(script_context) {
				fmt.println("Running scripts")
				services.ServerScriptService_RunScripts(
					environment.renderer,
					environment.services.data_model,
					&server_script_service.object,
				)
				fmt.println("Finished running scripts")
			}
		}
	}

	if options.singleplayer || options.standalone {
		services.CharacterService_Load_Local_Player(&environment.services)
	}

	if target.is_server() {
		object := services.Ensure_Service(&environment.services, "ReplicatorService")
		if object == nil ||
		   !services.replication_start(
				   cast(^services.ReplicatorService)object,
				   options.address,
				   options.port,
				   .Server,
			   ) {
			fmt.eprintf("Could not start the server on %s:%d\n", options.address, options.port)
			return false
		}
		fmt.printf("Kinemium server listening on %s:%d\n", options.address, options.port)
	} else if target.is_client() {
		if !options.standalone {
			object := services.Ensure_Service(&environment.services, "ReplicatorService")
			if object == nil ||
			   !services.replication_start(
					   cast(^services.ReplicatorService)object,
					   options.address,
					   options.port,
					   .Client,
				   ) {
				fmt.eprintf("Could not connect to %s:%d\n", options.address, options.port)
				return false
			}
			fmt.printf("Kinemium client connecting to %s:%d...\n", options.address, options.port)
		}
	}

	if !target.is_server() {
		services.Update_Service_Boot(
			&environment.services,
			!options.playtest,
			options.update_check,
			options.no_update,
		)
	}

	profiling.init()
	defer profiling.shutdown()

	title := "Kinemium Engine"
	if options.standalone {
		title = "Kinemium Engine"
	}
	if options.singleplayer {
		title = "Kinemium Singleplayer"
		if payload, ok := self_payload(); ok && payload.mode == .Singleplayer {
			fmt.println(services.SINGLEPLAYER_EXPORT_MARKER)
			if payload.name != "" {
				title = payload.name
			}
		}
	} else if target.is_server() {
		title = "Kinemium Server"
	} else if target.is_client() {
		title = "Kinemium Client"
	} else if !options.playtest && !options.standalone {
		title = "Kinemium Engine"
	}

	if len(options.project) > 0 && options.mode == target.Mode.Editor {
		datamodel := cast(^services.DataModel)environment.classes.data_model
		project := cast(^services.ProjectService)services.DataModel_Get_Service(
			datamodel,
			"Project",
		)
		services.Project_Bind_State(project, script_vm.L)
		if project == nil || !services.Project_Open(project, options.project) {
			fmt.eprintf("Could not open project %q\n", options.project)
			return false
		}
	}
	fmt.eprintf(
		"[Startup] entering renderer: %.1f ms\n",
		time.duration_milliseconds(time.tick_since(startup_started)),
	)
	renderer.init(title, 800, 600, &renderer_object)

	if !options.playtest {
		services.Update_Service_Shutdown()
	}
	return true
}

main :: proc() {

	when tracy.TRACY_ENABLE {
		context.allocator = tracy.InitDefaultAllocator(
			callstack_size = #config(TRACY_ALLOC_CALLSTACK, 0),
		)
	}

	services.Update_Handle_Command_Line()

	when ODIN_OS == .Windows {
		exe_path, err := os.get_executable_path(context.allocator)
		if err == nil {
			sdl3.register_protocol(exe_path)
		}
	}

	options, options_ok := startup_options()
	if !options_ok {os.exit(1)}

	target.set_mode(options.mode)

	if options.headless || (target.is_server() && !options.window) {

		if !run_headless(options) {os.exit(1)}
	} else {

		if !run_desktop(options) {os.exit(1)}
	}
}
