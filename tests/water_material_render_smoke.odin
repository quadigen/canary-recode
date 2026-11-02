package main
import k "../src/engine/bindings"
import "core:fmt"
import "core:math"
import "core:os"
import sdl "vendor:sdl3"
main :: proc() {
	assert(sdl.Init({.VIDEO})); defer sdl.Quit()
	window := sdl.CreateWindow(
		"Water shader preview",
		320,
		256,
		sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN,
	); assert(window != nil); defer sdl.DestroyWindow(window)
	ctx := k.Kine_Filament_CreateForVulkanCompositorWindow(
		window,
		320,
		256,
	); assert(ctx != nil); defer k.Kine_Filament_Destroy(ctx)
	if len(os.args) > 2 && os.args[2] == "still" {
		params: k.KineFilamentWaterParams
		assert(k.Kine_Filament_GetWaterParams(ctx, &params))
		params.speed = 0; params.strength = 0; params.foamAmount = 0
		k.Kine_Filament_SetWaterParams(ctx, &params)
	}
	compositor := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(ctx)
	vp := k.Kine_Filament_Viewport_Create(
		ctx,
	); assert(vp != nil); defer k.Kine_Filament_Viewport_Destroy(vp)
	cube := k.Kine_Filament_Viewport_Primitive(ctx, k.KINE_MESH_CUBE)
	water := k.Kine_Filament_Viewport_Primitive(ctx, k.KINE_MESH_WATER_GRID)
	items: [6]k.KineFilamentDrawItem
	for &item in items {item.mesh = cube; item.transform[0] = 1; item.transform[5] = 1; item.transform[10] = 1; item.transform[15] = 1; item.r = .8; item.g = .8; item.b = .8; item.param1 = .8; item.flags = 3; item.transmission = 1}
	items[0].transform[0] = 44; items[0].transform[5] = 2; items[0].transform[10] = 44; items[0].transform[7] = -2
	items[1].mesh =
		water; items[1].materialKind = k.KINE_MAT_WATER; items[1].r = .75; items[1].g = .9; items[1].b = 1
	items[1].transform[0] = 36; items[1].transform[10] = 36; items[1].transform[7] = -.5
	items[1].param1 = .08; items[1].param2 = 1.333; items[1].param3 = .12; items[1].transmission = .88
	items[2].transform[0] = 40; items[2].transform[5] = 4; items[2].transform[10] = 2; items[2].transform[7] = 1; items[2].transform[11] = -19
	items[3].transform[0] = 2; items[3].transform[5] = 4; items[3].transform[10] = 40; items[3].transform[3] = -19; items[3].transform[7] = 1
	items[4].transform[0] = 6; items[4].transform[5] = 1; items[4].transform[10] = 7; items[4].transform[3] = 6; items[4].transform[7] = -1; items[4].r = .5; items[4].g = .3; items[4].b = .2
	items[5].transform[0] = 3; items[5].transform[5] = 5; items[5].transform[10] = 3; items[5].transform[3] = -7; items[5].transform[7] = .5; items[5].transform[11] = -5
	settings := k.KineViewportSettings {
		fieldOfView    = 45,
		width          = 320,
		height         = 256,
		ambient        = {.65, .65, .65},
		lightColor     = {1, 1, 1},
		lightDirection = {-1, -2, -1},
		shadows        = 1,
		postProcessing = 1,
	}
	normalize :: proc(v: [3]f32) -> [3]f32 {return(
			v /
			f32(math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])) \
		)}
	back := normalize(
		[3]f32{25, 31, 37},
	); right := normalize([3]f32{back[2], 0, -back[0]}); up := [3]f32{back[1] * right[2], back[2] * right[0] - back[0] * right[2], -back[1] * right[0]}
	settings.camera = {
		right[0],
		up[0],
		back[0],
		25,
		right[1],
		up[1],
		back[1],
		31,
		right[2],
		up[2],
		back[2],
		37,
		0,
		0,
		0,
		1,
	}
	output := make([]u8, 320 * 256 * 3); defer delete(output)
	before := make([]u8, len(output)); defer delete(before)
	for iteration in 0 ..< 4 {
		k.Kine_Filament_SetWaterTime(ctx, iteration < 2 ? 0 : 2)
		base := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(
			compositor,
		); assert(base != nil); k.Kine_Skia_Surface_Clear(base, 180, 193, 205, 255)
		k.Kine_Filament_Viewport_Begin(ctx)
		assert(
			k.Kine_Filament_Viewport_Update(
				vp,
				&settings,
				&items[0],
				u32(len(items)),
				u64(iteration + 1),
			),
		)
		k.Kine_Filament_Viewport_RenderFrame(ctx, 1.0 / 30.0, false)
		overlay := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginOverlay(
			compositor,
		); assert(overlay != nil)
		k.Kine_Filament_Viewport_Draw(vp, overlay, 0, 0, 320, 256, 1, 1, 1, 1)
		if iteration == 1 || iteration == 3 {
			for y in 0 ..< 256 {for x in 0 ..< 320 {
					r, g, b, a: u8; k.Kine_Skia_Surface_GetPixel(overlay, i32(x), i32(y), &r, &g, &b, &a)
					offset := (y * 320 + x) * 3
					if iteration ==
					   1 {before[offset] = r; before[offset + 1] = g; before[offset + 2] = b} else {output[offset] = r; output[offset + 1] = g; output[offset + 2] = b}
				}}
		}
		assert(k.Kine_VulkanCompositor_EndFrame(compositor) != 0)
	}
	blue_pixels := 0
	for i in 0 ..< len(output) / 3 {
		if int(output[i * 3 + 2]) > int(output[i * 3]) + 40 &&
		   int(output[i * 3 + 2]) > int(output[i * 3 + 1]) + 8 {blue_pixels += 1}
	}
	assert(blue_pixels > 1000, "water did not render its blue surface")
	if !(len(os.args) > 2 && os.args[2] == "still") {
		changed := 0
		for i in 0 ..< len(output) / 3 {
			difference := 0
			for channel in 0 ..< 3 {difference += abs(int(output[i * 3 + channel]) - int(before[i * 3 + channel]))}
			if difference > 30 {changed += 1}
		}
		assert(changed > 100, "Gerstner waves did not animate the rendered water")
	}
	if len(os.args) > 1 {
		filename := os.args[1]
		f, err := os.create(filename); assert(err == nil); defer os.close(f)
		header := "P6\n320 256\n255\n"; _, _ = os.write(f, transmute([]u8)header); _, _ = os.write(f, output)
	}
	fmt.println("WATER_MATERIAL_RENDER_PASSED", blue_pixels, "blue pixels")
}
