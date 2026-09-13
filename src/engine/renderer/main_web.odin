#+build js
package renderer

import "core:strings"

import kineffi "../bindings"
import sdl3 "../platform"

Filament_Context :: kineffi.KineFilamentContext
Skia_Surface     :: kineffi.KineSkiaSurface

RendererObject :: struct {
	KeyDown:    proc(scancode: sdl3.Scancode),
	KeyUp:      proc(scancode: sdl3.Scancode),
	MouseClick: proc(button: sdl3.MouseButtonEvent),
	OnClose:    proc(),
	Step:        proc(user_data: rawptr, delta_time: f32),
	UserData:    rawptr,
	Draw3D:      proc(user_data: rawptr, ctx: ^kineffi.KineFilamentContext, delta_time: f32),
	Draw2D:      proc(user_data: rawptr, surface: ^kineffi.KineSkiaSurface, width, height: i32, delta_time: f32),
	DrawOverlay: proc(user_data: rawptr, surface: ^kineffi.KineSkiaSurface, width, height: i32, delta_time: f32),
	OnEvent:     proc(user_data: rawptr, event: sdl3.Event),
	Ready:       bool,
	HasWorldToView: bool,
	WorldToView: [12]f32,
	ActiveCamera: rawptr,
	SkiaSurface: ^kineffi.KineSkiaSurface,
	Filament:    ^kineffi.KineFilamentContext,
	HasViewportRect: bool,
	ViewportRect: [4]i32,
}

Web_State :: struct {
	renderer:       ^RendererObject,
	window:         ^sdl3.Window,
	base_surface:   ^kineffi.KineSkiaSurface,
	overlay_surface:^kineffi.KineSkiaSurface,
	width:          i32,
	height:         i32,
}

web_state: Web_State

set_viewport_rect :: proc(renderer: ^RendererObject, x, y, width, height: i32) {
	renderer.HasViewportRect = true
	renderer.ViewportRect = {x, y, width, height}
}

apply_viewport_rect :: proc(renderer: ^RendererObject) {
	if renderer.HasViewportRect && renderer.Filament != nil {
		rect := renderer.ViewportRect
		kineffi.Kine_Filament_SetViewport(renderer.Filament, rect[0], rect[1], rect[2], rect[3])
	}
}

resize_surfaces :: proc(width, height: i32) {
	if web_state.base_surface != nil { kineffi.Kine_Skia_Surface_Destroy(web_state.base_surface) }
	if web_state.overlay_surface != nil { kineffi.Kine_Skia_Surface_Destroy(web_state.overlay_surface) }
	web_state.base_surface = kineffi.Kine_Skia_Surface_Create(width, height)
	web_state.overlay_surface = kineffi.Kine_Skia_Surface_Create(width, height)
	if web_state.renderer != nil && web_state.renderer.Filament != nil {
		kineffi.Kine_Filament_Resize(web_state.renderer.Filament, width, height)
		kineffi.Kine_Filament_SetCameraPerspective(web_state.renderer.Filament, 60, f64(width)/f64(height), 0.1, 1000)
	}
	web_state.width, web_state.height = width, height
}

init :: proc(window_name: string, width, height: i32, renderer: ^RendererObject) {
	assert(renderer != nil)
	frame_width, frame_height := width, height
	_ = sdl3.Init(sdl3.INIT_VIDEO | sdl3.INIT_EVENTS)
	name := strings.clone_to_cstring(window_name)
	defer delete(name)
	window := sdl3.CreateWindow(name, frame_width, frame_height, sdl3.WINDOW_RESIZABLE)
	_ = sdl3.GetWindowSizeInPixels(window, &frame_width, &frame_height)
	filament := kineffi.Kine_Filament_CreateForSDLWindow(window, frame_width, frame_height)
	if filament == nil { panic("Failed to create Filament WebGL renderer") }

	renderer.Filament = filament
	renderer.Ready = true
	web_state = {renderer = renderer, window = window}
	resize_surfaces(frame_width, frame_height)
}

frame :: proc(delta_time: f64) -> bool {
	renderer := web_state.renderer
	if renderer == nil { return false }
	dt := min(f32(max(delta_time, 0)), 0.1)

	event: sdl3.Event
	for sdl3.PollEvent(&event) {
		if renderer.OnEvent != nil { renderer.OnEvent(renderer.UserData, event) }
		#partial switch event.type {
		case .QUIT, .WINDOW_CLOSE_REQUESTED, .WINDOW_DESTROYED:
			if renderer.OnClose != nil { renderer.OnClose() }
			return false
		case .KEY_DOWN:
			if renderer.KeyDown != nil { renderer.KeyDown(event.key.scancode) }
		case .KEY_UP:
			if renderer.KeyUp != nil { renderer.KeyUp(event.key.scancode) }
		case .MOUSE_BUTTON_DOWN:
			if renderer.MouseClick != nil { renderer.MouseClick(event.button) }
		case:
		}
	}

	width, height: i32
	_ = sdl3.GetWindowSizeInPixels(web_state.window, &width, &height)
	if width <= 0 || height <= 0 { return true }
	if width != web_state.width || height != web_state.height { resize_surfaces(width, height) }

	renderer.SkiaSurface = nil
	if renderer.Step != nil { renderer.Step(renderer.UserData, dt) }

	kineffi.Kine_Skia_Surface_Clear(web_state.base_surface, 20, 28, 41, 255)
	renderer.SkiaSurface = web_state.base_surface
	if renderer.Draw2D != nil { renderer.Draw2D(renderer.UserData, web_state.base_surface, width, height, dt) }
	kineffi.Kine_Skia_Surface_Flush(web_state.base_surface)
	renderer.SkiaSurface = nil

	if renderer.Draw3D != nil { renderer.Draw3D(renderer.UserData, renderer.Filament, dt) }
	apply_viewport_rect(renderer)
	kineffi.Kine_Filament_RenderFrame(renderer.Filament, dt)

	kineffi.Kine_Skia_Surface_Clear(web_state.overlay_surface, 0, 0, 0, 0)
	renderer.SkiaSurface = web_state.overlay_surface
	if renderer.DrawOverlay != nil { renderer.DrawOverlay(renderer.UserData, web_state.overlay_surface, width, height, dt) }
	kineffi.Kine_Skia_Surface_Flush(web_state.overlay_surface)
	renderer.SkiaSurface = nil
	return true
}

shutdown :: proc() {
	if web_state.base_surface != nil { kineffi.Kine_Skia_Surface_Destroy(web_state.base_surface) }
	if web_state.overlay_surface != nil { kineffi.Kine_Skia_Surface_Destroy(web_state.overlay_surface) }
	if web_state.renderer != nil && web_state.renderer.Filament != nil {
		kineffi.Kine_Filament_Destroy(web_state.renderer.Filament)
		web_state.renderer.Filament = nil
	}
	web_state = {}
	sdl3.Quit()
}

close :: proc(renderer: RendererObject, running: ^bool) {
	if renderer.OnClose != nil { renderer.OnClose() }
	if running != nil { running^ = false }
}
