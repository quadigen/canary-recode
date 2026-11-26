package main

import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run_script :: proc(state: ^vm.VM, source: string) {
	ok, err := vm.Run(state, source, "viewport_world_isolation")
	if !ok {fmt.eprintln(err); panic("script failed")}
}

main :: proc() {
	state := vm.New()
	env: runtime.Environment
	renderer_state: renderer.RendererObject
	runtime.Environment_Init(&env, &state, &renderer_state)
	defer {vm.Close(&state); runtime.Environment_Destroy(&env)}
	run_script(
		&state,
		`
preview = Instance.new("ViewportFrame", game.CoreGui)
previewCamera = Instance.new("Camera", preview)
preview.CurrentCamera = previewCamera
previewModel = Instance.new("Model", preview)
previewPart = Instance.new("Part", previewModel)
worldPart = Instance.new("Part", workspace)
`,
	)
	before := classes.Render_3D_Revision()
	run_script(
		&state,
		`
previewCamera.CFrame = CFrame.new(0, 0, 20)
previewCamera.FieldOfView = 35
previewPart.Color = Color3.new(1, 0, 0)
previewPart:PivotTo(CFrame.new(2, 3, 4))
previewModel:ScaleTo(2)
local extra = Instance.new("Part", previewModel)
extra:Destroy()
`,
	)
	assert(classes.Render_3D_Revision() == before, "preview mutations invalidated main world")
	run_script(&state, `worldPart.Color = Color3.new(0, 1, 0)`)
	assert(classes.Render_3D_Revision() > before, "world mutation lost")
	before = classes.Render_3D_Revision()
	run_script(&state, `worldPart.Parent = previewModel`)
	assert(classes.Render_3D_Revision() > before, "world removal lost")
	before = classes.Render_3D_Revision()
	run_script(&state, `worldPart.Parent = workspace`)
	assert(classes.Render_3D_Revision() > before, "world insertion lost")
	before = classes.Render_3D_Revision()
	run_script(&state, `workspace.CurrentCamera = previewCamera`)
	assert(classes.Render_3D_Revision() > before, "world camera switch lost")
	before = classes.Render_3D_Revision()
	run_script(&state, `previewCamera.CFrame = CFrame.new(0, 0, 30)`)
	assert(classes.Render_3D_Revision() > before, "active world camera mutation lost")
	run_script(&state, `counter = Instance.new("NumberValue", workspace)`)
	before = classes.Render_3D_Revision()
	run_script(
		&state,
		`
previewCamera.CFrame = previewCamera.CFrame
previewCamera.FieldOfView = previewCamera.FieldOfView
counter.Value = 42
assert(counter.Value == 42)
`,
	)
	assert(classes.Render_3D_Revision() == before, "unchanged camera or value invalidated world")
	run_script(&state, `previewCamera.FieldOfView = 55`)
	assert(classes.Render_3D_Revision() > before, "changed field of view was lost")
	run_script(
		&state,
		`lighting = game:GetService("Lighting")
lighting.Ambient = Color3.new(0.5, 0.5, 0.5)
lighting.OutdoorAmbient = Color3.new(0.5, 0.5, 0.5)
workspace.Gravity = 196
`,
	)
	before = classes.Render_3D_Revision()
	run_script(
		&state,
		`
for i = 1, 1000 do
	lighting.Ambient = Color3.new(0.5, 0.5, 0.5)
	lighting.OutdoorAmbient = Color3.new(0.5, 0.5, 0.5)
	workspace.Gravity = 196
end
workspace.Gravity = 150
assert(workspace.Gravity == 150)
`,
	)
	assert(
		classes.Render_3D_Revision() == before,
		"redundant lighting or gravity invalidated world",
	)
	run_script(&state, `lighting.Ambient = Color3.new(0.6, 0.5, 0.5)`)
	assert(classes.Render_3D_Revision() > before, "changed lighting invalidation lost")
	dirty := classes.Render_3D_Dirty_Counts()
	assert(dirty[.Camera] > 0 && dirty[.Part] > 0 && dirty[.Hierarchy] > 0)
	fmt.println("VIEWPORT_WORLD_ISOLATION_PASSED")
}
