package main

import kineffi "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import sdl "vendor:sdl3"

run :: proc(state: ^vm.VM, source: string) {
	ok, err := vm.Run(state, source, "construct_viewport")
	if !ok {fmt.eprintln(err); panic("Construct viewport script failed")}
}

main :: proc() {
	assert(sdl.Init({.VIDEO}))
	defer sdl.Quit()
	window := sdl.CreateWindow(
		"Construct viewport regression",
		320,
		240,
		sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN,
	)
	assert(window != nil)
	defer sdl.DestroyWindow(window)
	filament := kineffi.Kine_Filament_CreateForVulkanCompositorWindow(window, 320, 240)
	assert(filament != nil)
	defer kineffi.Kine_Filament_Destroy(filament)
	view := renderer.RendererObject {
		Filament        = filament,
		HasViewportRect = true,
		ViewportRect    = {0, 0, 320, 240},
	}
	state := vm.New()
	env: runtime.Environment
	runtime.Environment_Init(&env, &state, &view)
	defer {vm.Close(&state); runtime.Environment_Destroy(&env)}

	run(
		&state,
		`
local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable
local screen = Instance.new("ScreenGui", game.CoreGui)
preview = Instance.new("ViewportFrame", screen)
preview.Size = UDim2.fromScale(1, 1)
preview.BackgroundTransparency = 1
preview.CurrentCamera = Instance.new("Camera", preview)
model = Instance.new("Model", workspace)
block = Instance.new("Part", model)
block.Anchored = true
block.Size = Vector3.new(3, 3, 3)
block.Position = Vector3.new(0, 0, 0)
camera.CameraSubject = block
`,
	)
	ws := cast(^services.Workspace)services.Ensure_Service(&env.services, "Workspace")
	runtime.Environment_Render_3D(&env, &state, 1.0 / 60)
	assert(len(ws.draw_items) == 1, "placement model was not initially present in Workspace")
	version := ws.draw_version

	run(
		&state,
		`
local camera = workspace.CurrentCamera
cameraEvents = 0
cframeEvents = 0
camera.Changed:Connect(function(property)
	if property ~= "CFrame" then return end
	cameraEvents += 1
	preview.CurrentCamera.CFrame = camera.CFrame
	preview.CurrentCamera.FieldOfView = camera.FieldOfView
	model.Parent = preview
end)
camera:GetPropertyChangedSignal("CFrame"):Connect(function()
	cframeEvents += 1
end)
camera.CameraType = Enum.CameraType.Follow
`,
	)
	runtime.Environment_Render_3D(&env, &state, 1.0 / 60)
	run(
		&state,
		`
assert(cameraEvents == 1 and cframeEvents == 1, tostring(cameraEvents) .. "/" .. tostring(cframeEvents))
assert(model.Parent == preview)
assert(preview.CurrentCamera.CFrame == workspace.CurrentCamera.CFrame)
assert(preview.CurrentCamera.FieldOfView == workspace.CurrentCamera.FieldOfView)
`,
	)
	assert(
		len(ws.draw_items) == 0 && ws.draw_version > version,
		"world retained a reparented placement model",
	)
	classes.Update_GUI_Layout(&env.classes, 320, 240)
	classes.ViewportFrame_Prepare_All(&env.classes, 320, 240, 1.0 / 60)
	descriptor := classes.Find_Class(&env.classes, "ViewportFrame")
	preview := cast(^classes.ViewportFrame)descriptor.instances[0]
	assert(len(preview.items) == 1, "placement model was not submitted to its ViewportFrame")
	fmt.println("CONSTRUCT_VIEWPORT_SMOKE_PASSED")
}
