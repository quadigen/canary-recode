package main

import kineffi "../src/engine/bindings"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

expect_pixel :: proc(surface: ^kineffi.KineSkiaSurface, x, y: i32, red, opaque: bool) {
	r, g, b, a: u8
	kineffi.Kine_Skia_Surface_GetPixel(surface, x, y, &r, &g, &b, &a)
	is_red := r == 255 && g == 0 && b == 0
	assert(is_red == red, fmt.tprintf("pixel %d,%d red=%v want %v", x, y, is_red, red))
	assert(
		(a == 255) == opaque,
		fmt.tprintf("pixel %d,%d alpha=%d want opaque=%v", x, y, a, opaque),
	)
}

main :: proc() {
	script_vm := vm.New()
	renderer_object: renderer.RendererObject
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm, &renderer_object)
	defer {
		vm.Close(&script_vm)
		engine_runtime.Environment_Destroy(&environment)
	}


	ok, err := vm.Run(
		&script_vm,
		`
local screen = Instance.new("ScreenGui", game.StarterGui)
screen.Name = "Hud"
screen.Size = Vector2.new(100, 80)
screen.RenderOffset = Vector2.new(40, 30)

local frame = Instance.new("Frame", screen)
frame.Position = UDim2.fromOffset(-50, -50)
frame.Size = UDim2.fromOffset(300, 300)
frame.BackgroundColor3 = Color3.new(1, 0, 0)
frame.BackgroundTransparency = 0
`,
		"screen_gui_clip_setup",
	)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("ScreenGui clip setup failed")
	}

	surface := kineffi.Kine_Skia_Surface_Create(300, 300)
	if surface == nil {panic("Skia surface creation failed")}
	defer kineffi.Kine_Skia_Surface_Destroy(surface)
	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 0)

	engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, 300, 300, 1.0 / 60.0)
	engine_runtime.Environment_Render_Overlay(
		&environment,
		&script_vm,
		surface,
		300,
		300,
		1.0 / 60.0,
	)
	kineffi.Kine_Skia_Surface_Flush(surface)

	expect_pixel(surface, 60, 50, true, true)

	expect_pixel(surface, 30, 50, false, false)
	expect_pixel(surface, 50, 20, false, false)
	expect_pixel(surface, 150, 50, false, false)
	expect_pixel(surface, 50, 120, false, false)
	expect_pixel(surface, 200, 200, false, false)

	fmt.println("SCREEN_GUI_CLIP_SMOKE_PASSED")
}
