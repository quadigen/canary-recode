#+build !js
package renderer

import "core:fmt"
import "core:strings"

import kineffi "../bindings"
import sdl3 "../platform"
import tracy "../util/odin-tracy"
import profiling "../profiling"

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
	OnResize:    proc(user_data: rawptr, width, height: i32),
	Ready:       bool,
	HasWorldToView: bool,
	WorldToView: [12]f32,
	ActiveCamera: rawptr,
	SkiaSurface: ^kineffi.KineSkiaSurface,
	Filament:    ^kineffi.KineFilamentContext,
	HasViewportRect: bool,
	RenderFilament: bool,
	ViewportRect: [4]i32,
	CurrentEvent: ^sdl3.Event,
	Window: ^sdl3.Window,
}

set_viewport_rect :: proc(
    renderer: ^RendererObject,
    x, y, width, height: i32,
) {
    if width <= 0 || height <= 0 {
        return
    }

    old := renderer.ViewportRect
    changed :=
        !renderer.HasViewportRect ||
        old[0] != x ||
        old[1] != y ||
        old[2] != width ||
        old[3] != height

    renderer.HasViewportRect = true
    renderer.ViewportRect = {x, y, width, height}

    if changed && renderer.Filament != nil {
        kineffi.Kine_Filament_SetCameraPerspective(
            renderer.Filament,
            60,
            f64(width) / f64(height),
            0.1,
            1000,
        )
    }
}

apply_viewport_rect :: proc(renderer: ^RendererObject) {
	if renderer.HasViewportRect && renderer.Filament != nil {
		rect := renderer.ViewportRect
		kineffi.Kine_Filament_SetViewport(renderer.Filament, rect[0], rect[1], rect[2], rect[3])
	}
}

show_fatal_error :: proc(message: string, window: ^sdl3.Window = nil) {
	fmt.eprintln("Kinemium: ", message, ": ", sdl3.GetError())
	title := strings.clone_to_cstring("Kinemium could not start")
	text := strings.clone_to_cstring(message)
	defer delete(title)
	defer delete(text)
	_ = sdl3.ShowSimpleMessageBox(sdl3.MessageBoxFlags{.ERROR}, title, text, window)
}

init :: proc(windowName: string, width: i32, height: i32, renderer: ^RendererObject) {
	width, height := width, height
	if !sdl3.Init(sdl3.INIT_VIDEO | sdl3.INIT_EVENTS) {
		show_fatal_error("Failed to initialize SDL")
		return
	}
	defer sdl3.Quit()

	name := strings.clone_to_cstring(windowName)
	defer delete(name)

	window := sdl3.CreateWindow(
		name,
		width,
		height,
		sdl3.WINDOW_RESIZABLE | sdl3.WINDOW_VULKAN,
    )

	renderer.Window = window
	defer {
		renderer.Window = nil
	}
	
	if window == nil {
		show_fatal_error("Failed to create the Vulkan window")
		return
	}
	defer sdl3.DestroyWindow(window)
	_ = sdl3.GetWindowSizeInPixels(window, &width, &height)

	filament := kineffi.Kine_Filament_CreateForVulkanCompositorWindow(
		window,
		width,
		height,
	)
	if filament == nil {
		show_fatal_error("Failed to create the Filament Vulkan renderer", window)
		return
	}
	defer kineffi.Kine_Filament_Destroy(filament)

	renderer.Filament = filament
	renderer.Ready = false
	renderer.HasWorldToView = false
	defer {
		renderer.Ready = false
		renderer.HasWorldToView = false
		renderer.SkiaSurface = nil
		renderer.Filament = nil
	}

	compositor := cast(^kineffi.KineVulkanCompositor)kineffi.Kine_Filament_GetVulkanCompositor(filament)
	if compositor == nil || kineffi.Kine_VulkanCompositor_IsReady(compositor) == 0 {
		show_fatal_error("Failed to create the Vulkan compositor", window)
		return
	}

	running := true
	drawable := true
	frame_width, frame_height := width, height
	previous_ticks := sdl3.GetTicksNS()

	tracy.SetThreadName("Main/Render")

	for running {
		{
			tracy.ZoneNC("Polling Events", 0x61AFEF)
			z := profiling.Begin("Polling Events", 0x61AFEF)
			event: sdl3.Event

			for sdl3.PollEvent(&event) {
				if renderer.OnEvent != nil {
					renderer.OnEvent(renderer.UserData, event)
				}
				renderer.CurrentEvent = &event
				#partial switch event.type {
				case .QUIT, .WINDOW_CLOSE_REQUESTED:
					running = false
				case .KEY_DOWN:
					if renderer.KeyDown != nil {
						renderer.KeyDown(event.key.scancode)
					}
				case .KEY_UP:
					if renderer.KeyUp != nil {
						renderer.KeyUp(event.key.scancode)
					}
				case .WINDOW_DESTROYED:
					running = false
				case .MOUSE_BUTTON_DOWN:
					if renderer.MouseClick != nil {
						renderer.MouseClick(event.button)
					}
				case .WINDOW_MINIMIZED:
					drawable = false
				case .WINDOW_RESTORED:
					drawable = true
				case .WINDOW_RESIZED, .WINDOW_PIXEL_SIZE_CHANGED:
					drawable = true
				}
			}
		}

		if !running || !drawable {
			previous_ticks = sdl3.GetTicksNS()
			sdl3.Delay(10)
			continue
		}

		pixel_width, pixel_height: i32
		_ = sdl3.GetWindowSizeInPixels(window, &pixel_width, &pixel_height)
		if pixel_width <= 0 || pixel_height <= 0 { sdl3.Delay(10); continue }
		if pixel_width != frame_width || pixel_height != frame_height ||
		kineffi.Kine_VulkanCompositor_NeedsResize(compositor) != 0 {
			size_changed := pixel_width != frame_width || pixel_height != frame_height

			frame_width, frame_height = pixel_width, pixel_height

			kineffi.Kine_Filament_Resize(
				filament,
				frame_width,
				frame_height,
			)

			if size_changed && renderer.OnResize != nil {
				renderer.OnResize(
					renderer.UserData,
					frame_width,
					frame_height,
				)
			}

			previous_ticks = sdl3.GetTicksNS()
		}

		now := sdl3.GetTicksNS()
		delta_time := min(f32(now-previous_ticks)/1_000_000_000.0, 0.1)
		previous_ticks = now
		renderer.SkiaSurface = nil

		{
			tracy.ZoneNC("Engine Step", 0xD08770)
			z := profiling.Begin("Engine Step", 0xD08770)
			if renderer.Step != nil {
				renderer.Step(renderer.UserData, delta_time)
			}
		}

		base_surface: rawptr
		{
			tracy.ZoneNC("Vulkan BeginFrame", 0x56B6C2)
			z := profiling.Begin("Vulkan BeginFrame", 0x56B6C2)
			base_surface = kineffi.Kine_VulkanCompositor_BeginFrame(compositor)
			if base_surface == nil {
				if kineffi.Kine_VulkanCompositor_NeedsResize(compositor) != 0 { continue }
				error := kineffi.Kine_VulkanCompositor_GetLastError(compositor)
				fmt.eprintf("Vulkan frame acquisition failed: %s\n", error)
				break
			}
		}

		{
			tracy.ZoneNC("Skia Clear", 0xA3BE8C)
			z := profiling.Begin("Skia Clear", 0xA3BE8C)
			kineffi.Kine_Skia_Surface_Clear(
				cast(^kineffi.KineSkiaSurface)base_surface,
				20,
				28,
				41,
				255,
			)
		}

		renderer.SkiaSurface = cast(^kineffi.KineSkiaSurface)base_surface

		{
			tracy.ZoneNC("Draw2D", 0x61AFEF)
			z := profiling.Begin("Draw2D", 0x61AFEF)
			if renderer.Draw2D != nil {
				renderer.Draw2D(renderer.UserData, renderer.SkiaSurface, frame_width, frame_height, delta_time)
			}
		}

		{
			tracy.ZoneNC("Draw3D", 0x98C379)
			z := profiling.Begin("Draw3D", 0x98C379)
			if renderer.Draw3D != nil {
				renderer.Draw3D(renderer.UserData, filament, delta_time)
			}
		}

		{
			tracy.ZoneNC("Skia Flush", 0xE5C07B)
			z := profiling.Begin("Skia Flush", 0xE5C07B)
			kineffi.Kine_Skia_Surface_Flush(renderer.SkiaSurface)
		}
		renderer.SkiaSurface = nil
		apply_viewport_rect(renderer)

		if renderer.RenderFilament {
			tracy.ZoneNC("Filament RenderFrame", 0xC678DD)
			z := profiling.Begin("Filament RenderFrame", 0xC678DD)
			kineffi.Kine_Filament_RenderFrame(filament, delta_time)
		}

		if renderer.DrawOverlay != nil {
			tracy.ZoneNC("Overlay", 0xE06C75)
			z := profiling.Begin("Overlay", 0xE06C75)
			overlay_surface := kineffi.Kine_VulkanCompositor_BeginOverlay(compositor)
			if overlay_surface != nil {
				renderer.SkiaSurface = cast(^kineffi.KineSkiaSurface)overlay_surface
				renderer.DrawOverlay(renderer.UserData, renderer.SkiaSurface, frame_width, frame_height, delta_time)
				tracy.ZoneNC("Skia Flush", 0xE5C07B)
				z := profiling.Begin("Overlay Skia Flush", 0xE5C07B)
				kineffi.Kine_Skia_Surface_Flush(renderer.SkiaSurface)
				renderer.SkiaSurface = nil
			}
		}

		if kineffi.Kine_VulkanCompositor_EndFrame(compositor) == 0 {
			error := kineffi.Kine_VulkanCompositor_GetLastError(compositor)
			tracy.ZoneNC("Vulkan Present", 0xD19A66)
			z := profiling.Begin("Vulkan Present", 0xD19A66)
			fmt.eprintf("Vulkan presentation failed: %s\n", error)
			break
		}
		renderer.Ready = true
		renderer.SkiaSurface = nil

		tracy.FrameMark()
	}

	if renderer.OnClose != nil {
		renderer.OnClose()
	}
}

close :: proc(renderer: RendererObject, running: ^bool) {
    renderer.OnClose()
    running^ = false
}
