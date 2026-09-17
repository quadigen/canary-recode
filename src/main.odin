#+build !js
package main

import "core:fmt"
import engine_runtime "engine/runtime"
import renderer "engine/renderer"
import vm "engine/vm"
import sdl3 "engine/platform"
import sandbox "./sandboxed"
import services "engine/services"

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

runtime_render_3d :: proc(user_data: rawptr, filament: ^renderer.Filament_Context, delta_time: f32) {
	ctx := cast(^Runtime_Render_Context)user_data
	if ctx == nil { return }
	engine_runtime.Environment_Render_3D(ctx.environment, ctx.vm_state, delta_time)
}

runtime_resize :: proc(user_data: rawptr, width, height: i32) {
    ctx := cast(^Runtime_Render_Context)user_data

    if ctx == nil || ctx.environment == nil {
        return
    }

    services.Resize(
        &ctx.environment.services,
        &ctx.environment.datatypes,
        width,
        height,
    )
}

last_ui_width:  i32 = -1
last_ui_height: i32 = -1

runtime_render_2d :: proc(user_data: rawptr, surface: ^renderer.Skia_Surface, width, height: i32, delta_time: f32) {
	if width != last_ui_width || height != last_ui_height {
        fmt.printf(
            "[Draw2D SIZE CHANGED] %dx%d -> %dx%d\n",
            last_ui_width,
            last_ui_height,
            width,
            height,
        )

        last_ui_width = width
        last_ui_height = height
    }

	ctx := cast(^Runtime_Render_Context)user_data
	if ctx == nil { return }
	engine_runtime.Environment_Render_2D(ctx.environment, ctx.vm_state, surface, width, height, delta_time)
}

runtime_render_overlay :: proc(user_data: rawptr, surface: ^renderer.Skia_Surface, width, height: i32, delta_time: f32) {
	ctx := cast(^Runtime_Render_Context)user_data
	if ctx == nil { return }
	engine_runtime.Environment_Render_Overlay(ctx.environment, ctx.vm_state, surface, width, height, delta_time)
}

runtime_input_event :: proc(user_data: rawptr, event: sdl3.Event) {
	ctx := cast(^Runtime_Render_Context)user_data
	if ctx == nil { return }
	engine_runtime.Environment_SetEvent(ctx.environment, ctx.vm_state, event)
}

main :: proc() {
	script_vm := vm.New()
	defer vm.Close(&script_vm)

	environment: engine_runtime.Environment
	render_context := Runtime_Render_Context{
		environment = &environment,
		vm_state = &script_vm,
	}

	renderer_object := renderer.RendererObject{
		Step = runtime_update_step,
		Draw3D = runtime_render_3d,
		Draw2D = runtime_render_2d,
		DrawOverlay = runtime_render_overlay,
		UserData = &render_context,
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

	sandbox.init(&script_vm, &environment, &renderer_object)
	defer sandbox.shutdown()

	renderer.init("Kinemium Engine", 800, 600, &renderer_object)
}
