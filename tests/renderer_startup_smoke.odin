package main

import kineffi "../src/engine/bindings"
import sdl3 "vendor:sdl3"
import "core:fmt"

render_compositor_frame :: proc(
	filament: ^kineffi.KineFilamentContext,
	compositor: ^kineffi.KineVulkanCompositor,
) {
	if kineffi.Kine_VulkanCompositor_BeginFrame(compositor) == nil {
		panic("Vulkan compositor frame acquisition failed")
	}
	kineffi.Kine_Filament_RenderFrame(filament, 1.0/60.0)
	overlay := cast(^kineffi.KineSkiaSurface)kineffi.Kine_VulkanCompositor_BeginOverlay(compositor)
	if overlay == nil { panic("Skia overlay acquisition failed") }
	kineffi.Kine_Skia_Surface_Flush(overlay)
	if kineffi.Kine_VulkanCompositor_EndFrame(compositor) == 0 {
		panic("Vulkan compositor presentation failed")
	}
}

main :: proc() {
	if !sdl3.Init({.VIDEO}) { panic("SDL init failed") }
	defer sdl3.Quit()
	window := sdl3.CreateWindow("Kinemium renderer smoke", 320, 240, sdl3.WINDOW_VULKAN | sdl3.WINDOW_HIDDEN | sdl3.WINDOW_RESIZABLE)
	if window == nil { panic("SDL window failed") }
	defer sdl3.DestroyWindow(window)

	filament := kineffi.Kine_Filament_CreateForSDLWindow(rawptr(window), 320, 240)
	if filament == nil { panic("Filament startup failed") }
	kineffi.Kine_Filament_RenderFrame(filament, 1.0/60.0)
	kineffi.Kine_Filament_Destroy(filament)

	owned := kineffi.Kine_Filament_CreateForVulkanCompositorWindow(window, 320, 240)
	if owned == nil { panic("Filament compositor startup failed") }
	defer kineffi.Kine_Filament_Destroy(owned)

	compositor := cast(^kineffi.KineVulkanCompositor)kineffi.Kine_Filament_GetVulkanCompositor(owned)
	if compositor == nil || kineffi.Kine_VulkanCompositor_IsReady(compositor) == 0 {
		panic("Vulkan compositor is not ready")
	}
	render_compositor_frame(owned, compositor)

	for _ in 0..<8 {
		render_compositor_frame(owned, compositor)
	}
	sizes := [][2]i32{{640, 360}, {480, 640}, {900, 500}, {320, 240}, {800, 600}}
	for size in sizes {
		assert(sdl3.SetWindowSize(window, size[0], size[1]))
		sdl3.PumpEvents()
		width, height: i32
		assert(sdl3.GetWindowSizeInPixels(window, &width, &height))
		kineffi.Kine_Filament_Resize(owned, width, height)
		info: kineffi.KineVulkanCompositorInfo
		assert(kineffi.Kine_VulkanCompositor_GetInfo(compositor, &info) != 0)
		assert(info.width == u32(width) && info.height == u32(height))
		for _ in 0..<8 { render_compositor_frame(owned, compositor) }
		fmt.printf("RESIZE_PASSED %dx%d\n", width, height)
	}
	fmt.println("RENDERER_RESIZE_SMOKE_PASSED")
}
