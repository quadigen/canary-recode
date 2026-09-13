package main

import "core:fmt"
import "core:os"
import kineffi "../src/engine/bindings"
import engine_runtime "../src/engine/runtime"
import renderer "../src/engine/renderer"
import sandbox "../src/sandboxed"
import vm "../src/engine/vm"
import sdl3 "vendor:sdl3"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	renderer_object: renderer.RendererObject

	sandbox.init(&script_vm, &environment, &renderer_object)
	defer sandbox.shutdown()
	defer vm.Close(&script_vm)

	width: i32 = 800
	height: i32 = 600
	surface := kineffi.Kine_Skia_Surface_Create(width, height)
	assert(surface != nil)
	defer kineffi.Kine_Skia_Surface_Destroy(surface)

	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 255)
	// The first retained pass resolves layout; the second reflects dynamic
	// Explorer, Inspector, Output, and viewport content created by callbacks.
	engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, width, height, 1.0/60.0)
	engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, width, height, 1.0/60.0)

	// Exercise the same native UserInputService hit routing used by the live
	// editor. This coordinate selects a visible Explorer service row at 800x600.
	click: sdl3.Event
	click.type = .MOUSE_BUTTON_DOWN
	click.button.button = sdl3.BUTTON_LEFT
	click.button.x = 680
	click.button.y = 167
	engine_runtime.Environment_SetEvent(&environment, &script_vm, click)
	selected, selection_error := vm.Run(&script_vm, `
assert(#game:GetService("Selection"):Get() == 1)
`, "editor_native_ui_selection")
	if !selected {
		fmt.eprintln(selection_error)
		delete(selection_error)
		panic("native editor click did not reach Explorer")
	}
	engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, width, height, 1.0/60.0)
	engine_runtime.Environment_Render_Overlay(&environment, &script_vm, surface, width, height, 1.0/60.0)
	assert(renderer_object.HasViewportRect)
	// Expanded ribbon ends at y=115 and leaves a four-pixel separator before
	// Filament begins. This prevents the 3D pass from clipping toolbar content.
	assert(renderer_object.ViewportRect[1] >= 119)
	assert(renderer_object.ViewportRect[3] > 0)
	overlay_ok, overlay_error := vm.Run(&script_vm, `
local overlay = game.CoreGui:FindFirstChild("StudioOverlay")
assert(overlay ~= nil and overlay.RenderOnTop == true)
`, "editor_native_ui_overlay")
	if !overlay_ok {
		fmt.eprintln(overlay_error)
		delete(overlay_error)
		panic("native editor overlay was not configured")
	}
	kineffi.Kine_Skia_Surface_Flush(surface)

	header := fmt.tprintf("P6\n%d %d\n255\n", width, height)
	pixels := make([]byte, len(header)+int(width*height*3))
	defer delete(pixels)
	copy(pixels[:len(header)], transmute([]byte)header)

	offset := len(header)
	for y: i32 = 0; y < height; y += 1 {
		for x: i32 = 0; x < width; x += 1 {
			r, g, b, a: u8
			kineffi.Kine_Skia_Surface_GetPixel(surface, x, y, &r, &g, &b, &a)
			pixels[offset+0] = r
			pixels[offset+1] = g
			pixels[offset+2] = b
			offset += 3
		}
	}

	err := os.write_entire_file("build/editor-native-ui.ppm", pixels)
	assert(err == nil)
	fmt.println("EDITOR_NATIVE_UI_SMOKE_PASSED build/editor-native-ui.ppm")
}
