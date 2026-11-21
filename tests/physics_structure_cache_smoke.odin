package main

import classes "../src/engine/classes"
import runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.Run(v, source, "physics_structure_cache_smoke")
	assert(ok, err)
}

main :: proc() {
	v := vm.New()
	env: runtime.Environment
	runtime.Environment_Init(&env, &v)
	defer {vm.Close(&v); runtime.Environment_Destroy(&env)}
	physics := cast(^services.Physics)services.Ensure_Service(&env.services, "Physics")
	workspace := services.Ensure_Service(&env.services, "Workspace")
	assert(physics != nil && workspace != nil)
	services.Physics_Synchronize(physics, workspace)
	base := len(physics.bodies)
	run(
		&v,
		`
group = Instance.new("Folder", workspace)
part = Instance.new("Part", group)
part.Anchored = true
part.Position = Vector3.new(0, 40, 0)
other = Instance.new("Part", group)
other.Anchored = true
other.Position = Vector3.new(0, 50, 0)
joint = Instance.new("WeldConstraint", group)
joint.Part0, joint.Part1 = part, other
`,
	)
	services.Physics_Synchronize(physics, workspace)
	assert(len(physics.bodies) == base + 2)
	services.Physics_StepConstraints(workspace, physics, 1.0 / 60)
	assert(len(physics.constraint_steps) == 1)
	epoch := classes.Hierarchy_Structure_Epoch()
	run(&v, `part.Position = Vector3.new(2, 40, 0)`)
	assert(classes.Hierarchy_Structure_Epoch() == epoch)
	services.Physics_Synchronize(physics, workspace)
	services.Physics_StepConstraints(workspace, physics, 1.0 / 60)
	assert(physics.constraint_epoch == epoch)
	assert(len(physics.constraint_steps) == 1)
	run(&v, `group.Parent = nil`)
	services.Physics_Synchronize(physics, workspace)
	services.Physics_StepConstraints(workspace, physics, 1.0 / 60)
	assert(len(physics.bodies) == base)
	assert(len(physics.constraint_steps) == 0)
	run(&v, `group.Parent = workspace`)
	services.Physics_Synchronize(physics, workspace)
	services.Physics_StepConstraints(workspace, physics, 1.0 / 60)
	assert(len(physics.bodies) == base + 2)
	assert(len(physics.constraint_steps) == 1)
	run(
		&v,
		`
viewport = Instance.new("ViewportFrame")
viewport.Parent = workspace
group.Parent = viewport
`,
	)
	services.Physics_Synchronize(physics, workspace)
	services.Physics_StepConstraints(workspace, physics, 1.0 / 60)
	assert(len(physics.bodies) == base)
	assert(len(physics.constraint_steps) == 0)
	run(
		&v,
		`group.Parent = workspace; viewport:Destroy(); joint:Destroy(); part.Material = Enum.Material.Water`,
	)
	runtime.Environment_Update_Step(&env, &v, 1.0 / 60)
	assert(len(physics.constraint_steps) == 0)
	assert(len(physics.bodies) == base + 1)
	run(&v, `part.Material = Enum.Material.Plastic`)
	services.Physics_Synchronize(physics, workspace)
	assert(len(physics.bodies) == base + 2)
	run(&v, `group:Destroy()`)
	runtime.Environment_Update_Step(&env, &v, 1.0 / 60)
	assert(len(physics.bodies) == base)
	assert(len(physics.constraint_steps) == 0)
	fmt.println("PHYSICS_STRUCTURE_CACHE_SMOKE_PASSED")
}
