package main

import kineffi "../src/engine/bindings"
import native "../src/engine/renderer/compositor"
import "core:fmt"
import sdl "vendor:sdl3"

main :: proc() {
	assert(sdl.Init({.VIDEO}))
	defer sdl.Quit()
	modes := [?]bool{false, true}
	for offscreen in modes {
		window := sdl.CreateWindow(
			"Native lifecycle smoke",
			320,
			240,
			sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN | sdl.WINDOW_RESIZABLE,
		)
		assert(window != nil)
		defer sdl.DestroyWindow(window)
		id := u32(sdl.GetWindowID(window))
		assert(native.register_swapchain(id, offscreen))
		compositor := kineffi.Kine_VulkanCompositor_CreateForSDLWindow(window, 320, 240)
		native.unregister_swapchain(id)
		assert(compositor != nil)
		defer kineffi.Kine_VulkanCompositor_Destroy(compositor)
		assert(
			kineffi.Kine_VulkanCompositor_IsReady(compositor) != 0,
			string(kineffi.Kine_VulkanCompositor_GetLastError(compositor)),
		)
		assert(kineffi.Kine_VulkanCompositor_UsesOdinBackend(compositor) != 0)
		state: native.Backend
		assert(native.attach(&state, compositor))
		defer native.detach(&state)
		sizes := [?]i32{320, 480}
		for size in sizes {
			assert(sdl.SetWindowSize(window, size, 240))
			assert(sdl.SyncWindow(window))
			sdl.PumpEvents()
			w, h: i32
			assert(sdl.GetWindowSizeInPixels(window, &w, &h))
			assert(kineffi.Kine_VulkanCompositor_Resize(compositor, w, h) != 0)
			assert(kineffi.Kine_VulkanCompositor_UsesOdinBackend(compositor) != 0)
			depth: rawptr
			format: u32
			assert(
				kineffi.Kine_VulkanCompositor_GetDepthAttachment(compositor, &depth, &format) != 0,
			)
			assert(depth != nil && format != 0)
			for _ in 0 ..< 12 {
				base := cast(^kineffi.KineSkiaSurface)kineffi.Kine_VulkanCompositor_BeginFrame(
					compositor,
				)
				assert(base != nil)
				kineffi.Kine_Skia_Surface_Clear(base, 20, 40, 60, 255)
				assert(kineffi.Kine_VulkanCompositor_EndFrame(compositor) != 0)
			}
		}
		assert(kineffi.Kine_VulkanCompositor_WaitForQueueIdle(compositor) != 0)
		fmt.println("NATIVE_OWNED_DEVICE_LIFECYCLE_PASSED", offscreen)
	}
}
