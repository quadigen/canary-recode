package renderer

import "core:fmt"
import "core:strings"

import kineffi "../bindings"
import sdl3 "vendor:sdl3"

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

	SkiaSurface: ^kineffi.KineSkiaSurface,
	Filament:    ^kineffi.KineFilamentContext,
}

init :: proc(windowName: string, width: i32, height: i32, renderer: ^RendererObject) {
	if !sdl3.Init(sdl3.INIT_VIDEO | sdl3.INIT_EVENTS) {
		panic("Failed to initialize SDL")
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
	if window == nil {
		panic("Failed to create SDL window")
	}
	defer sdl3.DestroyWindow(window)

	filament := kineffi.Kine_Filament_CreateForVulkanCompositorWindow(
		window,
		width,
		height,
	)
	if filament == nil {
		panic("Failed to create Filament Vulkan renderer")
	}
	defer kineffi.Kine_Filament_Destroy(filament)

	renderer.Filament = filament
	defer {
		renderer.SkiaSurface = nil
		renderer.Filament = nil
	}

	compositor := cast(^kineffi.KineVulkanCompositor)kineffi.Kine_Filament_GetVulkanCompositor(filament)
	if compositor == nil || kineffi.Kine_VulkanCompositor_IsReady(compositor) == 0 {
		panic("Failed to create Vulkan compositor")
	}

	kineffi.Kine_Filament_CreateSky(filament, 0.08, 0.11, 0.16, 1)
	kineffi.Kine_Filament_SetCameraPerspective(
		filament,
		60,
		f64(width)/f64(height),
		0.1,
		1000,
	)
	kineffi.Kine_Filament_SetCameraLookAt(
		filament,
		0, 4, 10,
		0, 0, 0,
		0, 1, 0,
	)

	running := true
	drawable := true
	frame_width, frame_height := width, height
	previous_ticks := sdl3.GetTicksNS()

	for running {
		event: sdl3.Event

		for sdl3.PollEvent(&event) {
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
				if event.window.data1 > 0 && event.window.data2 > 0 {
					frame_width = event.window.data1
					frame_height = event.window.data2
					drawable = true
					kineffi.Kine_Filament_Resize(filament, frame_width, frame_height)
					kineffi.Kine_Filament_SetCameraPerspective(
						filament,
						60,
						f64(frame_width)/f64(frame_height),
						0.1,
						1000,
					)
				}
			}
		}

		if !running || !drawable {
			continue
		}

		now := sdl3.GetTicksNS()
		delta_time := f32(now-previous_ticks)/1_000_000_000.0
		previous_ticks = now
		renderer.SkiaSurface = nil
		if renderer.Step != nil {
			renderer.Step(renderer.UserData, delta_time)
		}

		base_surface := kineffi.Kine_VulkanCompositor_BeginFrame(compositor)
		if base_surface == nil {
			error := kineffi.Kine_VulkanCompositor_GetLastError(compositor)
			fmt.eprintf("Vulkan frame acquisition failed: %s\n", error)
			break
		}

		if renderer.Draw3D != nil {
			renderer.Draw3D(renderer.UserData, filament, delta_time)
		}
		kineffi.Kine_Filament_RenderFrame(filament, delta_time)

		overlay := cast(^kineffi.KineSkiaSurface)kineffi.Kine_VulkanCompositor_BeginOverlay(compositor)
		renderer.SkiaSurface = overlay
		if overlay == nil {
			error := kineffi.Kine_VulkanCompositor_GetLastError(compositor)
			fmt.eprintf("Skia overlay acquisition failed: %s\n", error)
			break
		}
		if renderer.Draw2D != nil {
			renderer.Draw2D(renderer.UserData, overlay, frame_width, frame_height, delta_time)
		}
		kineffi.Kine_Skia_Surface_Flush(overlay)

		if kineffi.Kine_VulkanCompositor_EndFrame(compositor) == 0 {
			error := kineffi.Kine_VulkanCompositor_GetLastError(compositor)
			fmt.eprintf("Vulkan presentation failed: %s\n", error)
			break
		}
		renderer.SkiaSurface = nil
	}

	if renderer.OnClose != nil {
		renderer.OnClose()
	}
}

close :: proc(renderer: RendererObject, running: ^bool) {
    renderer.OnClose()
    running^ = false
}
