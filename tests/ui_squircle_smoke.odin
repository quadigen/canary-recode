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
	kineffi.Kine_Skia_Surface_Clear(surface, 0, 0, 0, 0)
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

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("UI_SQUIRCLE_SMOKE_PASSED")
}
