package main

import kineffi "../src/engine/bindings"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	script_vm := vm.New()
	render: renderer.RendererObject
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm, &render)

	ok, err := vm.Run(
		&script_vm,
		`
local gui = Instance.new("ScreenGui")
gui.Name = "VRTestBase"
local base = Instance.new("Frame", gui)
base.Size = UDim2.fromOffset(100, 100)
base.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
base.BorderSizePixel = 0

local overlay = Instance.new("ScreenGui")
overlay.Name = "VRTestOverlay"
overlay.RenderOnTop = true
local top = Instance.new("Frame", overlay)
top.Position = UDim2.fromOffset(20, 20)
top.Size = UDim2.fromOffset(40, 40)
top.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
top.BorderSizePixel = 0
`,
		"vr_gui_setup",
	)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("VR GUI setup failed")
	}

	desktop := kineffi.Kine_Skia_Surface_Create(200, 200)
	panel := kineffi.Kine_Skia_Surface_Create(100, 100)
	assert(desktop != nil && panel != nil)
	kineffi.Kine_Skia_Surface_Clear(desktop, 0, 0, 0, 255)
	kineffi.Kine_Skia_Surface_Clear(panel, 0, 0, 0, 0)
	engine_runtime.Environment_Render_2D(&environment, &script_vm, desktop, 200, 200, 0)
	engine_runtime.Environment_Render_VR_UI(&environment, &script_vm, panel, 200, 200, 100, 100)
	kineffi.Kine_Skia_Surface_Flush(panel)
	r, g, b, a: u8
	kineffi.Kine_Skia_Surface_GetPixel(panel, 5, 5, &r, &g, &b, &a)
	assert(r > 200 && g < 30 && b < 30 && a == 255)
	kineffi.Kine_Skia_Surface_GetPixel(panel, 20, 20, &r, &g, &b, &a)
	assert(r < 30 && g > 200 && b < 30 && a == 255)
	kineffi.Kine_Skia_Surface_GetPixel(panel, 80, 80, &r, &g, &b, &a)
	assert(a == 0)
	assert(render.SkiaSurface == nil)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	kineffi.Kine_Skia_Surface_Destroy(panel)
	kineffi.Kine_Skia_Surface_Destroy(desktop)
	fmt.println("VR_GUI_SMOKE_PASSED")
}
