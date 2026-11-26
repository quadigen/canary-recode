package main

import k "../src/engine/bindings"
import renderer "../src/engine/renderer"
import runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import sdl "vendor:sdl3"

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.RunInternal(v, source, "part_surface_render_smoke")
	assert(ok, err)
}

render :: proc(env: ^runtime.Environment, v: ^vm.VM) {
	ctx := env.renderer.Filament
	comp := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(ctx)
	services.Prepare_3D(&env.services, env.renderer)
	base := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(comp)
	assert(base != nil)
	k.Kine_Skia_Surface_Clear(base, 0, 0, 0, 255)
	runtime.Environment_Render_2D(env, v, base, 320, 240, 1.0 / 60)
	runtime.Environment_Render_3D(env, v, 1.0 / 60)
	k.Kine_Filament_RenderFrame(ctx, 1.0 / 60)
	overlay := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginOverlay(comp)
	assert(overlay != nil)
	runtime.Environment_Render_Overlay(env, v, overlay, 320, 240, 1.0 / 60)
	assert(k.Kine_VulkanCompositor_EndFrame(comp) != 0)
}

main :: proc() {
	assert(sdl.Init({.VIDEO}))
	defer sdl.Quit()
	window := sdl.CreateWindow("Part surface smoke", 320, 240, sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN)
	assert(window != nil)
	defer sdl.DestroyWindow(window)
	ctx := k.Kine_Filament_CreateForVulkanCompositorWindow(window, 320, 240)
	assert(ctx != nil)
	defer k.Kine_Filament_Destroy(ctx)
	view := renderer.RendererObject{Filament = ctx, HasViewportRect = true, ViewportRect = {0, 0, 320, 240}}
	v := vm.New()
	env: runtime.Environment
	runtime.Environment_Init(&env, &v, &view)
	defer {vm.Close(&v); runtime.Environment_Destroy(&env)}
	run(&v, `
workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
workspace.CurrentCamera.CFrame = CFrame.lookAt(Vector3.new(6, 6, 8), Vector3.zero)
p = Instance.new("Part", workspace)
p.Size = Vector3.new(4, 2, 6)
p.Anchored = true
p.Color = Color3.new(0.4, 0.5, 0.6)
p.TopSurface = Enum.SurfaceType.Studs
p.BottomSurface = Enum.SurfaceType.Inlet
p.FrontSurface = Enum.SurfaceType.Glue
p.BackSurface = Enum.SurfaceType.Universal
`)
	ws := cast(^services.Workspace)services.Ensure_Service(&env.services, "Workspace")
	render(&env, &v)
	assert(len(ws.draw_items) == 5)
	for item in ws.draw_items[1:] {
		assert(item.mesh == ws.surface_mesh && item.tex != nil && item.param3 == -1)
		assert(item.r == ws.draw_items[0].r && item.g == ws.draw_items[0].g)
	}
	for texture in ws.surface_textures {assert(texture != nil)}
	version := ws.draw_version
	run(&v, `p.TopSurface = Enum.SurfaceType.Smooth; p.Size = Vector3.new(8, 2, 6)`)
	render(&env, &v)
	assert(len(ws.draw_items) == 4 && ws.draw_version > version)
	run(&v, `p.TopSurface = Enum.SurfaceType.Inlet`)
	render(&env, &v)
	assert(len(ws.draw_items) == 5)
	run(&v, `p:Destroy()`)
	render(&env, &v)
	assert(len(ws.draw_items) == 0)
	fmt.println("PART_SURFACE_RENDER_SMOKE_PASSED")
}
