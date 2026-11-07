package main

import k "../src/engine/bindings"
import engine_runtime "../src/engine/runtime"
import renderer "../src/engine/renderer"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"
import sdl "vendor:sdl3"

main :: proc() {
	path := "/home/devcell/Documents/Construct 2/autosave.kine"
	if len(os.args) > 1 {path = os.args[1]}

	assert(sdl.Init({.VIDEO}))
	defer sdl.Quit()
	width, height: i32 = 640, 480
	w := sdl.CreateWindow(
		"Kinemium map render probe",
		width,
		height,
		sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN,
	)
	assert(w != nil)
	defer sdl.DestroyWindow(w)
	f := k.Kine_Filament_CreateForVulkanCompositorWindow(w, width, height)
	assert(f != nil)
	defer k.Kine_Filament_Destroy(f)
	compositor := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(f)
	assert(compositor != nil)

	ro := renderer.RendererObject {
		Filament = f,
	}
	ro.ViewportRect = {0, 0, width, height}
	ro.HasViewportRect = true
	v := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &v, &ro, .Editor)
	defer {
		vm.Close(&v)
		engine_runtime.Environment_Destroy(&env)
	}

	fmt.println("loading map", path)
	ok := engine_runtime.Load_Map(&env, &v, path)
	fmt.println("load ok =", ok)
	if !ok {os.exit(2)}

	for iteration in 0 ..< 12 {
		fmt.printf("frame %d: prepare\n", iteration)
		services.Prepare_3D(&env.services, &ro)
		base := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(compositor)
		if base == nil {
			fmt.printf("frame %d: BeginFrame FAILED\n", iteration)
			break
		}
		k.Kine_Skia_Surface_Clear(base, 20, 30, 40, 255)
		engine_runtime.Environment_Render_2D(&env, &v, base, width, height, 1.0 / 60.0)
		fmt.printf("frame %d: render3d\n", iteration)
		engine_runtime.Environment_Render_3D(&env, &v, 1.0 / 60.0)
		k.Kine_Filament_SetSun(f, -1, -1, -1, 100000)
		k.Kine_Filament_RenderFrame(f, 1.0 / 60.0)
		fmt.printf("frame %d: overlay\n", iteration)
		overlay := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginOverlay(compositor)
		if overlay == nil {
			fmt.printf("frame %d: BeginOverlay FAILED\n", iteration)
			break
		}
		engine_runtime.Environment_Render_Overlay(&env, &v, overlay, width, height, 1.0 / 60.0)
		fmt.printf("frame %d: end\n", iteration)
		if k.Kine_VulkanCompositor_EndFrame(compositor) == 0 {
			fmt.printf("frame %d: EndFrame FAILED\n", iteration)
			break
		}
		fmt.printf("frame %d: ok\n", iteration)
	}
	fmt.println("RENDER_PROBE_DONE")
}
