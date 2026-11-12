#+build !js
package main

import tracy "./engine/util/odin-tracy"
import sandbox "./sandboxed"
import "core:fmt"
import "core:os"
import audio "engine/audio"
import extensions "engine/extensions"
import sdl3 "engine/platform"
import profiling "engine/profiling"
import renderer "engine/renderer"
import engine_runtime "engine/runtime"
import services "engine/services"
import target "engine/target"
import vm "engine/vm"

Runtime_Render_Context :: struct {
	environment: ^engine_runtime.Environment,
	vm_state:    ^vm.VM,
}

runtime_update_step :: proc(user_data: rawptr, delta_time: f32) {
	ctx := cast(^Runtime_Render_Context)user_data
	if ctx == nil {
		return
	}
	engine_runtime.Environment_Update_Step(ctx.environment, ctx.vm_state, delta_time)
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

runtime_input_event :: proc(user_data: rawptr, event: sdl3.Event) {
	ctx := cast(^Runtime_Render_Context)user_data
	if ctx == nil {return}
	profiling.trigger_event(event)
	engine_runtime.Environment_SetEvent(ctx.environment, ctx.vm_state, event)
}

run_desktop :: proc(options: Startup_Options) {
	tracy.SetThreadName("Main")
	if target.is_client() && !options.standalone {
		if !options.playtest && (options.address == "" || options.address == "0.0.0.0") {
			fmt.eprintln(
				"Network client needs a reachable server address; use 127.0.0.1 for a server on this computer",
			)
			return
		}
		if options.map_path != "" && !options.playtest {
			fmt.eprintln(
				"Load the map on the server with --map; clients receive it through replication",
			)
			return
		}
	}
	script_vm := vm.New()
	if !audio.init() {
		return
	}
	defer audio.shutdown()

	environment: engine_runtime.Environment
	render_context := Runtime_Render_Context {
		environment = &environment,
		vm_state    = &script_vm,
	}

	renderer_object := renderer.RendererObject {
		Step = runtime_update_step,
		Draw3D = runtime_render_3d,
		Draw2D = runtime_render_2d,
		DrawOverlay = runtime_render_overlay,
		UserData = &render_context,
		RenderFilament = true,
		Cache2D = true,
		Render3DCheck = runtime_render_3d_dirty,
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
			// Lua finalizers release mesh resources through their Filament context.
			// Run them before the renderer destroys that context.
			vm.Close(render_context.vm_state)
		},
		OnResize = runtime_resize,
		OnEvent = runtime_input_event,
	}

	target.set_playtest(options.playtest)
	vm.AddGlobal_Boolean(&script_vm, "IsPlaytest", options.playtest)

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

	// Load KNE native extensions from ./extensions before any game code runs, so
	// a script can use what they registered from its first line.
	{
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

	if target.is_server() || options.singleplayer {
		if !load_game_map(&environment, &script_vm, options) {
			return
		}
	} else if options.playtest || options.standalone {
		if !load_game_map(&environment, &script_vm, options) {
			return
		}
	} else if target.is_client() && !load_client_asset_bundle() {
		return
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
			if players != nil && players.local_player != nil {
				character_service := cast(^services.CharacterService)(services.Ensure_Service(
						&environment.services,
						"CharacterService",
					))
				if character_service != nil {
					_ = services.CharacterService_Load(character_service, players.local_player)
				}
			}
		}
	}

	if target.is_server() || options.singleplayer {
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
			return
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
				return
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
	renderer.init(title, 800, 600, &renderer_object)

	if !options.playtest {
		services.Update_Service_Shutdown()
	}
}

main :: proc() {
	fmt.println("Hello World! Step 1")
	when tracy.TRACY_ENABLE {
		context.allocator = tracy.InitDefaultAllocator(
			callstack_size = #config(TRACY_ALLOC_CALLSTACK, 0),
		)
	}
	fmt.println("Hello World! Step 2")
	services.Update_Handle_Command_Line()
	fmt.println("Hello World! Step 3")
	when ODIN_OS == .Windows {
		exe_path, err := os.get_executable_path(context.allocator)
		if err == nil {
			sdl3.register_protocol(exe_path)
		}
	}
	fmt.println("Hello World! Step 4")
	options, options_ok := startup_options()
	if !options_ok {return}
	fmt.println("Hello World! Step 5")
	target.set_mode(options.mode)
	fmt.println("Hello World! Step 6")
	if target.is_server() && !options.window {
		fmt.println("Hello World! Step 7: Server")
		run_server(options)
	} else {
		fmt.println("Hello World! Step 7: Desktop")
		run_desktop(options)
	}
}
