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
falling = Instance.new("Part", workspace)
falling.Size = vector.create(2, 2, 2)
falling.CFrame = CFrame.new(0, 10, 0)
`, "workspace_physics")

	fmt.println("before first physics step")
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0/60.0)
	fmt.println("after first physics step")
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
	fmt.println("after cleanup physics step")
	run_script(&script_vm, `assert(game:GetService("Physics").BodyCount == 0)`, "workspace_physics_cleanup")

	fmt.println("before vm close")
	vm.Close(&script_vm)
	fmt.println("after vm close")
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("WORKSPACE_PHYSICS_SMOKE_PASSED")
}
