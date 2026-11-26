package main

import kineffi "../src/engine/bindings"
import "core:fmt"
import sdl3 "vendor:sdl3"

main :: proc() {
	assert(sdl3.Init({.VIDEO}))
	defer sdl3.Quit()
	window := sdl3.CreateWindow(
		"Viewport budget smoke",
		320,
		240,
		sdl3.WINDOW_VULKAN | sdl3.WINDOW_HIDDEN,
	)
	assert(window != nil)
	defer sdl3.DestroyWindow(window)
	filament := kineffi.Kine_Filament_CreateForVulkanCompositorWindow(window, 320, 240)
	assert(filament != nil)
	defer kineffi.Kine_Filament_Destroy(filament)
	compositor := cast(^kineffi.KineVulkanCompositor)kineffi.Kine_Filament_GetVulkanCompositor(
		filament,
	)
	assert(compositor != nil)
	previews: [8]^kineffi.KineFilamentViewport
	defer {
		for preview in previews {
			if preview != nil {kineffi.Kine_Filament_Viewport_Destroy(preview)}
		}
	}
	settings := kineffi.KineViewportSettings {
		camera         = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 6, 0, 0, 0, 1},
		ambient        = {1, 1, 1},
		lightColor     = {1, 1, 1},
		lightDirection = {-1, -1, -1},
		fieldOfView    = 60,
		width          = 64,
		height         = 64,
	}
	for i in 0 ..< len(previews) {
		previews[i] = kineffi.Kine_Filament_Viewport_Create(filament)
		assert(previews[i] != nil)
	}
	mesh := kineffi.Kine_Filament_Viewport_Primitive(filament, kineffi.KINE_MESH_CUBE)
	assert(mesh != nil)
	item := kineffi.KineFilamentDrawItem {
		mesh         = mesh,
		transform    = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1},
		r            = 1,
		transmission = 1,
	}
	previous, previous_reused: u64
	for frame in 0 ..< 6 {
		base := cast(^kineffi.KineSkiaSurface)kineffi.Kine_VulkanCompositor_BeginFrame(compositor)
		assert(base != nil)
		kineffi.Kine_Skia_Surface_Clear(base, 20, 30, 40, 255)
		kineffi.Kine_Filament_Viewport_Begin(filament)
		for preview, index in previews {
			if frame == 0 || frame == 3 {
				settings.fieldOfView = 60 + f32(index) if frame == 0 else 45
				assert(kineffi.Kine_Filament_Viewport_Update(preview, &settings, &item, 1, 1))
			} else {
				kineffi.Kine_Filament_Viewport_Touch(preview)
			}
		}
		if kineffi.Kine_Filament_Viewport_HasWork(filament) {
			kineffi.Kine_Filament_Viewport_RenderFrame(filament, 1.0 / 60.0, false)
			passes: kineffi.KineFilamentPassStats
			kineffi.Kine_Filament_GetPassStats(filament, &passes)
			assert(passes.world == 0 && passes.viewportCopy == 4 && passes.viewportPresent == 1)
			assert(passes.viewportScene == (4 if frame < 2 else 1 if frame == 3 else 0))
		}
		current: u64
		kineffi.Kine_Filament_Viewport_Stats(filament, nil, nil, &current)
		reused := kineffi.Kine_Filament_Viewport_ReusedRenders(filament)
		expected := u64(4) if frame < 2 else 1 if frame == 3 else 0
		expected_reused := u64(3) if frame == 3 else 4 if frame == 4 else 0
		assert(current - previous == expected, "viewport budget or cached result failed")
		assert(
			reused - previous_reused == expected_reused,
			"identical previews did not reuse scratch",
		)
		previous = current
		previous_reused = reused
		assert(kineffi.Kine_VulkanCompositor_EndFrame(compositor) != 0)
	}
	assert(kineffi.Kine_Filament_Viewport_PersistentReuses(filament) == 4)
	fmt.println("VIEWPORT_NATIVE_BUDGET_PASSED")
}
