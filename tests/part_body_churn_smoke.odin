package main

// Regression test for body duplication caused by a stale part index.
//
// Every Part caches the slot it occupies in Physics::bodies, so a Part can find
// its body with a field read instead of a hash lookup. That cache goes stale the
// moment a body is removed from the middle of the array, because every later
// Part shifts down a slot.
//
// The bug this pins down is what the create pass did with a stale index. It
// asked only whether the index was in range, so an index pointing one past the
// end of a shortened array read as "this Part has no body" and the pass built a
// *second* body for it. The next walk dropped those and built them again, for as
// long as the scene existed.
//
// It is invisible to the engine's other tests. Nothing crashes: every Part has a
// body, raycasts hit, and bodies get created. What shows up is cost, and only
// when there are enough Parts for it to matter, so the assertion here is that
// creating and removing one Part does not rebuild the rest of the scene.
//
// The shape of the check matters: a Part is added *after* several others, so its
// removal shifts the Parts that follow it. Any Part placed after the removed one
// is the one that would have been duplicated.

import "core:fmt"
import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("script failed")
	}
}

physics_of :: proc(environment: ^engine_runtime.Environment) -> ^services.Physics {
	return cast(^services.Physics)services.Ensure_Service(&environment.services, "Physics")
}

workspace_of :: proc(environment: ^engine_runtime.Environment) -> ^classes.Object {
	return cast(^classes.Object)services.Ensure_Service(&environment.services, "Workspace")
}

PART_COUNT :: 200

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	// Anchored, so the solver is not the thing under test, and laid out so there
	// is a Part after every removable slot.
	run_script(&script_vm, fmt.tprintf(`
for i = 1, %d do
	local p = Instance.new("Part", workspace)
	p.Anchored = true
	p.Size = vector.create(4, 1, 4)
	p.CFrame = CFrame.new(i * 4, 0, 0)
end
`, PART_COUNT), "build")

	physics := physics_of(&environment)
	workspace := workspace_of(&environment)
	if physics == nil || workspace == nil {
		panic("no physics or workspace service")
	}

	for _ in 0..<3 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	}

	before := len(physics.bodies)
	if before != PART_COUNT {
		fmt.printfln("setup failed: %d bodies, expected %d", before, PART_COUNT)
		panic("wrong body count")
	}

	// Destroy a Part from the middle of the child list, so every Part after it
	// shifts down a slot: that is the condition that used to make the create pass
	// duplicate them. Chosen by position rather than by name so the test does not
	// depend on the Parts having distinct names.
	run_script(&script_vm, `
local children = workspace:GetChildren()
local index = math.floor(#children / 2)
children[index + 1]:Destroy()
`, "remove_one")

	for _ in 0..<3 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	}

	after := len(physics.bodies)

	// The removed Part's body goes, and only that one. Anything higher means the
	// walk duplicated bodies for Parts that already had them, which is the bug:
	// the duplicates are indistinguishable here, and would be dropped and rebuilt
	// again on the next walk, forever.
	fmt.printfln("bodies: %d -> %d", before, after)
	if after != before - 1 {
		fmt.printfln(
			"expected exactly one body to disappear; %d were created or destroyed",
			after - (before - 1),
		)
		panic("body churn after a single removal")
	}

	// Two more walks: if the walk is duplicating, the damage compounds here and
	// the count climbs again.
	for _ in 0..<4 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	}
	settled := len(physics.bodies)
	fmt.printfln("bodies after further walks: %d", settled)
	if settled != after {
		panic("body count is not stable across walks")
	}

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("PART_BODY_CHURN_SMOKE_PASSED")
}