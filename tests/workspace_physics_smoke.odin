package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("workspace physics smoke test failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	run_script(&script_vm, `
local physics = game:GetService("Physics")
assert(physics:IsA("Service"))
assert(physics.Enabled)
assert(math.abs(physics.Gravity - 196.2) < 0.001)
assert(math.abs(workspace.Gravity - 196.2) < 0.001)

workspace.Gravity = 100
assert(physics.Gravity == 100 and workspace.Gravity == 100)
assert(workspace.FallenPartsDestroyHeight == -500)
assert(workspace.FallHeightEnabled)

local model = Instance.new("Model", workspace)
local part = Instance.new("Part", model)
part.Name = "Target"
part.Anchored = true
part.Size = vector.create(4, 4, 4)
part.CFrame = CFrame.new(0, 0, 0)
part.Material = Enum.Material.Concrete

local result = workspace:Raycast(vector.create(0, 0, -10), vector.create(0, 0, 20))
assert(typeof(result) == "RaycastResult")
assert(result.Instance == part)
assert(result.Material == Enum.Material.Concrete)
assert(math.abs(result.Distance - 8) < 0.01)
assert(math.abs(result.Position.Z + 2) < 0.01)
assert(result.Normal.Z < -0.99)
assert(physics.BodyCount == 1)

local params = RaycastParams.new()
assert(typeof(params) == "RaycastParams")
assert(params.FilterType == Enum.RaycastFilterType.Exclude)
assert(params.CollisionGroup == "Default")
params.FilterDescendantsInstances = {model}
assert(workspace:Raycast(vector.create(0, 0, -10), vector.create(0, 0, 20), params) == nil)

params.FilterType = Enum.RaycastFilterType.Include
assert(workspace:Raycast(vector.create(0, 0, -10), vector.create(0, 0, 20), params).Instance == part)

params.FilterDescendantsInstances = {}
params.FilterType = Enum.RaycastFilterType.Exclude
params.ExcludeInstances = nil
params.IncludeInstances = {model}
assert(workspace:Raycast(vector.create(0, 0, -10), vector.create(0, 0, 20), params).Instance == part)
params.ExcludeInstances = {part}
assert(workspace:Raycast(vector.create(0, 0, -10), vector.create(0, 0, 20), params) == nil)

params.ExcludeInstances = nil
params.IncludeInstances = nil
params.FilterType = Enum.RaycastFilterType.Exclude
part.CanQuery = false
assert(workspace:Raycast(vector.create(0, 0, -10), vector.create(0, 0, 20), params) == nil)
params.BruteForceAllSlow = true
assert(workspace:Raycast(vector.create(0, 0, -10), vector.create(0, 0, 20), params).Instance == part)

part:Destroy()

local queryModel = Instance.new("Model", workspace)
local function makePart(position, size)
	local p = Instance.new("Part", queryModel)
	p.Anchored = true
	p.Position = position
	p.Size = size
	return p
end

local sphere = makePart(vector.create(30, 0, 0), vector.create(4, 4, 4))
sphere.Shape = Enum.PartType.Ball
local probe = makePart(vector.create(31.8, 1.8, 0), vector.create(0.2, 0.2, 0.2))
local overlap = OverlapParams.new()
overlap.IncludeInstances = {queryModel}
overlap.ExcludeInstances = {probe}
assert(workspace:GetPartBoundsInBox(probe.CFrame, probe.Size, overlap)[1] == sphere)
assert(#workspace:GetPartsInPart(probe, overlap) == 0)
probe.Position = vector.create(31.9, 0, 0)
assert(workspace:GetPartsInPart(probe)[1] == sphere)
probe.Position = vector.create(32.12, 0, 0)
assert(#workspace:GetPartsInPart(probe, overlap) == 0)
overlap.Tolerance = 0.05
assert(workspace:GetPartsInPart(probe, overlap)[1] == sphere)
overlap.Tolerance = 0
probe.Position = vector.create(31.9, 0, 0)
sphere.Parent = nil
assert(#workspace:GetPartsInPart(probe) == 0)
sphere.Parent = queryModel

sphere.CanQuery = false
local sphereCenter = sphere.CFrame.Position
assert(#workspace:GetPartBoundsInRadius(sphereCenter, 2, overlap) == 0)
overlap.RespectCanCollide = true
assert(workspace:GetPartBoundsInRadius(sphereCenter, 2, overlap)[1] == sphere)
overlap.BruteForceAllSlow = true
overlap.ExcludeInstances = nil
overlap.MaxParts = 1
assert(overlap.MaxParts == 1)
assert(#workspace:GetPartBoundsInRadius(sphereCenter, 5, overlap) == 1)

local beam = makePart(vector.create(50, 0, 0), vector.create(8, 1, 1))
beam.CFrame = beam.CFrame * CFrame.Angles(0, 0, math.pi / 4)
assert(#workspace:GetPartBoundsInRadius(vector.create(52.5, -2.5, 0), 0.1) == 0)
assert(workspace:GetPartBoundsInRadius(vector.create(52.5, 2.5, 0), 0.1)[1] == beam)
local marker = makePart(vector.create(62.5, 2.5, 0), vector.create(0.1, 0.1, 0.1))
local rotatedBox = CFrame.new(60, 0, 0) * CFrame.Angles(0, 0, math.pi / 4)
assert(workspace:GetPartBoundsInBox(rotatedBox, beam.Size)[1] == marker)
assert(#workspace:GetPartBoundsInBox(CFrame.new(60, 0, 0), beam.Size) == 0)

local size = vector.create(2, 2, 2)
local selected = makePart(vector.create(100, 0, 0), size)
local selectedNeighbor = makePart(vector.create(102, 0, 0), size)
local outsider = makePart(vector.create(98, 0, 0), size)
local roundNeighbor = makePart(vector.create(100, 2, 0), size)
roundNeighbor.Shape = Enum.PartType.Ball
local internalWeld = Instance.new("WeldConstraint", selectedNeighbor)
internalWeld.Part0 = selected
internalWeld.Part1 = selectedNeighbor
local selection = {selected, selectedNeighbor, selected}

workspace:JoinToOutsiders(selection, Enum.JointCreationMode.None)
assert(#selected:GetChildren() == 0)
assert(not pcall(function() workspace:JoinToOutsiders({selected, queryModel}) end))
assert(#selected:GetChildren() == 0)
workspace:JoinToOutsiders(selection, Enum.JointCreationMode.All)
workspace:JoinToOutsiders(selection, Enum.JointCreationMode.Surface)
local welds = selected:GetChildren()
assert(#welds == 1 and welds[1]:IsA("WeldConstraint"))
assert(welds[1].Part0 == selected and welds[1].Part1 == outsider)
workspace:UnjoinFromOutsiders(selection)
assert(#selected:GetChildren() == 0)
assert(internalWeld.Parent == selectedNeighbor)
queryModel:Destroy()

falling = Instance.new("Part", workspace)
falling.Anchored = false
falling.Size = vector.create(2, 2, 2)
falling.CFrame = CFrame.new(0, 10, 0)
`, "workspace_physics")

	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0/60.0)
	run_script(&script_vm, `
assert(game:GetService("Physics").BodyCount == 1)
assert(falling.CFrame.Y < 10)
assert(workspace.DistributedGameTime > 0)
assert(workspace:GetPhysicsThrottling() == 0)
assert(workspace:GetRealPhysicsFPS() == 60)
assert(workspace:PGSIsEnabled())
	falling:Destroy()
`, "workspace_physics_after_step")
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0/60.0)
	run_script(&script_vm, `assert(game:GetService("Physics").BodyCount == 0)`, "workspace_physics_cleanup")

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("WORKSPACE_PHYSICS_SMOKE_PASSED")
}
