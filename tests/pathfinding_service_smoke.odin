package main

import "core:fmt"

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	ok, err := vm.RunInternal(&script_vm, `
	local PathfindingService = game:GetService("PathfindingService")
	assert(PathfindingService ~= nil)
	assert(PathfindingService:IsA("Service"))
	assert(game:GetService("PathfindingService") == PathfindingService)

	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Size = Vector3.new(200, 2, 200)
	floor.Position = Vector3.new(0, 5, 0)
	floor.Anchored = true
	floor.CanCollide = true
	floor.Parent = workspace

	local wall = Instance.new("Part")
	wall.Name = "Wall"
	wall.Size = Vector3.new(10, 20, 60)
	wall.Position = Vector3.new(0, 12, 0)
	wall.Anchored = true
	wall.CanCollide = true
	wall.Parent = workspace

	local agentParams = {
		AgentRadius = 2.0,
		AgentHeight = 5.0,
		AgentCanJump = false,
	}

	-- Every case below needs the navmesh rebuilt from the geometry as it stands at
	-- that moment. Waiting out the rebuild window is not possible from a synchronous
	-- test, and a different agent size always rebuilds immediately, so each case
	-- gets its own agent.
	local used_radii = {}
	local function agentFor(radius)
		assert(not used_radii[radius], "reused an agent radius, the case would reuse the cached mesh")
		used_radii[radius] = true
		return {
			AgentRadius = radius,
			AgentHeight = 5.0,
			AgentCanJump = false,
		}
	end

	local path = PathfindingService:CreatePath(agentParams)
	assert(path ~= nil)
	assert(path:IsA("Instance"))
	assert(path.ClassName == "Path")

	assert(path.Status ~= Enum.PathStatus.Success)
	assert(#path:GetWaypoints() == 0)

	path:ComputeAsync(Vector3.new(-60, 8, 0), Vector3.new(60, 8, 0))
	assert(path.Status == Enum.PathStatus.Success)

	local waypoints = path:GetWaypoints()
	assert(#waypoints > 1)

	assert((waypoints[1].Position - Vector3.new(-60, 8, 0)).Magnitude < 25)
	assert((waypoints[#waypoints].Position - Vector3.new(60, 8, 0)).Magnitude < 25)

	for _, waypoint in ipairs(waypoints) do
		assert(typeof(waypoint.Position) == "vector", "position not a vector")
		assert(waypoint.Action == Enum.PathWaypointAction.Walk
			or waypoint.Action == Enum.PathWaypointAction.Jump, "bad action")
		assert(waypoint.Label == nil, "label not nil")
	end

	local points = path:GetPointCoordinates()
	assert(#points == #waypoints, "point count mismatch")
	assert(typeof(points[1]) == "vector", "point not a vector")

	local occ = path:CheckOcclusionAsync(1)
	assert(occ == -1, "occlusion should be -1, got " .. tostring(occ))

	assert(path.Blocked ~= nil, "Blocked is nil")
	assert(path.Unblocked ~= nil, "Unblocked is nil")

	local direct = PathfindingService:FindPathAsync(
		Vector3.new(-40, 8, 40),
		Vector3.new(40, 8, 40)
	)
	assert(direct ~= nil)
	assert(direct.Status == Enum.PathStatus.Success)
	assert(#direct:GetWaypoints() > 1)

	local raw = PathfindingService:ComputeRawPathAsync(
		Vector3.new(-20, 8, 0),
		Vector3.new(20, 8, 0),
		100
	)
	assert(raw ~= nil)
	assert(raw.Status == Enum.PathStatus.Success)

	local smooth = PathfindingService:ComputeSmoothPathAsync(
		Vector3.new(-20, 8, 0),
		Vector3.new(20, 8, 0),
		100
	)
	assert(smooth ~= nil)

	assert(not pcall(function()
		PathfindingService:ComputeRawPathAsync(
			Vector3.new(0, 8, 0),
			Vector3.new(10, 8, 0),
			1000
		)
	end))

	assert(PathfindingService.EmptyCutoff ~= nil)

	local stranded = PathfindingService:CreatePath(agentParams)
	stranded:ComputeAsync(Vector3.new(0, 900, 0), Vector3.new(10, 900, 0))
	assert(stranded.Status ~= Enum.PathStatus.Success)
	assert(#stranded:GetWaypoints() == 0)

	-- A cached mesh must stay usable: asking the same question twice in a row must
	-- hit the cache and not invalidate itself.
	local repeatA = PathfindingService:CreatePath(agentParams)
	repeatA:ComputeAsync(Vector3.new(-40, 8, 40), Vector3.new(40, 8, 40))
	assert(repeatA.Status == Enum.PathStatus.Success)
	local firstCount = #repeatA:GetWaypoints()

	local repeatB = PathfindingService:CreatePath(agentParams)
	repeatB:ComputeAsync(Vector3.new(-40, 8, 40), Vector3.new(40, 8, 40))
	assert(repeatB.Status == Enum.PathStatus.Success)
	assert(#repeatB:GetWaypoints() == firstCount,
		"an unchanged scene must produce an identical path")

	-- Geometry changes are coalesced behind a short window, because a moving part
	-- would otherwise rebuild the mesh every frame. There is no way to wait out that
	-- window from a synchronous test, so each case below uses a different agent size
	-- instead, which always rebuilds immediately. That keeps every case a real
	-- differential test of the geometry rather than a test of the cache.
	local function highest_y(path)
		local highest = -math.huge
		for _, waypoint in ipairs(path:GetWaypoints()) do
			highest = math.max(highest, waypoint.Position.Y)
		end
		return highest
	end

	-- A part that cannot be queried contributes no geometry at all, so clearing the
	-- flag must take a floor away. The floor below is the only walkable surface in
	-- its region, so with the flag set the path across it has to succeed, and with
	-- the flag cleared it has to fail.
	local queryFloor = Instance.new("Part")
	queryFloor.Size = Vector3.new(60, 2, 60)
	queryFloor.Position = Vector3.new(300, 5, 0)
	queryFloor.Anchored = true
	queryFloor.CanCollide = true
	queryFloor.CanQuery = true
	queryFloor.Parent = workspace

	local seenA = PathfindingService:CreatePath(agentFor(3.0))
	seenA:ComputeAsync(Vector3.new(280, 8, 0), Vector3.new(320, 8, 0))
	assert(seenA.Status == Enum.PathStatus.Success,
		"a queryable floor must produce navigable geometry")

	queryFloor.CanQuery = false

	local seenB = PathfindingService:CreatePath(agentFor(3.25))
	seenB:ComputeAsync(Vector3.new(280, 8, 0), Vector3.new(320, 8, 0))
	assert(seenB.Status ~= Enum.PathStatus.Success,
		"a part with CanQuery=false must not produce navigable geometry")
	queryFloor:Destroy()

	-- The old implementation dropped every part below the origin, which silently
	-- removed any floor that sat below y = 0.
	local lower = Instance.new("Part")
	lower.Size = Vector3.new(60, 2, 60)
	lower.Position = Vector3.new(300, -20, 0)
	lower.Anchored = true
	lower.CanCollide = true
	lower.CanQuery = true
	lower.Parent = workspace

	local lowerPath = PathfindingService:CreatePath(agentFor(3.5))
	lowerPath:ComputeAsync(Vector3.new(280, -18, 0), Vector3.new(320, -18, 0))
	assert(lowerPath.Status == Enum.PathStatus.Success,
		"geometry below the origin must be navigable")
	assert(#lowerPath:GetWaypoints() > 1)
	lower:Destroy()

	-- A Wedge is a convex hull whose only walkable face is the slope. The slope runs
	-- along X and rises from the +X end to the vertical face at the -X end, so the
	-- ramp has to be approached from +X. Under the old bounding box approximation the
	-- whole box was walkable and the agent could stand on the vertical face; with the
	-- real shape it has to walk up the slope.
	local ramp = Instance.new("Part")
	ramp.Shape = Enum.PartType.Wedge
	ramp.Size = Vector3.new(20, 10, 20)
	ramp.Position = Vector3.new(0, 11, -60)
	ramp.Anchored = true
	ramp.CanCollide = true
	ramp.CanQuery = true
	ramp.Parent = workspace

	local rampPath = PathfindingService:CreatePath(agentFor(3.75))
	rampPath:ComputeAsync(Vector3.new(30, 8, -60), Vector3.new(0, 12.5, -60))
	assert(rampPath.Status == Enum.PathStatus.Success,
		"the walkable slope of a Wedge must be reachable")

	-- The path has to climb the slope rather than teleport onto the finish, so it has
	-- to end well above the floor it started on.
	local rampHigh = highest_y(rampPath)
	assert(rampHigh > 10,
		"expected the path to climb the ramp, highest y was " .. tostring(rampHigh))
	ramp:Destroy()

	-- Geometry that appears and disappears has to be picked up on the next rebuild.
	-- This platform is the only walkable surface in its region, so it is present means
	-- a path succeeds and removed means the region has no mesh left to path on.
	local platform = Instance.new("Part")
	platform.Size = Vector3.new(60, 2, 60)
	platform.Position = Vector3.new(300, 5, 0)
	platform.Anchored = true
	platform.CanCollide = true
	platform.CanQuery = true
	platform.Parent = workspace

	local covered = PathfindingService:CreatePath(agentFor(4.0))
	covered:ComputeAsync(Vector3.new(280, 8, 0), Vector3.new(320, 8, 0))
	assert(covered.Status == Enum.PathStatus.Success,
		"a newly added platform must produce navigable geometry")
	platform:Destroy()

	local uncovered = PathfindingService:CreatePath(agentFor(4.25))
	uncovered:ComputeAsync(Vector3.new(280, 8, 0), Vector3.new(320, 8, 0))
	assert(uncovered.Status ~= Enum.PathStatus.Success,
		"a destroyed platform must be dropped from the rebuilt mesh")
	`, "pathfinding_service_smoke")

	if !ok {
		fmt.eprintln(err)
		delete(err)
		vm.Close(&script_vm)
		engine_runtime.Environment_Destroy(&environment)
		panic("PathfindingService smoke test failed")
	}

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("PATHFINDING_SERVICE_SMOKE_PASSED")
}