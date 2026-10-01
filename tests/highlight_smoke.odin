package main

// Smoke test for the Highlight class. It covers the script-visible surface:
// defaults, round-tripped properties, reflection, clone, Adornee resolution,
// and that the Render_3D step is safe to run across frames.
//
// The headless environment here has no Filament context, so the step returns
// early instead of drawing. What this test can prove is that nothing about the
// draw path depends on state the script cannot observe, and that the property
// contract holds; the rasterized result needs a real window to judge.

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

	run_script(&script_vm, `
local reflection = game:GetService("ReflectionService")
local class = reflection:GetClass("Highlight")
assert(class ~= nil, "ReflectionService must know the Highlight class")
assert(class.Name == "Highlight", "wrong reflected name: " .. tostring(class.Name))
assert(class.Superclass == "Instance", "wrong reflected superclass: " .. tostring(class.Superclass))
assert(class.Permits.New ~= nil, "Highlight must be creatable")

local property_names = {}
for _, property in reflection:GetPropertiesOfClass("Highlight") do
	property_names[property.Name] = true
end
for _, name in ipairs({
	"Adornee", "DepthMode", "Enabled", "FillColor", "FillTransparency",
	"OutlineColor", "OutlineTransparency",
}) do
	assert(property_names[name], "Highlight must reflect the property " .. name)
end
`, "highlight_reflection")

	run_script(&script_vm, `
local part = Instance.new("Part")
part.Name = "Target"
part.Size = Vector3.new(4, 4, 4)
part.Anchored = true

local highlight = Instance.new("Highlight")
highlight.Name = "Highlight"
highlight.Parent = part

-- An unset Adornee follows Parent, so a Highlight must report nil until the
-- author assigns one.
assert(highlight.Adornee == nil, "Adornee must start nil")
assert(highlight.Enabled == true, "a new Highlight must be enabled")
assert(highlight.DepthMode == Enum.HighlightDepthMode.AlwaysOnTop,
	"DepthMode must default to AlwaysOnTop")
assert(highlight.FillTransparency == 0.5, "FillTransparency default: " .. tostring(highlight.FillTransparency))
assert(highlight.OutlineTransparency == 0, "OutlineTransparency must start opaque")
assert(highlight.FillColor == Color3.fromRGB(255, 100, 50),
	"FillColor default: " .. tostring(highlight.FillColor))
assert(highlight.OutlineColor == Color3.new(1, 1, 1), "OutlineColor default")

highlight.Adornee = part
assert(highlight.Adornee == part, "Adornee round trip failed")
highlight.Adornee = nil
assert(highlight.Adornee == nil, "clearing Adornee failed")

highlight.FillColor = Color3.new(0, 1, 0)
assert(highlight.FillColor == Color3.new(0, 1, 0), "FillColor round trip failed")
highlight.OutlineColor = Color3.new(0, 0, 1)
assert(highlight.OutlineColor == Color3.new(0, 0, 1), "OutlineColor round trip failed")
highlight.FillTransparency = 0.25
assert(highlight.FillTransparency == 0.25, "FillTransparency round trip failed")
highlight.OutlineTransparency = 0.75
assert(highlight.OutlineTransparency == 0.75, "OutlineTransparency round trip failed")
highlight.Enabled = false
assert(highlight.Enabled == false, "Enabled round trip failed")
highlight.Enabled = true

highlight.DepthMode = Enum.HighlightDepthMode.Occluded
assert(highlight.DepthMode == Enum.HighlightDepthMode.Occluded, "DepthMode round trip failed")
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
assert(highlight.DepthMode == Enum.HighlightDepthMode.AlwaysOnTop, "DepthMode must round trip back")
`, "highlight_properties")

	run_script(&script_vm, `
local highlight = Instance.new("Highlight")
highlight.FillTransparency = 0.1
highlight.OutlineColor = Color3.new(1, 0, 0)
highlight.DepthMode = Enum.HighlightDepthMode.Occluded

local clone = highlight:Clone()
assert(clone ~= nil, "Clone returned nil")
assert(clone ~= highlight, "Clone must return a different instance")
assert(clone.FillTransparency == 0.1, "Clone must copy FillTransparency")
assert(clone.OutlineColor == Color3.new(1, 0, 0), "Clone must copy OutlineColor")
assert(clone.DepthMode == Enum.HighlightDepthMode.Occluded, "Clone must copy DepthMode")
assert(clone.ClassName == "Highlight", "wrong cloned class: " .. tostring(clone.ClassName))

clone:Destroy()
`, "highlight_clone")

	// A model adornee must walk descendants, and every depth-mode and
	// transparency combination has to survive a frame without submitting
	// anything malformed.
	run_script(&script_vm, `
local model = Instance.new("Model")
model.Name = "HighlightedModel"
model.Parent = game:GetService("Workspace")

for index = 1, 3 do
	local part = Instance.new("Part")
	part.Name = "Member" .. index
	part.Size = Vector3.new(2, 2, 2)
	part.Shape = Enum.PartType.Ball
	part.Anchored = true
	part.Parent = model
end

local highlight = Instance.new("Highlight")
highlight.Parent = model
highlight.Adornee = model

local other = Instance.new("Highlight")
other.Parent = model

local invisible = Instance.new("Highlight")
invisible.Parent = model
invisible.FillTransparency = 1
invisible.OutlineTransparency = 1

for _, mode in ipairs({
	Enum.HighlightDepthMode.AlwaysOnTop,
	Enum.HighlightDepthMode.Occluded,
}) do
	for _, fill in ipairs({ 0, 0.5, 1 }) do
		for _, outline in ipairs({ 0, 0.5, 1 }) do
			highlight.DepthMode = mode
			highlight.FillTransparency = fill
			highlight.OutlineTransparency = outline
			other.DepthMode = mode
			other.FillTransparency = fill
			other.OutlineTransparency = outline
		end
	end
end

highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
highlight.FillTransparency = 0.5
highlight.OutlineTransparency = 0
other.DepthMode = Enum.HighlightDepthMode.Occluded
`, "highlight_model_setup")

	for _ in 0 ..< 4 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, STEP_DT)
	}

	run_script(&script_vm, `
-- A Highlight with neither Adornee nor Parent has nothing to draw and must stay
-- harmless rather than reach into the whole DataModel.
local orphan = Instance.new("Highlight")
orphan.Enabled = true
orphan:Destroy()

-- Destroying an Adornee must leave the Highlight safe to step: it resolves its
-- Adornee every frame, so the next frame sees a destroyed object.
local doomed_model = Instance.new("Model")
doomed_model.Parent = game:GetService("Workspace")

local doomed = Instance.new("Highlight")
doomed.Parent = doomed_model
doomed.Adornee = doomed_model

doomed_model:Destroy()
`, "highlight_destroy")

	engine_runtime.Environment_Update_Step(&environment, &script_vm, STEP_DT)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("HIGHLIGHT_SMOKE_PASSED")
}
