package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import renderer "../src/engine/renderer"
import sandbox "../src/sandboxed"
import vm "../src/engine/vm"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	renderer_object: renderer.RendererObject

	sandbox.init(&script_vm, &environment, &renderer_object)
	defer sandbox.shutdown()
	defer vm.Close(&script_vm)

	ok, err := vm.Run(&script_vm, `
local parent = Instance.new("Folder")
parent.Name = "Parent"
parent.Parent = game

local child = Instance.new("Folder")
child.Name = "Child"
child.Parent = parent

-- THE REPORTED CASE: dropping a child back onto the same parent.
print("STEP same-parent reparent")
child.Parent = child.Parent
print("STEP survived same-parent reparent")

-- The tween path: a tween still targeting an instance that is then destroyed,
-- which is what the explorer's drag ghost does on drop.
print("STEP tween-then-destroy")
local ghost = Instance.new("Frame")
ghost.Name = "Ghost"
ghost.Parent = game.CoreGui
ghost.BackgroundTransparency = 0.2

local TweenService = game:GetService("TweenService")

-- Several overlapping tweens, mirroring one-per-mousemove.
local tweens = {}
for i = 1, 5 do
	local t = TweenService:Create(
		ghost,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(i * 10, i * 10) }
	)
	tweens[#tweens + 1] = t
	t:Play()
end

-- Destroy the tween's target while those tweens are still playing.
ghost:Destroy()
print("STEP destroyed target")
`, "reparent_same_parent_setup")

	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("setup failed")
	}

	// Step several frames: this is where a use-after-free would surface.
	for i := 0; i < 8; i += 1 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 0.1)
		engine_runtime.Environment_Render_2D(&environment, &script_vm, nil, 0, 0, 0.1)
		fmt.println("step", i, "survived")
	}

	_ = renderer_object
	fmt.println("REPARENT_SAME_PARENT_SMOKE_PASSED")
}