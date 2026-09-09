package main

import "core:fmt"
import kineffi "../src/engine/bindings"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

main :: proc() {
	script_vm := vm.New()
	renderer_object: renderer.RendererObject
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm, &renderer_object)

	ok, err := vm.Run(&script_vm, `
local screenGui = Instance.new("ScreenGui")
gui = Instance.new("Frame", screenGui)
assert(gui.Size == UDim2.fromOffset(100, 100))
assert(gui.BackgroundColor3 == Color3.new(1, 1, 1))
assert(gui.BackgroundTransparency == 0)
`, "gui_render_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("GuiObject setup failed")
	}

	surface := kineffi.Kine_Skia_Surface_Create(200, 200)
	if surface == nil { panic("Skia surface creation failed") }
	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 0)
	engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, 200, 200, 1.0/60.0)
	kineffi.Kine_Skia_Surface_Flush(surface)

	inside_r, inside_g, inside_b, inside_a: u8
	kineffi.Kine_Skia_Surface_GetPixel(surface, 50, 50, &inside_r, &inside_g, &inside_b, &inside_a)
	assert(inside_r == 255 && inside_g == 255 && inside_b == 255 && inside_a == 255)

	outside_r, outside_g, outside_b, outside_a: u8
	kineffi.Kine_Skia_Surface_GetPixel(surface, 150, 150, &outside_r, &outside_g, &outside_b, &outside_a)
	assert(outside_r == 0 && outside_g == 0 && outside_b == 0 && outside_a == 0)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	kineffi.Kine_Skia_Surface_Destroy(surface)
	fmt.println("GUI_RENDER_SMOKE_PASSED")
}
