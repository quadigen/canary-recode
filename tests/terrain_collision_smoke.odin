// Terrain is a Service, not a Part, so the Part walk that gives every other
// object a Jolt body never saw it. The terrain was drawn as geometry and the
// solver knew nothing about it, so a body dropped on visible ground fell
// straight through it.
//
// A body per voxel does not scale, so the collision shape is one static mesh
// built from the exposed faces of the solid voxels. What matters here is that
// the mesh lands on the voxel grid, that faces buried between neighbouring
// voxels are left out, that liquids stay walkable-through, that clearing the map
// takes the floor away again, that the body is rebuilt when voxels change rather
// than on every step, and that the solver actually stops a body on it.
package main

import "core:fmt"
import "core:strings"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

STEP_SIZE :: f32(1.0 / 60.0)

// An uncollided body falls about 590 studs in the three seconds these tests step
// for, so a body that ends up near the slab proves the slab stopped it and a
// control body dropped on empty space proves the step loop really did run.
SETTLE_STEPS :: 180

// A 2x2x2 block of voxels has 24 exposed unit faces, two triangles per face, and
// both windings written for each so a body can arrive at a surface from either
// side. A collider that kept buried faces would produce 36 faces instead.
TRIANGLES_PER_FACE :: 2
WINDINGS_PER_FACE :: 2
CUBE_FACE_COUNT :: 24
CUBE_TRIANGLES :: CUBE_FACE_COUNT * TRIANGLES_PER_FACE * WINDINGS_PER_FACE

// TERRAIN_SCRIPT_PREAMBLE binds the service in every chunk. Each chunk is a
// separate compilation unit, so a `local` from one chunk is not visible in the
// next.
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
	for _ in 0..<times {
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

	// ------------------------------------------------------------------
	// One voxel slab. A stored cell is a whole voxel of side voxel_size, and
	// FillBlock selects cells by whether their centre falls inside the shape, so
	// a 4x4x4 block centred on the origin selects the cells at indices -1 and 0
	// on each axis: a 2x2x2 block of voxels spanning -4..4.
	// ------------------------------------------------------------------
	run_script(&script_vm, `
Terrain:Clear()
Terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(4, 4, 4), Enum.Material.Slate)
assert(Terrain:CountCells() == 8, "a 4x4x4 block fills the eight touching cell centres")
`, "terrain_collision_setup")

	check(len(terrain.voxels) == 8, "setup did not produce a voxel slab")

	step(&environment, &script_vm)
	check(physics.terrain_valid, "no terrain body was created for a non-empty map")
	check(
		physics.terrain_triangles == CUBE_TRIANGLES,
		"unexpected triangle count for a 2x2x2 voxel block",
	)

	// A wider slab is four voxels along one axis. Its interior faces must not
	// reach the mesh, so a 4x2x2 block has 2*(4*2 + 4*2 + 2*2) = 40 faces and not
	// the 48 that a collider treating every voxel as an isolated cube produces.
	run_script(&script_vm, `
Terrain:Clear()
Terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(12, 4, 4), Enum.Material.Slate)
`, "terrain_collision_interior_faces")

	check(len(terrain.voxels) == 16, "a 12x4x4 block should fill sixteen cell centres")
	step(&environment, &script_vm)
	check(
		physics.terrain_triangles == 40 * TRIANGLES_PER_FACE * WINDINGS_PER_FACE,
		"interior faces between neighbouring voxels reached the collision mesh",
	)

	// ------------------------------------------------------------------
	// The body is rebuilt when voxels change, not on every step.
	// ------------------------------------------------------------------
	version_before := physics.terrain_version
	step(&environment, &script_vm, 3)
	check(
		physics.terrain_version == version_before,
		"the terrain body was rebuilt on a step that changed nothing",
	)

	run_script(&script_vm, `
Terrain:FillBlock(CFrame.new(40, 0, 0), Vector3.new(8, 8, 8), Enum.Material.Slate)
`, "terrain_collision_extend")

	step(&environment, &script_vm)
	check(
		physics.terrain_version != version_before,
		"adding voxels did not mark the terrain body stale",
	)
	// The 4x2x2 slab is still there and the new block is a 2x2x2 well clear of
	// it, so the mesh is the sum of both: 40 faces plus 24.
	check(
		physics.terrain_triangles == (40+CUBE_FACE_COUNT)*TRIANGLES_PER_FACE*WINDINGS_PER_FACE,
		"a second isolated block did not add collision geometry",
	)

	// ------------------------------------------------------------------
	// Liquids are drawn as a surface rather than as rock, so they must not turn
	// into an invisible wall along every shoreline.
	// ------------------------------------------------------------------
	run_script(&script_vm, `
Terrain:Clear()
Terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(4, 4, 4), Enum.Material.Water)
`, "terrain_collision_water")

	step(&environment, &script_vm)
	check(
		!physics.terrain_valid,
		"a Water fill produced a collider, so water is now a solid wall",
	)

	// Neon is stored as solid occupancy, so it stays collidable. This is the
	// distinction that testing the material name rather than the occupancy
	// channel would get backwards.
	run_script(&script_vm, `
Terrain:Clear()
Terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(4, 4, 4), Enum.Material.Neon)
`, "terrain_collision_neon")

	step(&environment, &script_vm)
	check(physics.terrain_valid, "a Neon fill did not produce a collider")

	// ------------------------------------------------------------------
	// Clearing has to take the floor away. Keeping the old body would leave a
	// body standing on a world that no longer exists, which is the failure this
	// collider was added to prevent.
	// ------------------------------------------------------------------
	run_script(&script_vm, `Terrain:Clear()`, "terrain_collision_clear")

	step(&environment, &script_vm)
	check(!physics.terrain_valid, "clearing the map left the terrain body in place")

	// ------------------------------------------------------------------
	// The solver has to actually stop a body on the terrain, which is the case
	// the collider exists for. The control crate is dropped far away from any
	// voxel: it must keep falling, which proves the steps ran and the other
	// crate did not simply stop early on its own.
	// ------------------------------------------------------------------
	run_script(&script_vm, `
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
`, "terrain_collision_crate")

	step(&environment, &script_vm, SETTLE_STEPS)

	run_script(&script_vm, `
-- 20x4x20 selects six cells along x and z and two along y, so the voxel slab
-- spans -12..12 horizontally and tops out at y = 4. A 2x2x2 crate resting on it
-- has its centre at y = 5.
assert(crate.Position.Y > 4, "the crate sank into the terrain, ending at y=" .. tostring(crate.Position.Y))
assert(crate.Position.Y < 8, "the crate fell through the terrain, ending at y=" .. tostring(crate.Position.Y))

-- The control has nothing under it and must keep falling, which is what makes
-- the crate's resting place meaningful. It may have fallen out of the world and
-- been destroyed on the way, and that counts too: either way it did not stop.
local destroyed = not pcall(function() return control.Position.Y end)
local fell = destroyed
if not destroyed then
	fell = control.Position.Y < 0
end
assert(fell, "the control crate never fell, so the crate resting on terrain proves nothing")
`, "terrain_collision_crate_rest")

	fmt.println("TERRAIN_COLLISION_SMOKE_PASSED")
}
