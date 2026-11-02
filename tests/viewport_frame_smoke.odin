package main
import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	script_vm := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm)
	defer {vm.Close(&script_vm); engine_runtime.Environment_Destroy(&env)}
	source := `
local reflection = game:GetService("ReflectionService")
assert(reflection:GetClass("ViewportFrame"))
local screen = Instance.new("ScreenGui", game.CoreGui)
local frame = Instance.new("ViewportFrame", screen)
frame.Name = "Preview"
assert(frame:IsA("GuiObject"))
assert(frame.CurrentCamera == nil and frame.ImageTransparency == 0)
assert(frame.ResolutionScale == 1 and frame.UpdateRate == 60)
assert(frame.Shadows and frame.PostProcessing)
frame.Shadows = false
frame.PostProcessing = false
frame.Size = UDim2.fromOffset(128,128)
frame.Ambient = Color3.new(0.2,0.3,0.4)
frame.LightColor = Color3.new(0.5,0.6,0.7)
frame.LightDirection = Vector3.new(1,-1,-1)
frame.ImageColor3 = Color3.new(0.7,0.8,0.9)
frame.ImageTransparency = 0.25
frame.ResolutionScale = 0.5
frame.UpdateRate = 30
local camera = Instance.new("Camera", frame)
camera.Name = "PreviewCamera"
camera.FieldOfView = 45
camera.CFrame = CFrame.new(0,0,10)
frame.CurrentCamera = camera
assert(camera.FieldOfView == 45)
local model = Instance.new("Model",frame)
local part = Instance.new("Part",model)
part.Size = Vector3.new(3,3,3)
part.Color = Color3.new(0,1,0)
local copy = frame:Clone()
assert(copy.CurrentCamera ~= camera and copy.CurrentCamera:IsDescendantOf(copy))
assert(copy.CurrentCamera.FieldOfView == 45)
assert(copy.Ambient == frame.Ambient and copy.LightColor == frame.LightColor)
assert(copy.ImageColor3 == frame.ImageColor3 and copy.ImageTransparency == 0.25)
assert(copy.ResolutionScale == 0.5 and copy.UpdateRate == 30)
assert(not copy.Shadows and not copy.PostProcessing)
copy:Destroy()
assert(not pcall(function() frame.CurrentCamera = part end))
camera:Destroy()
assert(frame.CurrentCamera == nil, "destroyed camera reference was retained")
-- A preview under Workspace is still an isolated GUI, never a physics body.
frame.Parent = workspace
frame.Position = UDim2.fromOffset(0,0)
for i=1,1000 do
    local other = Instance.new("ViewportFrame",screen)
    other.Name = "UnusedPreview"
end
`
	ok, err := vm.Run(&script_vm, source, "viewport_frame_properties")
	if !ok {fmt.eprintln(err); panic("viewport frame smoke failed")}
	physics := cast(^services.Physics)services.Ensure_Service(&env.services, "Physics")
	workspace := services.Ensure_Service(&env.services, "Workspace")
	services.Physics_Synchronize(physics, workspace)
	assert(len(physics.bodies) == 0, "preview parts leaked into world physics")
	descriptor := classes.Find_Class(&env.classes, "ViewportFrame")
	assert(descriptor != nil && len(descriptor.instances) >= 1001)
	for object in descriptor.instances {
		frame := cast(^classes.ViewportFrame)object
		assert(frame.native == nil, "unrendered frames allocated renderer resources")
	}
	fmt.println("VIEWPORT_FRAME_SMOKE_PASSED")
}
