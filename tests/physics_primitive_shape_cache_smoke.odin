package main

import ffi "../src/engine/bindings"
import classes "../src/engine/classes"
import runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.Run(v, source, "primitive_shape_cache")
	assert(ok, err)
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
group = Instance.new("Folder", workspace)
a = Instance.new("Part", group)
a.Name = "a"; a.Size = Vector3.new(4, 4, 4); a.Anchored = false; a.Gravity = Vector3.zero
b = Instance.new("Part", group)
b.Name = "b"; b.Size = a.Size; b.Position = Vector3.new(20, 0, 0)
b.Anchored = false; b.Gravity = Vector3.zero; b.Material = Enum.Material.Metal
c = Instance.new("Part", group)
c.Name = "c"; c.Size = Vector3.new(5, 4, 4); c.Position = Vector3.new(40, 0, 0)
`,
	)
	services.Physics_Synchronize(physics, workspace)
	group := classes.Find_First_Child(workspace, "Folder")
	assert(group != nil)
	a := cast(^classes.Part)classes.Find_First_Child(group, "a")
	b := cast(^classes.Part)classes.Find_First_Child(group, "b")
	c := cast(^classes.Part)classes.Find_First_Child(group, "c")
	assert(a != nil && b != nil && c != nil)
	shape_of :: proc(physics: ^services.Physics, part: ^classes.Part) -> ffi.JPH_ShapeRef {
		assert(part.part_index >= 0)
		return ffi.JPH_BodyInterface_GetShape(
			physics.system.body_interface,
			physics.body_ids[part.part_index],
		)
	}
	shared := shape_of(physics, a)
	assert(shared != nil && shared == shape_of(physics, b))
	assert(shared != shape_of(physics, c))
	run(
		&v,
		`assert(b:GetMass() > a:GetMass(), "shared geometry must preserve independent material mass")`,
	)
	run(
		&v,
		`
for i=1,400 do
	local p = Instance.new("Part", group)
	p.Size = Vector3.new(i + 5, 3, 2)
	p.Position = Vector3.new(i * 500, 100, 0)
end
`,
	)
	services.Physics_Synchronize(physics, workspace)
	assert(len(physics.primitive_shape_cache) == services.PHYSICS_PRIMITIVE_CACHE_CAPACITY)
	assert(shape_of(physics, a) == shared && shape_of(physics, b) == shared)
	run(&v, `a.Size = Vector3.new(7, 4, 4)`)
	services.Physics_Synchronize(physics, workspace)
	assert(shape_of(physics, a) != shared)
	assert(shape_of(physics, b) == shared)
	run(&v, `group:Destroy()`)
	runtime.Environment_Update_Step(&env, &v, 1.0 / 60)
	assert(len(physics.bodies) == 0)
	fmt.println("PHYSICS_PRIMITIVE_SHAPE_CACHE_SMOKE_PASSED")
}
