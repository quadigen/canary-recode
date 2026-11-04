package main

import kineffi "../src/engine/bindings"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	script_vm := vm.New()
	renderer_object: renderer.RendererObject
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm, &renderer_object)

	ok, err := vm.Run(
		&script_vm,
		`
local screen = Instance.new("ScreenGui")

-- Circular round (UICorner, radius 50 on 100x100) for comparison.
local round = Instance.new("Frame", screen)
round.Size = UDim2.fromOffset(100, 100)
local roundCorner = Instance.new("UICorner", round)
roundCorner.CornerRadius = UDim.new(0, 50)

-- Squircle with a high exponent: the corner stays much fuller than a circle.
squircle = Instance.new("Frame", screen)
squircle.Position = UDim2.fromOffset(150, 0)
squircle.Size = UDim2.fromOffset(100, 100)
local squircleMod = Instance.new("UISquircle", squircle)
squircleMod.Radius = UDim.new(0, 50)
squircleMod.Exponent = 8
assert(squircleMod.Radius == UDim.new(0, 50))
assert(squircleMod.Exponent == 8)
assert(squircleMod.TopLeftRadius == UDim.new(0, 0))
squircleMod.TopLeftRadius = UDim.new(0, 25)
assert(squircleMod.TopLeftRadius == UDim.new(0, 25))

-- UIShadow/UIBackdrop with squircle exponents must render without crashing.
effects = Instance.new("Frame", screen)
effects.Position = UDim2.fromOffset(300, 0)
effects.Size = UDim2.fromOffset(100, 100)
local effectsSquircle = Instance.new("UISquircle", effects)
effectsSquircle.Exponent = 6
local shadow = Instance.new("UIShadow", effects)
shadow.Exponent = 6
local backdrop = Instance.new("UIBackdrop", effects)
backdrop.Exponent = 6
assert(backdrop.Exponent == 6)
assert(shadow.Exponent == 6)

local background = Instance.new("Frame", screen)
background.Position = UDim2.fromOffset(0, 120)
background.Size = UDim2.fromOffset(400, 80)
background.BackgroundColor3 = Color3.new(0, 0, 1)

local function addBackdrop(x, transparency)
	local panel = Instance.new("Frame", screen)
	panel.Position = UDim2.fromOffset(x, 120)
	panel.Size = UDim2.fromOffset(100, 80)
	panel.BackgroundTransparency = 1
	panel.ZIndex = 2
	local effect = Instance.new("UIBackdrop", panel)
	assert(effect.Transparency == 0)
	effect.Transparency = transparency
	effect.TintTransparency = 1
	assert(effect:Clone().Transparency == transparency)
	return effect
end

addBackdrop(0, 1)
addBackdrop(120, 0.5)
local tintOnly = addBackdrop(240, 0)
tintOnly.BlurRadius = 0
tintOnly.TintColor3 = Color3.new(0, 0, 0)
tintOnly.TintTransparency = 0.5
`,
		"ui_squircle_smoke",
	)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("ui_squircle_smoke setup failed")
	}

	surface := kineffi.Kine_Skia_Surface_Create(400, 200)
	if surface == nil {panic("Skia surface creation failed")}
	defer kineffi.Kine_Skia_Surface_Destroy(surface)
	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 0)
	snapshot := kineffi.Kine_Skia_Surface_Create(400, 200)
	if snapshot == nil {panic("Skia backdrop surface creation failed")}
	defer kineffi.Kine_Skia_Surface_Destroy(snapshot)
	kineffi.Kine_Skia_Surface_Clear(snapshot, 255, 0, 0, 255)
	kineffi.Kine_Skia_Surface_SetBackdropFromSurface(surface, snapshot)
	engine_runtime.Environment_Render_2D(&environment, &script_vm, surface, 400, 200, 1.0 / 60.0)
	kineffi.Kine_Skia_Surface_Flush(surface)


	rr, rg, rb, ra: u8
	kineffi.Kine_Skia_Surface_GetPixel(surface, 5, 5, &rr, &rg, &rb, &ra)
	assert(ra == 0, "round corner pixel should be transparent")


	sr, sg, sb, sa: u8
	kineffi.Kine_Skia_Surface_GetPixel(surface, 155, 5, &sr, &sg, &sb, &sa)
	assert(sa > 0, "squircle corner pixel should be covered")


	cr, cg, cb, ca: u8
	kineffi.Kine_Skia_Surface_GetPixel(surface, 200, 50, &cr, &cg, &cb, &ca)
	assert(cr == 255 && cg == 255 && cb == 255 && ca == 255, "squircle center should be white")


	er, eg, eb, ea: u8
	kineffi.Kine_Skia_Surface_GetPixel(surface, 150, 0, &er, &eg, &eb, &ea)
	assert(ea == 0, "squircle extreme corner should be transparent")

	r, g, b, a: u8
	kineffi.Kine_Skia_Surface_GetPixel(surface, 50, 160, &r, &g, &b, &a)
	assert(r == 0 && g == 0 && b == 255 && a == 255, "invisible backdrop should preserve the GUI behind it")
	kineffi.Kine_Skia_Surface_GetPixel(surface, 170, 160, &r, &g, &b, &a)
	assert(r >= 126 && r <= 129 && g == 0 && b >= 126 && b <= 129 && a == 255,
		"half-transparent blur should blend the captured image with the GUI behind it")
	kineffi.Kine_Skia_Surface_GetPixel(surface, 290, 160, &r, &g, &b, &a)
	assert(r == 0 && g == 0 && b >= 126 && b <= 129 && a == 255,
		"tint-only backdrop should tint the GUI without drawing the captured image")

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("UI_SQUIRCLE_SMOKE_PASSED")
}
