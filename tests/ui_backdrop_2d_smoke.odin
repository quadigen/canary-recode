package main

import kineffi "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	state := vm.New()
	render: renderer.RendererObject
	env: runtime.Environment
	runtime.Environment_Init(&env, &state, &render)
	defer {
		vm.Close(&state)
		runtime.Environment_Destroy(&env)
	}

	ok, err := vm.Run(
		&state,
		`
local base = Instance.new("ScreenGui")
local background = Instance.new("Frame", base)
background.Size = UDim2.fromOffset(120, 120)
background.BackgroundColor3 = Color3.new(0, 0, 1)

local overlay = Instance.new("ScreenGui")
overlay.RenderOnTop = true
local glass = Instance.new("Frame", overlay)
glass.BackgroundTransparency = 1
glass.Size = UDim2.fromOffset(120, 120)
local effect = Instance.new("UIBackdrop", glass)
effect.BlurRadius = 0
effect.TintColor3 = Color3.new(1, 0, 0)
effect.TintTransparency = 0.5
effect.Transparency = 1
`,
		"ui_backdrop_2d_setup",
	)
	if !ok {
		fmt.eprintln(err)
		panic("UI backdrop 2D setup failed")
	}

	surface := kineffi.Kine_Skia_Surface_Create(120, 120)
	assert(surface != nil)
	defer kineffi.Kine_Skia_Surface_Destroy(surface)
	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 255)
	runtime.Environment_Render_2D(&env, &state, surface, 120, 120, 1.0 / 60.0)
	assert(classes.Gui_Overlay_Needs_Backdrop(&env.classes))
	kineffi.Kine_Skia_Surface_SetBackdropFromSurface(surface, surface)
	runtime.Environment_Render_Overlay(&env, &state, surface, 120, 120, 1.0 / 60.0)
	kineffi.Kine_Skia_Surface_ClearBackdrop(surface)
	kineffi.Kine_Skia_Surface_Flush(surface)
	r, g, b, a: u8
	kineffi.Kine_Skia_Surface_GetPixel(surface, 60, 60, &r, &g, &b, &a)
	assert(r > 30 && b > 30 && a == 255)
	fmt.println("UI_BACKDROP_2D_SMOKE_PASSED")
}
