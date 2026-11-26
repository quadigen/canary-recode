package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)
	ok, err := vm.RunInternal(
		&script_vm,
		`
local service = game:GetService("PathfindingService")
assert(service.MaxSlope == 60)
assert(not pcall(function() service.MaxSlope = 90 end))
assert(not pcall(function() service.MaxSlope = -1 end))
assert(service.MaxSlope == 60)

local region = Instance.new("Model", workspace)
region.Name = "NavigationRegion"
local floor = Instance.new("Part", region)
floor.Size = Vector3.new(60, 2, 60)
floor.Position = Vector3.new(300, 5, 0)
floor.Anchored = true
floor.CanCollide = true
floor.CanQuery = true
local path = service:CreatePath({AgentRadius=2, AgentHeight=5, AgentCanJump=false})
local start = Vector3.new(280,8,0)
local finish = Vector3.new(320,8,0)
local function succeeds()
    path:ComputeAsync(start, finish)
    return path.Status == Enum.PathStatus.Success
end
assert(succeeds(), "baseline region should be navigable")

floor:SetAttribute("NavigationExcluded", true)
service:InvalidateNavigation()
assert(not succeeds(), "excluded part must not contribute navmesh geometry")
floor:SetAttribute("NavigationExcluded", false)
service:InvalidateNavigation()
assert(succeeds(), "restored part must contribute geometry")

region:SetAttribute("NavigationExcluded", true)
service:InvalidateNavigation()
assert(not succeeds(), "ancestor NavigationExcluded must apply to descendants")
region:SetAttribute("NavigationExcluded", false)
service:InvalidateNavigation()
assert(succeeds(), "clearing ancestor exclusion must restore geometry")

service.MaxSlope = 45
assert(service.MaxSlope == 45)
assert(succeeds(), "ordinary flat floor must remain navigable with lower max slope")
region:Destroy()
`,
		"navigation_authoring",
	)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("navigation authoring smoke failed")
	}
	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("NAVIGATION_AUTHORING_SMOKE_PASSED")
}
