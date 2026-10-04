package main

// Smoke test for the Lighting service. It covers the script-visible surface of
// the ClockTime work: that ClockTime reads and writes as a plain number rather
// than an EnumItem, that it wraps instead of clamping, that the shadow and
// effect controls round-trip, and that the default effect hierarchy exists with
// the intended enabled flags.
//
// The headless environment here has no Filament context, so Lighting_Apply
// returns before touching any GPU state. What this test can prove is that the
// property contract and the defaults hold, and that the clock wraps over a full
// day; the rasterized result needs a real window to judge.

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import renderer "../src/engine/renderer"
import vm "../src/engine/vm"

STEP_DT :: f32(1.0 / 60.0)
VIEWPORT_WIDTH :: i32(800)
VIEWPORT_HEIGHT :: i32(600)

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic(name)
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	view: renderer.RendererObject
	engine_runtime.Environment_Init(&environment, &script_vm, &view)

	view.HasViewportRect = true
	view.ViewportRect = {0, 0, VIEWPORT_WIDTH, VIEWPORT_HEIGHT}

	// ClockTime has to behave like a number. That is the contract which differs
	// from an EnumItem reading, so it is asserted first.
	run_script(&script_vm, `
	local lighting = game:GetService("Lighting")

	assert(type(lighting.ClockTime) == "number",
		"ClockTime must be a number, got " .. type(lighting.ClockTime))

	lighting.ClockTime = 14.5
	assert(lighting.ClockTime == 14.5,
		"ClockTime round trip failed: " .. tostring(lighting.ClockTime))

	-- Fractional hours must survive, since a script advancing the clock writes
	-- a fractional value every frame.
	lighting.ClockTime = 0.25
	assert(lighting.ClockTime == 0.25,
		"fractional ClockTime must round trip: " .. tostring(lighting.ClockTime))

	-- Midnight has to be reachable exactly, not only as a wrapped value.
	lighting.ClockTime = 0
	assert(lighting.ClockTime == 0, "midnight must be exactly 0")

	-- A clock left running wraps through midnight rather than sticking at 24
	-- or going negative.
	lighting.ClockTime = 23.5
	lighting.ClockTime = lighting.ClockTime + 1
	assert(lighting.ClockTime == 0.5,
		"ClockTime must wrap past midnight, got " .. tostring(lighting.ClockTime))

	lighting.ClockTime = 1
	lighting.ClockTime = lighting.ClockTime - 2
	assert(lighting.ClockTime == 23,
		"ClockTime must wrap below zero, got " .. tostring(lighting.ClockTime))

	-- An unclamped advance stays in range over many steps.
	lighting.ClockTime = 0
	for _ = 1, 500 do
		lighting.ClockTime = lighting.ClockTime + 0.37
	end
	assert(lighting.ClockTime >= 0 and lighting.ClockTime < 24,
		"ClockTime must stay within a single day, got " .. tostring(lighting.ClockTime))
	`, "lighting_clocktime")

	// The shadow and grading controls round-trip and clamp the way they should.
	run_script(&script_vm, `
	local lighting = game:GetService("Lighting")

	assert(lighting.GlobalShadows == true, "GlobalShadows must default on")
	lighting.GlobalShadows = false
	assert(lighting.GlobalShadows == false, "GlobalShadows round trip failed")
	lighting.GlobalShadows = true
	assert(lighting.GlobalShadows == true, "GlobalShadows must round trip back")

	lighting.ShadowSoftness = 0.5
	assert(lighting.ShadowSoftness == 0.5, "ShadowSoftness round trip failed")

	-- ShadowSoftness is a 0..1 dial, so out-of-range values clamp.
	lighting.ShadowSoftness = 5
	assert(lighting.ShadowSoftness == 1, "ShadowSoftness must clamp high")
	lighting.ShadowSoftness = -3
	assert(lighting.ShadowSoftness == 0, "ShadowSoftness must clamp low")

	lighting.Brightness = 1.5
	assert(lighting.Brightness == 1.5, "Brightness round trip failed")
	lighting.Brightness = -10
	assert(lighting.Brightness == 0, "Brightness must clamp at zero")

	lighting.Ambient = Color3.new(0.1, 0.2, 0.3)
	assert(lighting.Ambient == Color3.new(0.1, 0.2, 0.3), "Ambient round trip failed")
	lighting.OutdoorAmbient = Color3.new(0.4, 0.5, 0.6)
	assert(lighting.OutdoorAmbient == Color3.new(0.4, 0.5, 0.6),
		"OutdoorAmbient round trip failed")

	lighting.ExposureCompensation = 0.25
	assert(lighting.ExposureCompensation == 0.25,
		"ExposureCompensation round trip failed")
	`, "lighting_shadow_properties")

	// The stock effect hierarchy has to exist so scripts can reach the effects
	// without constructing them, with the frame-blurring ones left off.
	run_script(&script_vm, `
	local lighting = game:GetService("Lighting")

	for _, name in ipairs({
		"Atmosphere", "BloomEffect", "ColorCorrectionEffect",
		"DepthOfFieldEffect", "SunRaysEffect", "SSAOEffect",
	}) do
		local effect = lighting:FindFirstChild(name)
		assert(effect ~= nil, "Lighting must ship a default " .. name)
		assert(effect.ClassName == name,
			"default " .. name .. " has the wrong class: " .. tostring(effect.ClassName))
	end

	-- These are on by default: they are what a place gets without authoring.
	assert(lighting.BloomEffect.Enabled == true, "BloomEffect must default enabled")
	assert(lighting.ColorCorrectionEffect.Enabled == true,
		"ColorCorrectionEffect must default enabled")
	assert(lighting.SunRaysEffect.Enabled == true, "SunRaysEffect must default enabled")
	assert(lighting.SSAOEffect.Enabled == true, "SSAOEffect must default enabled")
	assert(lighting.Atmosphere.Enabled == true, "Atmosphere must default enabled")

	-- Both of these blur the whole frame, so shipping them on would make every
	-- fresh place an unreadable smear.
	assert(lighting.DepthOfFieldEffect.Enabled == false,
		"DepthOfFieldEffect must default disabled")
	assert(lighting.BlurEffect.Enabled == false,
		"BlurEffect must default disabled")

	-- Bloom's class default of 1.0 is Filament's full strength, which blows a
	-- daylight frame out to white.
	assert(lighting.BloomEffect.Intensity < 1.0,
		"default BloomEffect intensity must be softened, got "
			.. tostring(lighting.BloomEffect.Intensity))
	`, "lighting_default_effects")

	// The view-level Filament options are instances now, and they ship off.
	// FXAA in particular used to be forced on and cost visible frame time.
	run_script(&script_vm, `
	local lighting = game:GetService("Lighting")

	for _, name in ipairs({
		"AntiAliasingEffect", "DitheringEffect", "RenderQualityEffect",
		"VignetteEffect", "ScreenSpaceReflectionsEffect",
	}) do
		local effect = lighting:FindFirstChild(name)
		assert(effect ~= nil, "Lighting must ship a default " .. name)
		assert(effect.ClassName == name,
			"default " .. name .. " has the wrong class: " .. tostring(effect.ClassName))
		assert(effect.Enabled == false,
			name .. " must default disabled, since it was previously forced on")
	end

	-- No anti-aliasing mode is on until a script asks for one.
	local aa = lighting.AntiAliasingEffect
	assert(aa.FXAA == false, "FXAA must not default on")
	assert(aa.TAA == false, "TAA must not default on")
	assert(aa.MSAA == false, "MSAA must not default on")
	`, "lighting_view_effect_defaults")

	// Each of them has to round-trip and clamp the way its Filament option does.
	run_script(&script_vm, `
	local lighting = game:GetService("Lighting")

	local aa = lighting.AntiAliasingEffect
	aa.FXAA = true
	assert(aa.FXAA == true, "FXAA round trip failed")
	aa.TAA = true
	assert(aa.TAA == true, "TAA round trip failed")
	aa.MSAA = true
	assert(aa.MSAA == true, "MSAA round trip failed")

	aa.SampleCount = 8
	assert(aa.SampleCount == 8, "SampleCount round trip failed")
	-- Filament's MSAA tops out at 8 samples.
	aa.SampleCount = 99
	assert(aa.SampleCount == 8, "SampleCount must clamp to 8")
	aa.SampleCount = 0
	assert(aa.SampleCount == 1, "SampleCount must clamp to 1")

	-- Dithering is pure on/off, so Enabled is the entire contract.
	lighting.DitheringEffect.Enabled = true
	assert(lighting.DitheringEffect.Enabled == true, "Dithering Enabled round trip failed")

	-- Quality maps onto LOW/MEDIUM/HIGH/ULTRA as 0..3.
	local quality = lighting.RenderQualityEffect
	quality.Quality = 2
	assert(quality.Quality == 2, "Quality round trip failed")
	quality.Quality = 99
	assert(quality.Quality == 3, "Quality must clamp to ULTRA")
	quality.Quality = -5
	assert(quality.Quality == 0, "Quality must clamp to LOW")

	local vignette = lighting.VignetteEffect
	vignette.Midpoint = 0.75
	assert(vignette.Midpoint == 0.75, "Vignette Midpoint round trip failed")
	vignette.Roundness = 0.2
	assert(vignette.Roundness == 0.2, "Vignette Roundness round trip failed")
	vignette.Feather = 0.6
	assert(vignette.Feather == 0.6, "Vignette Feather round trip failed")
	vignette.Color = Color3.new(0.1, 0.2, 0.3)
	assert(vignette.Color == Color3.new(0.1, 0.2, 0.3), "Vignette Color round trip failed")
	vignette.Transparency = 0.5
	assert(vignette.Transparency == 0.5, "Vignette Transparency round trip failed")

	-- The Filament side clamps these, so the property must too.
	vignette.Midpoint = 4
	assert(vignette.Midpoint == 1, "Vignette Midpoint must clamp high")
	vignette.Transparency = -1
	assert(vignette.Transparency == 0, "Vignette Transparency must clamp low")

	local ssr = lighting.ScreenSpaceReflectionsEffect
	ssr.Thickness = 0.75
	assert(ssr.Thickness == 0.75, "SSR Thickness round trip failed")
	ssr.Bias = 0.02
	assert(ssr.Bias == 0.02, "SSR Bias round trip failed")
	ssr.MaxDistance = 25
	assert(ssr.MaxDistance == 25, "SSR MaxDistance round trip failed")
	ssr.Stride = 1
	assert(ssr.Stride == 1, "SSR Stride round trip failed")

	-- A negative range would make Filament trace backwards, so it floors.
	ssr.MaxDistance = -10
	assert(ssr.MaxDistance == 0, "SSR MaxDistance must floor at zero")
	ssr.Thickness = -1
	assert(ssr.Thickness == 0, "SSR Thickness must floor at zero")
	`, "lighting_view_effect_properties")

	// These are creatable on demand too, and Clone has to carry the settings.
	run_script(&script_vm, `
	local aa = Instance.new("AntiAliasingEffect")
	aa.FXAA = true
	aa.SampleCount = 4

	local clone = aa:Clone()
	assert(clone ~= nil, "Clone returned nil")
	assert(clone.ClassName == "AntiAliasingEffect", "wrong cloned class")
	assert(clone.FXAA == true, "Clone must copy FXAA")
	assert(clone.SampleCount == 4, "Clone must copy SampleCount")

	local vignette = Instance.new("VignetteEffect")
	vignette.Midpoint = 0.3
	vignette.Color = Color3.new(0, 0.5, 1)
	local vignette_clone = vignette:Clone()
	assert(vignette_clone.Midpoint == 0.3, "Clone must copy Vignette Midpoint")
	assert(vignette_clone.Color == Color3.new(0, 0.5, 1), "Clone must copy Vignette Color")

	clone:Destroy()
	vignette_clone:Destroy()
	`, "lighting_view_effect_clone")

	// Setting a time of day must stay safe across frames with no Filament
	// context, which is the path a headless host actually exercises.
	run_script(&script_vm, `
	local lighting = game:GetService("Lighting")

	for hour = 0, 23 do
		lighting.ClockTime = hour
		lighting.GlobalShadows = (hour % 2) == 0
	end

	lighting.ClockTime = 12
	assert(lighting.ClockTime == 12, "noon must round trip after a sweep")
	`, "lighting_clock_sweep")

	// Lighting is a replication root, so the runtime-built default effects must
	// never be sent to a client that has already built its own copy. Getting
	// this wrong produced a second same-named instance of every effect on the
	// client and took the session down at connect time.
	run_script(&script_vm, `
	local lighting = game:GetService("Lighting")

	for _, name in ipairs({
		"Atmosphere", "BloomEffect", "ColorCorrectionEffect",
		"DepthOfFieldEffect", "SunRaysEffect", "SSAOEffect",
		"AntiAliasingEffect", "DitheringEffect", "RenderQualityEffect",
		"VignetteEffect", "ScreenSpaceReflectionsEffect",
	}) do
		local effect = lighting:FindFirstChild(name)
		assert(effect ~= nil, "Lighting must ship a default " .. name)
		assert(effect.CanReplicate == false,
			name .. " must not replicate: the client builds its own copy")

		-- Exactly one instance of each, not a server copy shadowing the local
		-- one under an identical name.
		local seen = 0
		for _, child in lighting:GetChildren() do
			if child.ClassName == name then
				seen = seen + 1
			end
		end
		assert(seen == 1,
			name .. " must exist exactly once under Lighting, found " .. seen)
	end

	-- A script-authored effect still replicates normally; only the runtime's
	-- own defaults are excluded.
	local authored = Instance.new("BloomEffect")
	authored.Parent = lighting
	assert(authored.CanReplicate == true,
		"a script-created effect must keep the default replication behaviour")
	authored:Destroy()
	`, "lighting_no_replication")

	fmt.println("lighting_smoke: PASSED")
}