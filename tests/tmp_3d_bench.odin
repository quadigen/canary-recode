package main

import "core:fmt"
import "core:os"
import "core:time"
import k "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import sdl "vendor:sdl3"

strconv_atoi :: proc(text: string) -> (int, bool) {
	value := 0
	if len(text) == 0 {return 0, false}
	for c in text {
		if c < '0' || c > '9' {return 0, false}
		value = value * 10 + int(c - '0')
	}
	return value, true
}

FRAMES :: 48
WARMUP :: 8

main :: proc() {
	assert(sdl.Init({.VIDEO}))
	defer sdl.Quit()
	window := sdl.CreateWindow(
		"3d bench",
		640,
		480,
		sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN,
	)
	assert(window != nil)
	defer sdl.DestroyWindow(window)
	ctx := k.Kine_Filament_CreateForVulkanCompositorWindow(window, 640, 480)
	assert(ctx != nil)
	defer k.Kine_Filament_Destroy(ctx)
	view := renderer.RendererObject {
		Filament        = ctx,
		HasViewportRect = true,
		ViewportRect    = {0, 0, 640, 480},
		RenderFilament  = true,
	}
	v := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &v, &view)
	defer {
		vm.Close(&v)
		engine_runtime.Environment_Destroy(&env)
	}

	part_count := 800
	if value := os.get_env_alloc("BENCH_PARTS", context.allocator); len(value) > 0 {
		if parsed, parse_ok := strconv_atoi(value); parse_ok {part_count = parsed}
	}

	setup := fmt.aprintf(`
workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
workspace.CurrentCamera.CFrame = CFrame.new(60, 45, 60) * CFrame.Angles(-0.6, 0.75, 0)
workspace.CurrentCamera.FieldOfView = 70
parts = {}
for i = 1, %d do
    local part = Instance.new("Part", workspace)
    part.Name = "Bench" .. i
    part.Anchored = true
    part.Size = Vector3.new(2, 2, 2)
    part.CFrame = CFrame.new((i % 32) * 3, (i % 7) * 2, math.floor(i / 32) * 3)
    parts[i] = part
end
`, part_count)
	ok, err := vm.Run(&v, setup, "3d_bench")
	delete(setup)
	if !ok {
		fmt.eprintln(err)
		panic("setup failed")
	}

	workspace := cast(^services.Workspace)services.Ensure_Service(&env.services, "Workspace")
	parts: [dynamic]^classes.Part
	defer delete(parts)
	for child in workspace.object.children {
		if child != nil && classes.Is_A_Class(child, &classes.Part_Class) {
			append(&parts, cast(^classes.Part)child)
		}
	}
	fmt.printfln("parts=%d", len(parts))

	compositor := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(ctx)
	total_draw3d, total_filament, total_present: f64
	measured := 0

	for frame in 0 ..< FRAMES {
		// Move every part so the scene is genuinely animated every frame.
		for part, index in parts {
			part.cframe.x += f32(index % 3) * 0.01
			part.cframe.y += 0.005 * f32((frame % 5) - 2)
		}

		services.Prepare_3D(&env.services, &view)
		base := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(compositor)
		assert(base != nil)
		k.Kine_Skia_Surface_Clear(base, 20, 28, 41, 255)

		engine_runtime.Environment_Render_2D(&env, &v, base, 640, 480, 1.0 / 60.0)

		t0 := time.tick_now()
		engine_runtime.Environment_Render_3D(&env, &v, 1.0 / 60.0)
		t1 := time.tick_now()
		k.Kine_Filament_RenderFrame(ctx, 1.0 / 60.0)
		t2 := time.tick_now()
		overlay := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginOverlay(compositor)
		assert(overlay != nil)
		engine_runtime.Environment_Render_Overlay(&env, &v, overlay, 640, 480, 1.0 / 60.0)
		assert(k.Kine_VulkanCompositor_EndFrame(compositor) != 0)
		t3 := time.tick_now()

		if frame >= WARMUP {
			measured += 1
			total_draw3d += f64(time.tick_since(t0)) / 1e6
			total_filament += f64(time.tick_since(t1)) / 1e6
			total_present += f64(time.tick_since(t2)) / 1e6
		}
	}
	fmt.printfln(
		"items=%d draw3d=%.2fms filament=%.2fms overlay+present=%.2fms",
		len(workspace.draw_items),
		total_draw3d / f64(measured),
		total_filament / f64(measured),
		total_present / f64(measured),
	)
	fmt.println("TMP_3D_BENCH_DONE")
}
