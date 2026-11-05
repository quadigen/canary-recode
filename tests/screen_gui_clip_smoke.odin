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

	ok, err = vm.Run(&script_vm, `
local screen = Instance.new("ScreenGui", game.StarterGui)
label = Instance.new("TextLabel", screen)
button = Instance.new("TextButton", screen)
for _, object in {label, button} do
	object.Size = UDim2.fromOffset(100, 60)
	object.TextSize = 16
	object.Text = "Wide text"
end
`, "text_cache_setup")
	assert(ok, err)
	for _ in 0 ..< 2 {
		engine_runtime.Environment_Render_Overlay(&environment, &script_vm, surface, 300, 300, 1.0 / 60.0)
	}
	ok, err = vm.Run(&script_vm, `
labelWidth = label.TextBounds.X
buttonWidth = button.TextBounds.X
assert(labelWidth > 0 and buttonWidth > 0)
label.Text = "i"
button.Text = "i"
`, "text_cache_update")
	assert(ok, err)
	engine_runtime.Environment_Render_Overlay(&environment, &script_vm, surface, 300, 300, 1.0 / 60.0)
	ok, err = vm.Run(&script_vm, `
assert(label.TextBounds.X > 0 and label.TextBounds.X < labelWidth)
assert(button.TextBounds.X > 0 and button.TextBounds.X < buttonWidth)
`, "text_cache_bounds")
	assert(ok, err)

	svg := "<svg xmlns='http://www.w3.org/2000/svg' width='4' height='4'><rect width='4' height='4' fill='red'/></svg>"
	icon := kineffi.Kine_Skia_Image_LoadFromMemory(raw_data(svg), uintptr(len(svg)))
	assert(icon != nil)
	defer kineffi.Kine_Skia_Image_Destroy(icon)
	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 0)
	kineffi.Kine_Skia_Surface_DrawImageSized(surface, icon, 10, 10, 8, 16, 255)
	kineffi.Kine_Skia_Surface_DrawImageSized(surface, icon, 30, 10, 16, 8, 128)
	expect_pixel(surface, 14, 18, true, true)
	expect_pixel(surface, 20, 18, false, false)
	expect_pixel(surface, 35, 14, true, false)

	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 0)
	kineffi.Kine_Skia_Surface_DrawSquircle(surface, 10, 10, 32, 24, 10, 4, 255, 0, 0, 255, 0)
	kineffi.Kine_Skia_Surface_DrawSquircle(surface, 10, 10, 32, 24, 10, 4, 255, 0, 0, 255, 0)
	kineffi.Kine_Skia_Surface_DrawSquircle(surface, 65, 10, 22, 24, 8, 5, 255, 0, 0, 255, 0)
	expect_pixel(surface, 24, 20, true, true)
	expect_pixel(surface, 75, 20, true, true)
	expect_pixel(surface, 50, 20, false, false)

	fmt.println("SCREEN_GUI_CLIP_SMOKE_PASSED")
}
