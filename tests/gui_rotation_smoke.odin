package main

import kineffi "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

find_frame :: proc(environment: ^engine_runtime.Environment) -> ^classes.Frame {
	descriptor := classes.Find_Class(&environment.classes, "Frame")
	if descriptor == nil {
		return nil
	}
	for object in descriptor.instances {
		frame := cast(^classes.Frame)object
		if frame.object.name == "RotFrame" {
			return frame
		}
	}
	return nil
}

render_surface :: proc(
	surface: ^kineffi.KineSkiaSurface,
	environment: ^engine_runtime.Environment,
	script_vm: ^vm.VM,
) {
	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 0)
	engine_runtime.Environment_Render_2D(environment, script_vm, surface, 200, 200, 1.0 / 60.0)
	kineffi.Kine_Skia_Surface_Flush(surface)
}

main :: proc() {
	script_vm := vm.New()
	renderer_object: renderer.RendererObject
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm, &renderer_object)

	ok, err := vm.Run(
		&script_vm,
		`
local screenGui = Instance.new("ScreenGui")

rotFrame = Instance.new("Frame", screenGui)
rotFrame.Name = "RotFrame"
rotFrame.Position = UDim2.fromOffset(50, 90)
rotFrame.Size = UDim2.fromOffset(100, 20)
rotFrame.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
rotFrame.BackgroundTransparency = 0
assert(rotFrame.Rotation == 0)

rotFrame.Rotation = 90
assert(rotFrame.Rotation == 90)
`,
		"gui_rotation_smoke",
	)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("GuiObject rotation setup failed")
	}

	surface := kineffi.Kine_Skia_Surface_Create(200, 200)
	if surface == nil {panic("Skia surface creation failed")}

	render_surface(surface, &environment, &script_vm)


	frame := find_frame(&environment)
	if frame == nil {panic("RotFrame not found")}

	classes.Update_GUI_Layout(&environment.classes, 200, 200)

	assert(
		classes.GuiObject_contains_point(cast(^classes.GuiObject)&frame.object, 100, 140),
		"rotated bar should hit-test the pixel below centre",
	)
	assert(
		!classes.GuiObject_contains_point(cast(^classes.GuiObject)&frame.object, 140, 100),
		"rotated bar should not hit-test the pixel right of centre",
	)


	below_r, below_g, below_b, below_a: u8
	kineffi.Kine_Skia_Surface_GetPixel(surface, 100, 140, &below_r, &below_g, &below_b, &below_a)
	assert(below_a > 0 && below_g > below_r, "rotated bar should fill the pixel below centre")

	right_r, right_g, right_b, right_a: u8
	kineffi.Kine_Skia_Surface_GetPixel(surface, 140, 100, &right_r, &right_g, &right_b, &right_a)
	assert(right_a == 0, "rotated bar should leave the pixel right of centre empty")


	center_r, center_g, center_b, center_a: u8
	kineffi.Kine_Skia_Surface_GetPixel(
		surface,
		100,
		100,
		&center_r,
		&center_g,
		&center_b,
		&center_a,
	)
	assert(center_a > 0 && center_g > center_r, "rotation pivot centre should stay filled")


	ok, err = vm.Run(&script_vm, `rotFrame.Rotation = 0`, "gui_rotation_reset")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("rotFrame reset failed")
	}

	render_surface(surface, &environment, &script_vm)
	classes.Update_GUI_Layout(&environment.classes, 200, 200)

	right_r, right_g, right_b, right_a = 0, 0, 0, 0
	kineffi.Kine_Skia_Surface_GetPixel(surface, 140, 100, &right_r, &right_g, &right_b, &right_a)
	assert(right_a > 0 && right_g > right_r, "unrotated bar should fill the pixel right of centre")

	below_r, below_g, below_b, below_a = 0, 0, 0, 0
	kineffi.Kine_Skia_Surface_GetPixel(surface, 100, 140, &below_r, &below_g, &below_b, &below_a)
	assert(below_a == 0, "unrotated bar should leave the pixel below centre empty")


	assert(
		classes.GuiObject_contains_point(cast(^classes.GuiObject)&frame.object, 140, 100),
		"unrotated bar should hit-test the pixel right of centre",
	)
	assert(
		!classes.GuiObject_contains_point(cast(^classes.GuiObject)&frame.object, 100, 140),
		"unrotated bar should not hit-test the pixel below centre",
	)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	kineffi.Kine_Skia_Surface_Destroy(surface)
	fmt.println("GUI_ROTATION_SMOKE_PASSED")
}
