package main

// Regression test for a nil dereference in the transform write-back.
//
// Jolt Replicate CFrame walks service.bodies and casts each entry's object to a
// Part without checking it. A body whose Part could not be rebuilt is left in the
// array with the object cleared, and the pass that removes those only runs
// inside a tree walk.
//
// A network ownership snapshot calls physics_refresh_part, which clears that
// slot, and a snapshot does not necessarily move the hierarchy. So the walk that
// would have cleaned it up can legitimately be skipped, leaving a nil object for
// the write-back to dereference. That is an access violation, and it needs a
// replication scenario to reach; a plain Part churn does not produce one.
//
// The test drives the same state directly rather than standing up a replicator:
// it clears a body slot the way physics_refresh_part does, without touching the
// hierarchy, and then steps. Before the fix that steps straight into the
// dereference.

import "core:fmt"

import engine_runtime "../src/engine/runtime"
import kineffi "../src/engine/bindings"
import services "../src/engine/services"
import vm "../src/engine/vm"

PART_COUNT :: 64

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("script failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

// The Parts are anchored, and that is the whole point of the setup.
//
// An unanchored Part is written back by the transform loop every frame, and
// writing one bumps the hierarchy epoch, which forces the next walk to run and
// therefore to purge the cleared slot. An anchored Part is skipped by that loop,
// so nothing bumps the epoch, the walk is legitimately skipped, and the cleared
// object survives all the way into the write-back. That is why this crash needs
// a static scene to reach, and why a test built from falling boxes misses it.
	run_script(&script_vm, fmt.tprintf(`
for i = 1, %d do
	local p = Instance.new("Part", workspace)
	p.Anchored = true
	p.Size = vector.create(4, 1, 4)
	p.CFrame = CFrame.new(i * 4, 0, 0)
end
`, PART_COUNT), "build")

	physics := cast(^services.Physics) services.Ensure_Service(&environment.services, "Physics")
	if physics == nil {
		panic("no physics service")
	}

	for _ in 0..<3 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	}

	if len(physics.bodies) != PART_COUNT {
		fmt.printfln("setup: %d bodies, expected %d", len(physics.bodies), PART_COUNT)
		panic("wrong body count")
	}

	// Reproduce the state physics_refresh_part leaves behind: a slot whose Part
	// could not be rebuilt, with the object cleared and the BodyID invalidated,
	// and no hierarchy change to make the next walk pick it up.
	// Must be assigned through the slice, not to a local copy: `victim :=
	// physics.bodies[0]` copies the struct and the mutation would be lost, which
	// makes this test pass without ever exercising the nil object.
	physics.bodies[0].object = nil
	physics.bodies[0].body_id = kineffi.JPH_BODY_ID_INVALID
	if physics.bodies[0].object != nil {
		panic("could not stage the invalidated body")
	}

	// The Parts are anchored, so the write-back does not skip the entry on
	// `anchored` and reaches the cast.
	for _ in 0..<4 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	}

	fmt.printfln("bodies after stepping over a cleared slot: %d", len(physics.bodies))
	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("PART_NIL_BODY_SMOKE_PASSED")
}