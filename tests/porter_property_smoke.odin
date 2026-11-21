package main

import classes "../src/engine/classes"
import runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"

run :: proc(state: ^vm.VM, source: string) {
	ok, err := vm.RunInternal(state, source, "porter_property_smoke")
	assert(ok, err)
}
main :: proc() {
	state := vm.New()
	environment: runtime.Environment
	runtime.Environment_Init(&environment, &state)
	run(
		&state,
		`
local root = Instance.new("Model")
root.Name = "PorterPropertyTest"
local p = Instance.new("Part",root)
p.BackSurfaceInput = Enum.InputType.Constant
local e = Instance.new("ParticleEmitter",p)
e.Shape = Enum.ParticleEmitterShape.Sphere
e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
e.Orientation = Enum.ParticleOrientation.VelocityParallel
local cam = Instance.new("Camera",root)
cam.ProjectionType = Enum.ProjectionType.Orthographic
local variant = Instance.new("MaterialVariant",root)
variant.BaseMaterial = Enum.Material.Metal
local gradient = Instance.new("UIGradient",root)
gradient.Type = Enum.GradientType.Radial
gradient.TileMode = Enum.GradientTileMode.Mirror
local p2 = Instance.new("Part",root)
p2.Name = "Target"
local noCollision = Instance.new("NoCollisionConstraint",p)
noCollision.Part0,noCollision.Part1 = p,p2
local sm = Instance.new("SpecialMesh",p)
sm.MeshType = Enum.MeshType.Sphere
sm.Scale = Vector3.new(2,3,4)
sm.Offset = Vector3.new(0,1,0)
local billboard = Instance.new("BillboardGui",p)
billboard.Adornee = p2
billboard.Size = UDim2.new(3,10,2,20)
local sky = Instance.new("Sky",root)
sky.SkyboxRt = "rbxassetid://123"
sky.StarCount = 100
porterRoot = root
`,
	)
	vm.GetGlobal(state.L, "porterRoot")
	root := classes.Object_From_Argument(state.L, -1)
	vm.Pop(state.L)
	assert(root != nil)
	err := serializer.Serialize_To_File(
		&environment.classes,
		state.L,
		root,
		"build/porter-property-smoke.kine",
	)
	assert(serializer.Error_Is_None(err))
	serializer.Error_Delete(&err)
	loaded, load_err := serializer.Deserialize_From_File(
		&environment.classes,
		state.L,
		nil,
		"build/porter-property-smoke.kine",
	)
	if !serializer.Error_Is_None(load_err) {serializer.Error_Print(load_err, "porter load: ")}
	assert(loaded != nil)
	serializer.Error_Delete(&load_err)
	classes.Push_Object(state.L, loaded)
	vm.SetGlobal(state.L, "restored")
	run(
		&state,
		`
assert(restored.Part.BackSurfaceInput == Enum.InputType.Constant)
assert(restored.Part.ParticleEmitter.Shape == Enum.ParticleEmitterShape.Sphere)
assert(restored.Part.ParticleEmitter.ShapeInOut == Enum.ParticleEmitterShapeInOut.Inward)
assert(restored.Camera.ProjectionType == Enum.ProjectionType.Orthographic)
assert(restored.MaterialVariant.BaseMaterial == Enum.Material.Metal)
assert(restored.UIGradient.Type == Enum.GradientType.Radial)
assert(restored.UIGradient.TileMode == Enum.GradientTileMode.Mirror)
assert(restored.Part.NoCollisionConstraint.Part0 == restored.Part)
assert(restored.Part.NoCollisionConstraint.Part1 == restored.Target)
assert(restored.Part.SpecialMesh.Scale == Vector3.new(2,3,4))
assert(restored.Part.SpecialMesh.MeshType == Enum.MeshType.Sphere)
assert(restored.Part.BillboardGui.Adornee == restored.Target)
assert(restored.Part.BillboardGui.Size == UDim2.new(3,10,2,20))
assert(restored.Sky.SkyboxRt == "rbxassetid://123" and restored.Sky.StarCount == 100)

`,
	)
	if len(os.args) > 1 {
		assert(runtime.Load_Map(&environment, &state, os.args[1]))
		run(
			&state,
			`
local counts = {}
for _,item in game:GetDescendants() do counts[item.ClassName] = (counts[item.ClassName] or 0)+1 end
for class, minimum in {ParticleEmitter=35,NoCollisionConstraint=387,PlaneConstraint=92,UniversalConstraint=24,CylindricalConstraint=8,LinearVelocity=2,AlignOrientation=1,SpecialMesh=116,BillboardGui=1,Sky=1} do
	print("Imported",class,counts[class])
	assert((counts[class] or 0) >= minimum,class)
end
local sky=game:GetService("Lighting"):FindFirstChildOfClass("Sky")
assert(sky)
for _,face in {"Rt","Lf","Up","Dn","Bk","Ft"} do
    local uri=sky["Skybox"..face]
    assert(type(uri)=="string" and #uri>0,"Missing imported skybox face "..face)
    print(face,uri)
end
`,
		)
	}
	vm.Close(&state)
	runtime.Environment_Destroy(&environment)
	fmt.println("PORTER_PROPERTY_SMOKE_PASSED")
}
