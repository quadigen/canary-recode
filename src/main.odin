#+build !js
package main

import tracy "./engine/util/odin-tracy"
import sandbox "./sandboxed"
import "core:fmt"
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

run_desktop :: proc() {
	tracy.SetThreadName("Main")
	options, options_ok := startup_options("127.0.0.1")
	if !options_ok {return}
	when target.IS_CLIENT {
		if !options.playtest && (options.address == "" || options.address == "0.0.0.0") {
			fmt.eprintln("Network client needs a reachable server address; use 127.0.0.1 for a server on this computer")
			return
		}
		if options.map_path != "" && !options.playtest {
			fmt.eprintln("Load the map on the server with --map; clients receive it through replication")
			return
		}
	}
	script_vm := vm.New()

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
		KeyDown = proc(scancode: sdl3.Scancode) {
			fmt.println("Key down: ", scancode)
		},
		KeyUp = proc(scancode: sdl3.Scancode) {
			fmt.println("Key up: ", scancode)
		},
		MouseClick = proc(button: sdl3.MouseButtonEvent) {
			fmt.println("Mouse button clicked: ", button.button)
		},
		OnClose = proc() {
			fmt.println("Window closed")
		},
		OnResize = runtime_resize,
		OnEvent = runtime_input_event,
	}

	if options.playtest {sandbox.init_runtime(&script_vm, &environment, &renderer_object)} else {sandbox.init(&script_vm, &environment, &renderer_object)}
	defer sandbox.shutdown()
	defer vm.Close(&script_vm)
	if options.playtest && !engine_runtime.Load_Map(&environment, &script_vm, options.map_path) {return}

	when target.IS_CLIENT {
		if !options.playtest {
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

services.Update_Service_Boot(
		&environment.services,
		!options.playtest,
		options.update_check,
		options.no_update,
	)

	profiling.init()
	defer profiling.shutdown()

	title := "Kinemium Engine"
	if options.playtest {title = "Kinemium Playtest"}
	when target.IS_CLIENT {if !options.playtest {title = "Kinemium Client"}}
	renderer.init(title, 800, 600, &renderer_object)

	if !options.playtest {
		services.Update_Service_Shutdown()
	}
}

main :: proc() {
	services.Update_Handle_Command_Line()
	when target.IS_SERVER {run_server()} else {run_desktop()}
}
