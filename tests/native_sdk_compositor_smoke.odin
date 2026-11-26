package main

import target "../src/engine/target"
import sdk "../src/shared_library"
import "core:fmt"
import sdl "vendor:sdl3"

main :: proc() {
	assert(sdl.Init({.VIDEO}))
	defer sdl.Quit()
	window := sdl.CreateWindow(
		"SDK compositor smoke",
		320,
		240,
		sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN | sdl.WINDOW_RESIZABLE,
	)
	assert(window != nil)
	defer sdl.DestroyWindow(window)
	ctx := sdk.Kinemium_CreateForSDLWindow(window, 320, 240, i32(target.Mode.Singleplayer))
	assert(ctx != nil)
	defer sdk.Kinemium_Destroy(ctx)
	owned := sdk.owned_context(ctx)
	assert(owned != nil && owned.compositor_backend.attached)
	for _ in 0 ..< 20 {
		assert(sdk.Kinemium_RenderFrame(ctx, 1.0 / 60.0))
	}
	assert(sdl.SetWindowSize(window, 480, 320))
	assert(sdl.SyncWindow(window))
	sdl.PumpEvents()
	w, h: i32
	assert(sdl.GetWindowSizeInPixels(window, &w, &h))
	assert(sdk.Kinemium_ResizeRenderer(ctx, w, h))
	for _ in 0 ..< 20 {
		assert(sdk.Kinemium_RenderFrame(ctx, 1.0 / 60.0))
	}
	fmt.println("SDK_NATIVE_COMPOSITOR_PASSED")
}
