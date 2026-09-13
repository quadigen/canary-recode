#+build js
package main

import "core:fmt"
import engine_runtime "engine/runtime"
import renderer "engine/renderer"
import sdl3 "engine/platform"
import vm "engine/vm"
import sandbox "./sandboxed"

Runtime_Render_Context :: struct {
	environment: ^engine_runtime.Environment,
	vm_state:    ^vm.VM,
}

script_vm: vm.VM
environment: engine_runtime.Environment
render_context: Runtime_Render_Context
renderer_object: renderer.RendererObject

runtime_update_step :: proc(user_data: rawptr, delta_time: f32) {
	ctx := cast(^Runtime_Render_Context)user_data
	if ctx != nil { engine_runtime.Environment_Update_Step(ctx.environment, ctx.vm_state, delta_time) }
}
runtime_render_3d :: proc(user_data: rawptr, filament: ^renderer.Filament_Context, delta_time: f32) {
	ctx := cast(^Runtime_Render_Context)user_data
	if ctx != nil { engine_runtime.Environment_Render_3D(ctx.environment, ctx.vm_state, delta_time) }
}
runtime_render_2d :: proc(user_data: rawptr, surface: ^renderer.Skia_Surface, width, height: i32, delta_time: f32) {
	ctx := cast(^Runtime_Render_Context)user_data
	if ctx != nil { engine_runtime.Environment_Render_2D(ctx.environment, ctx.vm_state, surface, width, height, delta_time) }
}
runtime_render_overlay :: proc(user_data: rawptr, surface: ^renderer.Skia_Surface, width, height: i32, delta_time: f32) {
	ctx := cast(^Runtime_Render_Context)user_data
	if ctx != nil { engine_runtime.Environment_Render_Overlay(ctx.environment, ctx.vm_state, surface, width, height, delta_time) }
}
runtime_input_event :: proc(user_data: rawptr, event: sdl3.Event) {
	ctx := cast(^Runtime_Render_Context)user_data
	if ctx != nil { engine_runtime.Environment_SetEvent(ctx.environment, ctx.vm_state, event) }
}

main :: proc() {
	sdl3.DebugPhase(100)
	script_vm = vm.New()
	sdl3.DebugPhase(101)
	render_context = {environment = &environment, vm_state = &script_vm}
	renderer_object = {
		Step = runtime_update_step,
		Draw3D = runtime_render_3d,
		Draw2D = runtime_render_2d,
		DrawOverlay = runtime_render_overlay,
		UserData = &render_context,
		KeyDown = proc(scancode: sdl3.Scancode) { fmt.println("Key down: ", scancode) },
		KeyUp = proc(scancode: sdl3.Scancode) { fmt.println("Key up: ", scancode) },
		MouseClick = proc(button: sdl3.MouseButtonEvent) { fmt.println("Mouse button clicked: ", button.button) },
		OnEvent = runtime_input_event,
	}
}

@(export)
initialize_environment :: proc() -> bool {
	sandbox.init_runtime(&script_vm, &environment, &renderer_object)
	return true
}

@(export)
initialize_scripts :: proc() -> bool {
	sandbox.init_scripts()
	return true
}

@(export)
initialize_renderer :: proc() -> bool {
	renderer.init("Kinemium Engine", 1280, 720, &renderer_object)
	return renderer_object.Ready
}

@(export)
step :: proc(delta_time: f64) -> bool {
	return renderer.frame(delta_time)
}
