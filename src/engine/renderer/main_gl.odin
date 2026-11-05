#+build !js
package renderer

import "core:fmt"
import "core:strings"

import kineffi "../bindings"
import sdl3 "../platform"
import profiling "../profiling"
import tracy "../util/odin-tracy"

when KINE_RENDERER_GL {

	Filament_Context :: kineffi.KineFilamentContext
	Skia_Surface :: kineffi.KineSkiaSurface

	RendererObject :: struct {
		KeyDown:           proc(scancode: sdl3.Scancode),
		KeyUp:             proc(scancode: sdl3.Scancode),
		MouseClick:        proc(button: sdl3.MouseButtonEvent),
		OnClose:           proc(user_data: rawptr),
		Step:              proc(user_data: rawptr, delta_time: f32),
		UserData:          rawptr,
		Draw3D:            proc(
			user_data: rawptr,
			ctx: ^kineffi.KineFilamentContext,
			delta_time: f32,
		),
		Draw2D:            proc(
			user_data: rawptr,
			surface: ^kineffi.KineSkiaSurface,
			width, height: i32,
			delta_time: f32,
		),
		DrawOverlay:       proc(
			user_data: rawptr,
			surface: ^kineffi.KineSkiaSurface,
			width, height: i32,
			delta_time: f32,
		),
		OnEvent:           proc(user_data: rawptr, event: sdl3.Event),
		OnResize:          proc(user_data: rawptr, width, height: i32),
		Ready:             bool,
		HasWorldToView:    bool,
		WorldToView:       [12]f32,
		ActiveCamera:      rawptr,
		SkiaSurface:       ^kineffi.KineSkiaSurface,
		Filament:          ^kineffi.KineFilamentContext,
		HasViewportRect:   bool,
		RenderFilament:    bool,
		ViewportRect:      [4]i32,
		ViewportRect_Host: bool,
		MouseScale:        [2]f32,
		CurrentEvent:      ^sdl3.Event,
		Window:            ^sdl3.Window,
		Compositor:        ^kineffi.KineVulkanCompositor,
	}


	viewport_size :: proc(renderer: ^RendererObject) -> (width, height: i32) {
		if renderer == nil {return 0, 0}
		if renderer.HasViewportRect {
			return renderer.ViewportRect[2], renderer.ViewportRect[3]
		}
		if renderer.Filament != nil {
			return kineffi.Kine_Filament_GetWidth(
				renderer.Filament,
			), kineffi.Kine_Filament_GetHeight(renderer.Filament)
		}
		return 0, 0
	}


	set_viewport_rect :: proc(
		renderer: ^RendererObject,
		x, y, width, height: i32,
		from_host: bool,
	) -> bool {
		if renderer == nil {return false}
		if width < 0 || height < 0 {return false}

		if from_host {renderer.ViewportRect_Host = true}

		if width == 0 || height == 0 {
			renderer.HasViewportRect = false
			return true
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
		return true
	}

	update_mouse_scale :: proc(renderer: ^RendererObject, window: ^sdl3.Window) {
		if renderer == nil || window == nil {return}

		pixel_width, pixel_height: i32
		if !sdl3.GetWindowSizeInPixels(window, &pixel_width, &pixel_height) {return}

		logical_width, logical_height: i32
		if !sdl3.GetWindowSize(window, &logical_width, &logical_height) {return}
		if logical_width <= 0 || logical_height <= 0 {return}

		scale := [2]f32 {
			f32(pixel_width) / f32(logical_width),
			f32(pixel_height) / f32(logical_height),
		}
		if renderer.MouseScale == scale {return}

		renderer.MouseScale = scale
		fmt.eprintln(
			"Kinemium: mouse density ",
			scale[0],
			"x",
			scale[1],
			" (logical ",
			logical_width,
			"x",
			logical_height,
			", pixels ",
			pixel_width,
			"x",
			pixel_height,
			")",
		)
	}

	apply_viewport_rect :: proc(renderer: ^RendererObject) {
		if renderer.HasViewportRect && renderer.Filament != nil {
			rect := renderer.ViewportRect
			kineffi.Kine_Filament_SetViewport(
				renderer.Filament,
				rect[0],
				rect[1],
				rect[2],
				rect[3],
			)
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
		sdl3.Reset_UI_Scale()
		fmt.eprintln("Kinemium: UI scale ", sdl3.UI_Scale)
		defer sdl3.Quit()


		kineffi.Kine_GL_Compositor_SetDefaultAttributes()

		window := sdl3.CreateWindow(
			strings.clone_to_cstring(windowName),
			width,
			height,
			sdl3.WINDOW_OPENGL | sdl3.WINDOW_RESIZABLE,
		)
		if window == nil {
			show_fatal_error("Failed to create the OpenGL window")
			return
		}
		renderer.Window = window
		defer sdl3.DestroyWindow(window)

		_ = sdl3.GetWindowSizeInPixels(window, &width, &height)

		compositor := kineffi.Kine_GL_Compositor_CreateForSDLWindow(window, width, height)
		if compositor == nil || kineffi.Kine_GL_Compositor_IsReady(compositor) == 0 {
			show_fatal_error("Failed to create the OpenGL compositor", window)
			if compositor != nil {kineffi.Kine_GL_Compositor_Destroy(compositor)}
			return
		}
		defer kineffi.Kine_GL_Compositor_Destroy(compositor)


		filament := kineffi.Kine_Filament_CreateForSDLWindow(window, width, height)
		if filament == nil {
			show_fatal_error("Failed to create the Filament OpenGL renderer", window)
			return
		}
		renderer.Filament = filament
		defer {


			kineffi.Kine_Filament_Destroy(filament)
			renderer.Filament = nil
		}

		frame_width, frame_height := width, height
		previous_ticks := sdl3.GetTicksNS()
		running := true
		drawable := true

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
					defer renderer.CurrentEvent = nil
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
			if pixel_width <= 0 || pixel_height <= 0 {sdl3.Delay(10); continue}
			if pixel_width != frame_width || pixel_height != frame_height {
				size_changed := pixel_width != frame_width || pixel_height != frame_height

				frame_width, frame_height = pixel_width, pixel_height

				_ = kineffi.Kine_GL_Compositor_Resize(compositor, frame_width, frame_height)
				kineffi.Kine_Filament_Resize(filament, frame_width, frame_height)

				if size_changed && renderer.OnResize != nil {
					renderer.OnResize(renderer.UserData, frame_width, frame_height)
				}

				previous_ticks = sdl3.GetTicksNS()
			}

			if !renderer.ViewportRect_Host {
				set_viewport_rect(renderer, 0, 0, frame_width, frame_height, false)
			}
			update_mouse_scale(renderer, window)
			sdl3.update_ui_safe_area(window)

			now := sdl3.GetTicksNS()
			delta_time := min(f32(now - previous_ticks) / 1_000_000_000.0, 0.1)
			previous_ticks = now
			renderer.SkiaSurface = nil

			{
				tracy.ZoneNC("Engine Step", 0xD08770)
				z := profiling.Begin("Engine Step", 0xD08770)
				if renderer.Step != nil {
					renderer.Step(renderer.UserData, delta_time)
				}
			}

			base_surface := kineffi.Kine_GL_Compositor_BeginFrame(compositor)
			if base_surface == nil {
				fmt.eprintf(
					"OpenGL frame acquisition failed: %s\n",
					kineffi.Kine_GL_Compositor_GetLastError(compositor),
				)
				break
			}

			kineffi.Kine_Skia_Surface_Clear(
				cast(^kineffi.KineSkiaSurface)base_surface,
				20,
				28,
				41,
				255,
			)

			renderer.SkiaSurface = cast(^kineffi.KineSkiaSurface)base_surface

			if renderer.Draw2D != nil {
				renderer.Draw2D(
					renderer.UserData,
					renderer.SkiaSurface,
					frame_width,
					frame_height,
					delta_time,
				)
			}

			if renderer.Draw3D != nil {
				renderer.Draw3D(renderer.UserData, filament, delta_time)
			}

			kineffi.Kine_Skia_Surface_Flush(renderer.SkiaSurface)
			renderer.SkiaSurface = nil
			apply_viewport_rect(renderer)

			rendered_3d := renderer.RenderFilament && renderer.HasViewportRect
			if rendered_3d || kineffi.Kine_Filament_Viewport_HasWork(filament) {
				kineffi.Kine_Filament_Viewport_RenderFrame(filament, delta_time, rendered_3d)
			}
			if rendered_3d {
				rect := renderer.ViewportRect
				kineffi.Kine_GL_Compositor_SetViewportRect(
					compositor,
					rect[0],
					rect[1],
					rect[2],
					rect[3],
				)
				kineffi.Kine_GL_Compositor_SetSceneTexture(
					compositor,
					u32(kineffi.Kine_Filament_GetColorTextureId(filament)),
					frame_width,
					frame_height,
				)
			} else {
				kineffi.Kine_GL_Compositor_SetSceneTexture(
					compositor,
					0,
					frame_width,
					frame_height,
				)
			}

			if renderer.DrawOverlay != nil {
				overlay_surface := kineffi.Kine_GL_Compositor_BeginOverlay(compositor)
				if overlay_surface != nil {
					renderer.SkiaSurface = cast(^kineffi.KineSkiaSurface)overlay_surface

					renderer.DrawOverlay(
						renderer.UserData,
						renderer.SkiaSurface,
						frame_width,
						frame_height,
						delta_time,
					)

					kineffi.Kine_Skia_Surface_Flush(renderer.SkiaSurface)
					renderer.SkiaSurface = nil
				}
			}

			if kineffi.Kine_GL_Compositor_EndFrame(compositor) == 0 {
				fmt.eprintf(
					"OpenGL presentation failed: %s\n",
					kineffi.Kine_GL_Compositor_GetLastError(compositor),
				)
				break
			}
			renderer.Ready = true
			renderer.SkiaSurface = nil

			tracy.FrameMark()
		}

		if renderer.OnClose != nil {
			renderer.OnClose(renderer.UserData)
		}
	}

	close :: proc(renderer: RendererObject, running: ^bool) {
		renderer.OnClose(renderer.UserData)
		running^ = false
	}

}
