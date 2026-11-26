package main

import k "../src/engine/bindings"
import "core:fmt"
import sdl "vendor:sdl3"

frame :: proc(
	ctx: ^k.KineFilamentContext,
	compositor: ^k.KineVulkanCompositor,
) -> k.KineFilamentPassStats {
	base := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(compositor)
	assert(base != nil)
	k.Kine_Skia_Surface_Clear(base, 32, 40, 48, 255)
	k.Kine_Filament_RenderFrame(ctx, 1.0 / 60.0)
	passes: k.KineFilamentPassStats
	k.Kine_Filament_GetPassStats(ctx, &passes)
	overlay := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginOverlay(compositor)
	assert(overlay != nil)
	assert(k.Kine_VulkanCompositor_EndFrame(compositor) != 0)
	return passes
}

main :: proc() {
	assert(sdl.Init({.VIDEO}))
	defer sdl.Quit()
	window := sdl.CreateWindow(
		"Render pass work smoke",
		320,
		240,
		sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN,
	)
	assert(window != nil)
	defer sdl.DestroyWindow(window)
	ctx := k.Kine_Filament_CreateForVulkanCompositorWindow(window, 320, 240)
	assert(ctx != nil)
	defer k.Kine_Filament_Destroy(ctx)
	compositor := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(ctx)
	assert(compositor != nil)
	gi: [5]f32 = {0, 3, 0.02, 16, 40}
	fog: [12]f32 = {0, 10, 0, 100, 0, 0, 0, 1, 16, 1, 1, 1}
	chromatic: f32 = 0
	grain: [2]f32 = {0, 1}
	k.Kine_Filament_SetAdvancedEffect(ctx, 1, true, &gi[0], 5)
	k.Kine_Filament_SetAdvancedEffect(ctx, 7, true, &fog[0], 12)
	k.Kine_Filament_SetAdvancedEffect(ctx, 8, true, &chromatic, 1)
	k.Kine_Filament_SetAdvancedEffect(ctx, 9, true, &grain[0], 2)
	passes := frame(ctx, compositor)
	assert(passes.world == 1 && passes.sharedDepth == 0 && passes.screenEffects == 0)
	chromatic = 0.7
	k.Kine_Filament_SetAdvancedEffect(ctx, 8, true, &chromatic, 1)
	passes = frame(ctx, compositor)
	assert(passes.world == 1 && passes.sharedDepth == 0 && passes.screenEffects == 1)
	fog[0] = 0.5
	k.Kine_Filament_SetAdvancedEffect(ctx, 7, true, &fog[0], 12)
	passes = frame(ctx, compositor)
	assert(passes.world == 1 && passes.sharedDepth == 1 && passes.screenEffects == 1)
	fog[0] = 0
	chromatic = 0
	k.Kine_Filament_SetAdvancedEffect(ctx, 7, true, &fog[0], 12)
	k.Kine_Filament_SetAdvancedEffect(ctx, 8, true, &chromatic, 1)
	passes = frame(ctx, compositor)
	assert(passes.world == 1 && passes.sharedDepth == 0 && passes.screenEffects == 0)
	fmt.println("RENDER_PASS_WORK_PASSED")
}
