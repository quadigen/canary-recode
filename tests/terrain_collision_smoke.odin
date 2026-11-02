


package main

import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:strings"

STEP_SIZE :: f32(1.0 / 60.0)


SETTLE_STEPS :: 180


TERRAIN_SCRIPT_PREAMBLE :: "local Terrain = game:GetService(\"Terrain\")\n"

run_script :: proc(script_vm: ^vm.VM, body, name: string) {
	source := strings.concatenate({TERRAIN_SCRIPT_PREAMBLE, body})
	defer delete(source)

	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(name)
		fmt.eprintln(err)
		delete(err)
		panic("terrain collision smoke test failed")
	}
}

check :: proc(ok: bool, message: string) {
	if !ok {
		fmt.eprintln(message)
		panic("terrain collision smoke test failed")
	}
}

terrain_of :: proc(environment: ^engine_runtime.Environment) -> ^services.Terrain {
	return cast(^services.Terrain)services.Ensure_Service(&environment.services, "Terrain")
}

physics_of :: proc(environment: ^engine_runtime.Environment) -> ^services.Physics {
	return cast(^services.Physics)services.Ensure_Service(&environment.services, "Physics")
}

step :: proc(environment: ^engine_runtime.Environment, script_vm: ^vm.VM, times := 1) {
	for _ in 0 ..< times {
		engine_runtime.Environment_Update_Step(environment, script_vm, STEP_SIZE)
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	terrain := terrain_of(&environment)
	physics := physics_of(&environment)
	check(physics.initialized, "the Physics service did not initialise")


	run_script(
		&script_vm,
		`
Terrain:Clear()
Terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(4, 4, 4), Enum.Material.Slate)
assert(Terrain:CountCells() == 8, "a 4x4x4 block fills the eight touching cell centres")
`,
		"terrain_collision_setup",
	)

	check(services.Terrain_Cell_Count(terrain) == 8, "setup did not produce a voxel slab")

	step(&environment, &script_vm)
	check(physics.terrain_valid, "no terrain body was created for a non-empty map")
	check(physics.terrain_triangles > 0, "the sampled slab produced no collision geometry")


	run_script(
		&script_vm,
		`
Terrain:Clear()
Terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(12, 4, 4), Enum.Material.Slate)
`,
		"terrain_collision_interior_faces",
	)

	check(
		services.Terrain_Cell_Count(terrain) == 16,
		"a 12x4x4 block should fill sixteen cell centres",
	)
	step(&environment, &script_vm)
	check(physics.terrain_triangles > 0, "a wider slab produced no collision geometry")


	version_before := physics.terrain_version
	step(&environment, &script_vm, 3)
	check(
		physics.terrain_version == version_before,
		"the terrain body was rebuilt on a step that changed nothing",
	)

	run_script(
		&script_vm,
		`
Terrain:FillBlock(CFrame.new(40, 0, 0), Vector3.new(8, 8, 8), Enum.Material.Slate)
`,
		"terrain_collision_extend",
	)

	step(&environment, &script_vm)
	check(
		physics.terrain_version != version_before,
		"adding voxels did not mark the terrain body stale",
	)

	check(physics.terrain_triangles > 0, "a second isolated block did not add collision geometry")


	run_script(
		&script_vm,
		`
Terrain:Clear()
Terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(4, 4, 4), Enum.Material.Water)
`,
		"terrain_collision_water",
	)

	step(&environment, &script_vm)
	check(!physics.terrain_valid, "a Water fill produced a collider, so water is now a solid wall")


	run_script(
		&script_vm,
		`
Terrain:Clear()
Terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(4, 4, 4), Enum.Material.Neon)
`,
		"terrain_collision_neon",
	)

	step(&environment, &script_vm)
	check(physics.terrain_valid, "a Neon fill did not produce a collider")


	run_script(&script_vm, `Terrain:Clear()`, "terrain_collision_clear")

	step(&environment, &script_vm)
	check(!physics.terrain_valid, "clearing the map left the terrain body in place")


	run_script(
		&script_vm,
		`
Terrain:Clear()
Terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(20, 4, 20), Enum.Material.Slate)

crate = Instance.new("Part", workspace)
crate.Name = "Crate"
crate.Anchored = false
crate.Size = Vector3.new(2, 2, 2)
crate.Position = Vector3.new(0, 40, 0)

control = Instance.new("Part", workspace)
control.Name = "Control"
control.Anchored = false
control.Size = Vector3.new(2, 2, 2)
control.Position = Vector3.new(400, 40, 0)
`,
		"terrain_collision_crate",
	)

	step(&environment, &script_vm, SETTLE_STEPS)

	run_script(
		&script_vm,
		`
-- The smooth slab surface is y = 2; a 2x2x2 crate rests at y = 3.
assert(crate.Position.Y > 2, "the crate sank into the terrain, ending at y=" .. tostring(crate.Position.Y))
assert(crate.Position.Y < 5, "the crate fell through the terrain, ending at y=" .. tostring(crate.Position.Y))

-- The control has nothing under it and must keep falling, which is what makes
-- the crate's resting place meaningful. It may have fallen out of the world and
-- been destroyed on the way, and that counts too: either way it did not stop.
local destroyed = not pcall(function() return control.Position.Y end)
local fell = destroyed
if not destroyed then
	fell = control.Position.Y < 0
end
assert(fell, "the control crate never fell, so the crate resting on terrain proves nothing")
`,
		"terrain_collision_crate_rest",
	)

	fmt.println("TERRAIN_COLLISION_SMOKE_PASSED")
}
