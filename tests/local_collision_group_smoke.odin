package main
import runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run :: proc(state: ^vm.VM, source: string) {
	ok, err := vm.Run(state, source, "collision_group_smoke")
	if !ok {fmt.eprintln(err); panic("collision groups failed")}
}

main :: proc() {
	state := vm.New()
	env: runtime.Environment
	runtime.Environment_Init(&env, &state)
	run(
		&state,
		`
local ps = game:GetService("PhysicsService")
assert(ps:GetMaxCollisionGroups() == 32)
ps:RegisterCollisionGroup("Ghost")
assert(ps:IsCollisionGroupRegistered("Ghost"))
ps:CollisionGroupSetCollidable("Default","Ghost",false)
assert(not ps:CollisionGroupsAreCollidable("Ghost","Default"))
floor = Instance.new("Part",workspace)
floor.Size = Vector3.new(60,1,60)
floor.Position = Vector3.zero
floor.Anchored = true
ghost = Instance.new("Part",workspace)
ghost.Size = Vector3.one
ghost.Position = Vector3.new(0,10,0)
ghost.Anchored = false
ghost.CollisionGroup = "Ghost"
solid = Instance.new("Part",workspace)
solid.Size = Vector3.one
solid.Position = Vector3.new(5,10,0)
solid.Anchored = false
assert(not ghost:CanCollideWith(floor))
assert(solid:CanCollideWith(floor))
`,
	)
	for i in 0 ..< 60 {runtime.Environment_Update_Step(&env, &state, 1.0 / 60.0)}
	run(
		&state,
		`
assert(ghost.Position.Y < -1, tostring(ghost.Position))
assert(solid.Position.Y > 0, tostring(solid.Position))
local ps = game:GetService("PhysicsService")
ps:RenameCollisionGroup("Ghost","NewGhost")
assert(ghost.CollisionGroup == "NewGhost")
assert(not ps:CollisionGroupsAreCollidable("NewGhost","Default"))
ps:CollisionGroupSetCollidable("NewGhost","Default",true)
assert(ghost:CanCollideWith(floor))
ghost.Position = Vector3.new(0,10,0)
ghost.AssemblyLinearVelocity = Vector3.zero
`,
	)
	for i in 0 ..< 60 {runtime.Environment_Update_Step(&env, &state, 1.0 / 60.0)}
	run(
		&state,
		`
assert(ghost.Position.Y > 0,tostring(ghost.Position))
local ps = game:GetService("PhysicsService")
ps:UnregisterCollisionGroup("NewGhost")
assert(ghost.CollisionGroup == "Default")
assert(not ps:IsCollisionGroupRegistered("NewGhost"))
`,
	)
	vm.Close(&state)
	runtime.Environment_Destroy(&env)
	fmt.println("LOCAL_COLLISION_GROUP_SMOKE_PASSED")
}
