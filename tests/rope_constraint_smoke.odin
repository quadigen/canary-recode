package main

import k "../src/engine/bindings"
import classes "../src/engine/classes"
import runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:math/linalg"

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.Run(v, source, "rope_constraint_smoke")
	assert(ok, err)
}

step :: proc(env: ^runtime.Environment, v: ^vm.VM, frames: int) {
	for _ in 0 ..< frames {runtime.Environment_Render_Step(env, v, 1.0 / 60.0)}
}

main :: proc() {
	v := vm.New()
	env: runtime.Environment
	runtime.Environment_Init(&env, &v)
	defer {vm.Close(&v); runtime.Environment_Destroy(&env)}
	physics := cast(^services.Physics)services.Ensure_Service(&env.services, "Physics")
	workspace := services.Ensure_Service(&env.services, "Workspace")
	run(
		&v,
		`
game:GetService("Physics").SleepThreshold = 0.2
left = Instance.new("Part", workspace)
left.Size = Vector3.one
left.CFrame = CFrame.new(-6, 14, 0)
right = left:Clone()
right.Parent = workspace
right.Position = Vector3.new(6, 14, 0)
support = Instance.new("Part", workspace)
support.Size = Vector3.new(4, 2, 10)
support.Position = Vector3.new(0, 6, 0)
rope = Instance.new("RopeConstraint", workspace)
rope.Length = 14
rope.Thickness = 0.3
rope.Attachment0 = Instance.new("Attachment", left)
rope.Attachment1 = Instance.new("Attachment", right)
assert(rope.Visible and rope.CanCollide and not rope.Active)
local copy = rope:Clone()
assert(copy.Length == 14 and math.abs(copy.Thickness - 0.3) < 1e-5 and copy.Visible and copy.CanCollide)
copy:Destroy()
`,
	)
	vm.GetGlobal(v.L, "rope")
	rope := cast(^classes.RopeConstraint)classes.Object_From_Argument(v.L, -1)
	vm.Pop(v.L)
	points: classes.Rope_Points
	preview_count := classes.RopeConstraint_Points(rope, workspace, &points)
	assert(
		preview_count > 2 && points[preview_count / 2].y < 13,
		"rope preview does not show slack",
	)
	assert(
		points[0] == k.JPH_RVec3{-6, 14, 0} && points[preview_count - 1] == k.JPH_RVec3{6, 14, 0},
	)
	vertices: classes.Rope_Vertices
	indices: classes.Rope_Indices
	index_count := classes.Rope_Build_Tube(
		points[:preview_count],
		rope.thickness * 0.5,
		&vertices,
		&indices,
	)
	assert(index_count > 0)
	for index in indices[:index_count] {assert(index < u32(preview_count * classes.ROPE_TUBE_STRIDE))}
	assert(abs(linalg.length([3]f32{vertices[0][3], vertices[0][4], vertices[0][5]}) - 1) < 1e-5)

	step(&env, &v, 120)
	assert(rope.jolt_rope != nil && rope.active)
	assert(k.JPH_PhysicsSystem_GetNumBodies(physics.system.handle) > 3)
	run(&v, `
left.Position = Vector3.new(-6, 9, 0)
right.Position = Vector3.new(6, 9, 0)
`)
	step(&env, &v, 240)
	count := classes.RopeConstraint_Points(rope, workspace, &points)
	assert(count == preview_count)
	supported := points[count / 2].y
	fmt.println("Rope above support:", supported)
	assert(supported > 7.04 && supported < 8.7, "rope did not drape over the support")
	assert(points[0] == k.JPH_RVec3{-6, 9, 0} && points[count - 1] == k.JPH_RVec3{6, 9, 0})
	chain := rope.jolt_rope
	run(&v, `rope.Visible = false; assert(rope.Active); rope.CanCollide = false`)
	step(&env, &v, 240)
	assert(rope.jolt_rope == chain, "changing collision rebuilt the rope")
	assert(classes.RopeConstraint_Points(rope, workspace, &points) == count)
	fmt.println("Rope through support with collision disabled:", points[count / 2].y)
	assert(points[count / 2].y < supported - 0.5, "disabling collision did not release the rope")

	run(&v, `rope.Enabled = false; assert(not rope.Active)`)
	assert(
		k.JPH_PhysicsSystem_GetNumBodies(physics.system.handle) == 3,
		"disabling rope leaked colliders",
	)
	run(&v, `
rope.Visible = true
rope.Enabled = true
right.Anchored = false
`)
	step(&env, &v, 240)
	run(
		&v,
		`
assert(rope.Active)
assert((right.Position - left.Position).Magnitude < rope.Length + 0.1, "rope failed to hold its load")
right:Destroy()
`,
	)
	step(&env, &v, 1)
	run(&v, `assert(rope.Attachment1 == nil and not rope.Active)`)
	assert(rope.jolt_rope == nil, "destroying an endpoint leaked the rope")
	assert(k.JPH_PhysicsSystem_GetNumBodies(physics.system.handle) == 2)

	run(
		&v,
		`
local terrain = game:GetService("Terrain")
terrain:FillBlock(CFrame.new(2,4,42), Vector3.new(12,8,24), Enum.Material.Rock)
local hit = workspace:Raycast(Vector3.new(0,20,40), Vector3.new(0,-20,0))
assert(hit, "terrain support has no collision surface")
terrainTop = hit.Position.Y
left.Position = Vector3.new(-6, terrainTop + 2, 40)
right = left:Clone()
right.Parent = workspace
right.Position = Vector3.new(6, terrainTop + 2, 40)
rope.Attachment1 = Instance.new("Attachment", right)
rope.CanCollide = true
`,
	)
	vm.GetGlobal(v.L, "terrainTop")
	terrain_top, ok := vm.ToNumber(v.L, -1)
	assert(ok)
	vm.Pop(v.L)
	step(&env, &v, 240)
	count = classes.RopeConstraint_Points(rope, workspace, &points)
	assert(count == preview_count)
	middle := points[count / 2]
	ground, found := services.Physics_Raycast(
		physics,
		workspace,
		{f64(middle.x), f64(terrain_top + 8), f64(middle.z)},
		{0, -16, 0},
	)
	assert(found, "rope missed the terrain support")
	fmt.println("Rope spawned over terrain:", middle.y, "terrain height:", ground.Position.y)
	assert(
		middle.y >= f64(ground.Position.y) - 0.04 && middle.y < f64(ground.Position.y) + 1,
		"rope spawned through the terrain",
	)
	fmt.println("ROPE_CONSTRAINT_SMOKE_PASSED")
}
