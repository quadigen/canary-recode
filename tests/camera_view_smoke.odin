package main

import classes "../src/engine/classes"
import datatypes "../src/engine/datatypes"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

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
	assert(abs(view.z + 10) < 1.0e-6)
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm, &renderer_object)
	ok, err := vm.Run(
		&script_vm,
		`
local original = workspace.CurrentCamera
assert(original and original:IsA("Camera") and original.Parent == workspace)
original.FieldOfView = 45
assert(original:Clone().FieldOfView == 45)
original.CFrame = CFrame.new(2, 3, 4) * CFrame.Angles(0.2, 0.4, 0)
assert(vector.magnitude(original.CFrame.Position - vector.create(2, 3, 4)) < 0.0001)
local replacement = Instance.new("Camera")
replacement.Parent = workspace
workspace.CurrentCamera = replacement
assert(workspace.CurrentCamera == replacement)
`,
		"camera_properties",
	)
	if !ok {fmt.eprintln(err); panic("Camera properties failed")}
	workspace := cast(^services.Workspace)services.Ensure_Service(
		&environment.services,
		"Workspace",
	)
	assert(renderer_object.ActiveCamera == rawptr(workspace.current_camera))


	replicator := cast(^services.ReplicatorService)services.Ensure_Service(
		&environment.services,
		"ReplicatorService",
	)
	schema := services.replication_schema(replicator, "Camera")
	assert(schema != nil)
	assert(services.replication_schema_has(schema, "FieldOfView"))
	assert(!services.replication_schema_has(schema, "ViewportSize"))
	assert(!services.replication_schema_has(schema, "DiagonalFieldOfView"))

	ok, err = vm.Run(
		&script_vm,
		`
local worldCamera = workspace.CurrentCamera
local viewport = Instance.new("ViewportFrame", game.CoreGui)
local preview = Instance.new("Camera", viewport)
viewport.CurrentCamera = preview
cameraViewportEvents = 0
cameraChangedEvents = 0
worldCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	cameraViewportEvents += 1
end)
worldCamera.Changed:Connect(function(property)
	if property == "ViewportSize" then
		cameraChangedEvents += 1
		preview.CFrame = worldCamera.CFrame
		preview.FieldOfView = worldCamera.FieldOfView
		cameraPreviewParent = viewport
	end
end)
`,
		"viewport_camera_change_setup",
	)
	assert(ok, err)
	renderer_object.HasViewportRect = true
	renderer_object.ViewportRect = {0, 0, 800, 600}
	ctx := classes.Class_Step_Context {
		L        = script_vm.L,
		renderer = &renderer_object,
	}
	classes.Camera_Step(&workspace.current_camera.object, &ctx)
	classes.Camera_Step(&workspace.current_camera.object, &ctx)
	ok, err = vm.Run(
		&script_vm,
		`
assert(cameraViewportEvents == 1)
assert(cameraChangedEvents == 1)
assert(cameraPreviewParent ~= nil)
assert(cameraPreviewParent.CurrentCamera.CFrame == workspace.CurrentCamera.CFrame)
`,
		"viewport_camera_change_result",
	)
	assert(ok, err)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("CAMERA_VIEW_SMOKE_PASSED")
}
