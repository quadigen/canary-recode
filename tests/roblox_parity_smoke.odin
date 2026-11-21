package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	state := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &state)
	source := `
assert(math.abs(Color3.new(1,1,1):GetLuminance()-1) < 1e-6)
assert(math.abs(Color3.new(0,0,0):GetContrastRatio(Color3.new(1,1,1))-21) < 1e-6)
assert(Color3.new(0,0,0):GetContrastingColor() == Color3.new(1,1,1))
for _, order in Enum.RotationOrder:GetEnumItems() do
	local c = CFrame.fromEulerAngles(0.2,0.3,0.4,order)
	local x,y,z = c:ToEulerAngles(order)
	assert(c:FuzzyEq(CFrame.fromEulerAngles(x,y,z,order), 1e-5))
end
assert((CFrame.fromRotationBetweenVectors(Vector3.yAxis, Vector3.xAxis)*Vector3.yAxis):FuzzyEq(Vector3.xAxis))
assert((CFrame.fromRotationBetweenVectors(Vector3.yAxis, -Vector3.yAxis)*Vector3.yAxis):FuzzyEq(-Vector3.yAxis))
assert(Content.fromAssetId(123456789).Uri == "rbxassetid://123456789")
assert(Font.fromId(123).Family == "rbxassetid://123")
local cas = game:GetService("ContextActionService")
cas:BindActionAtPriority("jump", function() end, false, 3000, Enum.KeyCode.Space)
local info = cas:GetBoundActionInfo("jump")
assert(info.priorityLevel == 3000 and info.inputTypes[1] == Enum.KeyCode.Space)
assert(cas:GetAllBoundActionInfo().jump.priorityLevel == 3000)
cas:UnbindAllActions()
assert(next(cas:GetAllBoundActionInfo()) == nil)

local a, b, c = Instance.new("Part", workspace), Instance.new("Part", workspace), Instance.new("Part", workspace)
a.Anchored, b.Anchored, c.Anchored = false, false, true
local ab, bc = Instance.new("WeldConstraint", workspace), Instance.new("WeldConstraint", workspace)
ab.Part0, ab.Part1 = a, b
bc.Part0, bc.Part1 = b, c
assert(#a:GetConnectedParts() == 1 and a:GetConnectedParts()[1] == b)
assert(#a:GetConnectedParts(true) == 2)
assert(a:IsGrounded() and b:IsGrounded() and c:IsGrounded())
local duplicate = Instance.new("WeldConstraint", workspace)
duplicate.Part0, duplicate.Part1 = a, b
assert(#a:GetConnectedParts() == 1)
assert(#b:GetJoints() == 3)
local exclusion = Instance.new("NoCollisionConstraint", workspace)
exclusion.Part0, exclusion.Part1 = a, c
assert(#a:GetNoCollisionConstraints() == 1 and a:GetNoCollisionConstraints()[1] == exclusion)
assert(#a:GetJoints() == 2)
exclusion.Enabled = false
assert(#a:GetNoCollisionConstraints() == 0)
exclusion.Enabled = true
bc.Enabled = false
assert(#b:GetJoints() == 2)
assert(not a:IsGrounded() and #a:GetConnectedParts(true) == 1)
bc.Enabled = true
c.Parent = nil
assert(#b:GetJoints() == 2 and #a:GetNoCollisionConstraints() == 0)
assert(not a:IsGrounded() and #a:GetConnectedParts(true) == 1)
c.Parent = workspace
assert(a:IsGrounded())
bc:Destroy()
assert(not a:IsGrounded())
local hinge = Instance.new("HingeConstraint", workspace)
hinge.Attachment0 = Instance.new("Attachment", b)
hinge.Attachment1 = Instance.new("Attachment", c)
assert(#b:GetJoints() == 3)
assert(not a:IsGrounded() and #a:GetConnectedParts(true) == 1)
hinge:Destroy()
local d = Instance.new("Part", workspace)
d.Anchored = false
local bd, da = Instance.new("WeldConstraint", workspace), Instance.new("WeldConstraint", workspace)
bd.Part0, bd.Part1 = b, d
da.Part0, da.Part1 = d, a
assert(#a:GetConnectedParts(true) == 2 and not a:IsGrounded())
bd:Destroy()
da:Destroy()
d:Destroy()
local mesh = Instance.new("MeshPart", workspace)
mesh.Anchored = false
assert(#mesh:GetConnectedParts() == 0 and not mesh:IsGrounded())
mesh:Destroy()
a:Destroy()
b:Destroy()
c:Destroy()
ab:Destroy()
duplicate:Destroy()
exclusion:Destroy()

local assets = game:GetService("AssetService")
local image = assets:CreateImage({Size = Vector2.new(8, 8)})
assert(image:IsA("Image"))
local label = Instance.new("ImageLabel")
label.Image = image
assert(label.Image == image and label.IsLoaded)
local button = Instance.new("ImageButton")
button.Image = image
assert(button.Image == image)
local buttonClone = button:Clone()
assert(buttonClone.Image == image)
buttonClone:Destroy()
button:Destroy()
label:Destroy()
local function rgba(x, y)
	local p = image:ReadPixelsBuffer(Vector2.new(x, y), Vector2.one)
	return buffer.readu8(p, 0), buffer.readu8(p, 1), buffer.readu8(p, 2), buffer.readu8(p, 3)
end
image:DrawRectangle(Vector2.zero, image.Size, Color3.new(1, 0, 0))
local r, g, b, a = rgba(0, 0)
assert(r == 255 and g == 0 and b == 0 and a == 255)
image:DrawCircle(Vector2.new(3, 3), 2, Color3.new(0, 1, 0), 0, Enum.ImageCombineType.Overwrite, Enum.AntiAliasing.Disabled)
r, g, b, a = rgba(3, 3)
assert(r == 0 and g == 255 and b == 0 and a == 255)
image:DrawLine(Vector2.new(0, 7), Vector2.new(7, 7), Color3.new(0, 0, 1))
r, g, b, a = rgba(4, 7)
assert(r == 0 and g == 0 and b == 255 and a == 255)
local stamp = assets:CreateImage({Size = Vector2.one})
stamp:DrawRectangle(Vector2.zero, Vector2.one, Color3.new(1, 1, 1))
image:DrawImage(Vector2.new(1, 1), stamp)
r, g, b, a = rgba(1, 1)
assert(r == 255 and g == 255 and b == 255 and a == 255)
`
	ok, err := vm.Run(&state, source, "roblox_parity_smoke")
	if !ok {
		fmt.eprintln(err)
		panic("Roblox parity smoke failed")
	}
	vm.Close(&state)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("ROBLOX_PARITY_SMOKE_PASSED")
}
