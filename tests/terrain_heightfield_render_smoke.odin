package main

import k "../src/engine/bindings"
import "core:fmt"
import "core:math"
import "core:os"
import "core:time"
import sdl "vendor:sdl3"
import image "vendor:stb/image"

WIDTH :: 960
HEIGHT :: 360
HALF_GRID_X :: 37
HALF_GRID_Z :: 26
GRID_WIDTH :: 2 * HALF_GRID_X + 3
GRID_DEPTH :: 2 * HALF_GRID_Z + 3
PLATEAU_HEIGHT :: f32(15)
SHOULDER_WIDTH :: f32(14)
OUTPUT :: "build/terrain_heightfield.png"

Vertex :: [8]f32 // position, normal, UV

height_at :: proc(x, z: f32) -> f32 {
	// Distance outside the flat top's rectangle gives the shoulders round corners.
	dx := max(abs(x) - 22, 0)
	dz := max(abs(z) - 11, 0)
	t := clamp(math.sqrt(dx * dx + dz * dz) / SHOULDER_WIDTH, 0, 1)
	// Quintic easing gives both the top and the ground a flat tangent.
	return PLATEAU_HEIGHT * (1 - t * t * t * (t * (6 * t - 15) + 10))
}

grid_coordinate :: proc(index, half: int) -> f32 {
	// Stretch the last flat quad on each side to cover the background.
	if index == 0 {return -400}
	if index == 2 * half + 2 {return 400}
	return f32(index - half - 1)
}

build_mesh :: proc(vertices: []Vertex, indices: []u16) {
	for row in 0 ..< GRID_DEPTH {
		z := grid_coordinate(row, HALF_GRID_Z)
		for col in 0 ..< GRID_WIDTH {
			x := grid_coordinate(col, HALF_GRID_X)
			eps :: f32(0.05)
			nx := (height_at(x - eps, z) - height_at(x + eps, z)) / (2 * eps)
			nz := (height_at(x, z - eps) - height_at(x, z + eps)) / (2 * eps)
			inv_length := 1 / math.sqrt(nx * nx + 1 + nz * nz)
			vertices[row * GRID_WIDTH + col] = {
				x, height_at(x, z), z, nx * inv_length, inv_length, nz * inv_length, x / 6, z / 6,
			}
		}
	}
	for row in 0 ..< GRID_DEPTH - 1 {
		for col in 0 ..< GRID_WIDTH - 1 {
			a := u16(row * GRID_WIDTH + col)
			b := a + 1
			c := a + GRID_WIDTH
			d := c + 1
			offset := (row * (GRID_WIDTH - 1) + col) * 6
			indices[offset + 0] = a
			indices[offset + 1] = c
			indices[offset + 2] = b
			indices[offset + 3] = b
			indices[offset + 4] = c
			indices[offset + 5] = d
		}
	}
}

check_mesh :: proc(vertices: []Vertex, indices: []u16) -> f32 {
	assert(height_at(22, 11) == PLATEAU_HEIGHT)
	assert(height_at(22 + SHOULDER_WIDTH, 11) == 0)
	assert(height_at(22 + SHOULDER_WIDTH / 2, 11) == PLATEAU_HEIGHT / 2)
	max_error: f32
	for i := 0; i < len(indices); i += 3 {
		a, b, c := vertices[indices[i]], vertices[indices[i + 1]], vertices[indices[i + 2]]
		assert((b[2] - a[2]) * (c[0] - a[0]) - (b[0] - a[0]) * (c[2] - a[2]) > 0)
		x := (a[0] + b[0] + c[0]) / 3
		y := (a[1] + b[1] + c[1]) / 3
		z := (a[2] + b[2] + c[2]) / 3
		max_error = max(max_error, abs(y - height_at(x, z)))
	}
	return max_error
}

render_preview :: proc(vertices: []Vertex, indices: []u16) {
	assert(sdl.Init({.VIDEO}))
	defer sdl.Quit()
	window := sdl.CreateWindow(
		"Continuous terrain",
		WIDTH,
		HEIGHT,
		sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN,
	)
	assert(window != nil)
	defer sdl.DestroyWindow(window)
	ctx := k.Kine_Filament_CreateForVulkanCompositorWindow(window, WIDTH, HEIGHT)
	assert(ctx != nil)
	defer k.Kine_Filament_Destroy(ctx)
	compositor := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(ctx)
	assert(compositor != nil)

	mesh := k.Kine_Filament_CreateCustomMesh(
		ctx, &vertices[0][0], i32(len(vertices)), raw_data(indices), i32(len(indices)),
	)
	assert(mesh != nil)
	defer k.Kine_Filament_DestroyMesh(ctx, mesh)
	checker: [32 * 32][4]u8
	for y in 0 ..< 32 {
		for x in 0 ..< 32 {
			shade := u8((x / 16 + y / 16) % 2 == 0 ? 185 : 115)
			checker[y * 32 + x] = {shade, shade, shade, 255}
		}
	}
	tex := k.Kine_Filament_CreateTexFromPixels(ctx, 32, 32, 32 * 4, &checker[0])
	assert(tex != nil)
	defer k.Kine_Filament_DestroyTex(ctx, tex)

	item := k.KineFilamentDrawItem {
		mesh         = mesh,
		tex          = tex,
		transform    = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1},
		r            = 1,
		g            = 1,
		b            = 1,
		param1       = 0.9,
		materialKind = k.KINE_MAT_DEFAULT,
		flags        = k.KINE_FILAMENT_DRAW_CULLING,
	}
	k.Kine_Filament_SetCameraPerspective(ctx, 32, f64(WIDTH) / HEIGHT, 0.1, 800)
	k.Kine_Filament_SetCameraLookAt(ctx, 21, 7, 60, 0, 7, 0, 0, 1, 0)
	k.Kine_Filament_SetViewport(ctx, 0, 0, WIDTH, HEIGHT)
	k.Kine_Filament_SetPostProcessing(ctx, false)
	k.Kine_Filament_CreateSky(ctx, 0.33, 0.46, 0.64, 1)
	k.Kine_Filament_SetSun(ctx, -0.5, 1, 0.65, 85000)

	pixels := make([][3]u8, WIDTH * HEIGHT)
	defer delete(pixels)
	for frame in 0 ..< 4 {
		base := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(compositor)
		assert(base != nil)
		k.Kine_Skia_Surface_Clear(base, 154, 177, 202, 255)
		k.Kine_Filament_DrawMeshListVersioned(ctx, &item, 1, 1, 1)
		k.Kine_Filament_RenderFrame(ctx, 1.0 / 60)
		overlay := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginOverlay(compositor)
		assert(overlay != nil)
		if frame == 3 {
			for y in 0 ..< HEIGHT {
				for x in 0 ..< WIDTH {
					p := &pixels[y * WIDTH + x]
					alpha: u8
					k.Kine_Skia_Surface_GetPixel(overlay, i32(x), i32(y), &p[0], &p[1], &p[2], &alpha)
				}
			}
		}
		assert(k.Kine_VulkanCompositor_EndFrame(compositor) != 0)
	}

	if err := os.make_directory_all("build"); err != nil {
		assert(os.is_directory("build"))
	}
	assert(image.write_png(OUTPUT, WIDTH, HEIGHT, 3, raw_data(pixels), WIDTH * 3) != 0)
	sky := pixels[WIDTH / 2]
	assert(int(sky[2]) - int(sky[0]) > 20, "sky must be visible above the plateau")
	light, dark := 0, 255
	for y in HEIGHT / 3 ..< HEIGHT / 2 {
		for x in WIDTH / 3 ..< 2 * WIDTH / 3 {
			pixel := pixels[y * WIDTH + x]
			if abs(int(pixel[0]) - int(pixel[2])) < 16 {
				light = max(light, int(pixel[0]))
				dark = min(dark, int(pixel[0]))
			}
		}
	}
	assert(light - dark > 20, "the plateau must show checker contrast")
}

main :: proc() {
	vertices := make([]Vertex, GRID_WIDTH * GRID_DEPTH)
	defer delete(vertices)
	indices := make([]u16, (GRID_WIDTH - 1) * (GRID_DEPTH - 1) * 6)
	defer delete(indices)

	start := time.tick_now()
	build_mesh(vertices, indices)
	build_ms := f64(time.tick_since(start)) / f64(time.Millisecond)
	max_error := check_mesh(vertices, indices)
	fmt.printf(
		"%d vertices, %d triangles, CPU build %.3f ms, max centroid height error %.4f\n",
		len(vertices), len(indices) / 3, build_ms, max_error,
	)
	assert(max_error < 0.1, "mesh must follow the continuous height profile")
	render_preview(vertices, indices)
	fmt.println("TERRAIN_HEIGHTFIELD_RENDER_SMOKE_PASSED", OUTPUT)
}
