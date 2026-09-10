package main

import "core:fmt"
import classes "../src/engine/classes"
import datatypes "../src/engine/datatypes"
import renderer "../src/engine/renderer"
import services "../src/engine/services"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

main :: proc() {
	renderer_object: renderer.RendererObject
	camera := classes.Camera_Init()
	camera.CFrame = datatypes.CFrame_New_XYZ(2, 3, 4)
	classes.Camera_Update_World_To_View(&camera, &renderer_object)
	assert(renderer_object.HasWorldToView)

	world := datatypes.CFrame_New_XYZ(2, 3, -6)
	view := services.Workspace_Apply_View(&renderer_object, world)
	assert(abs(view.x) < 1.0e-6)
	assert(abs(view.y) < 1.0e-6)
	assert(abs(view.z+10) < 1.0e-6)
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm, &renderer_object)
	ok, err := vm.Run(&script_vm, `
local original = workspace.CurrentCamera
assert(original and original:IsA("Camera") and original.Parent == workspace)
original.CFrame = CFrame.new(2, 3, 4) * CFrame.Angles(0.2, 0.4, 0)
assert(vector.magnitude(original.CFrame.Position - vector.create(2, 3, 4)) < 0.0001)
local replacement = Instance.new("Camera")
replacement.Parent = workspace
workspace.CurrentCamera = replacement
assert(workspace.CurrentCamera == replacement)
`, "camera_properties")
	if !ok { fmt.eprintln(err); panic("Camera properties failed") }
	workspace := cast(^services.Workspace)services.Ensure_Service(&environment.services, "Workspace")
	assert(renderer_object.ActiveCamera == rawptr(workspace.current_camera))
	engine_runtime.Environment_Destroy(&environment)
	vm.Close(&script_vm)
	fmt.println("CAMERA_VIEW_SMOKE_PASSED")
}
