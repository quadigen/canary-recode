// AssemblyLinearVelocity, AssemblyAngularVelocity and ApplyImpulse are the Part
// members scripts use to throw things around. They were missing entirely, so the
// obvious spellings -- a shove, a fling, reading a body's speed -- all silently
// did nothing.
//
// Reaching a Part's Jolt body is awkward by construction: services imports
// classes, so classes cannot import services and Part has no route to the body
// standing in for it. These members therefore run through a hook the services
// layer installs. What matters is that a body-backed Part reports and accepts
// solver velocity, and that a Part with no body of its own reports zero rather
// than a number the solver never produced.
package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(name)
		fmt.eprintln(err)
		delete(err)
		panic("part velocity smoke test failed")
	}
}

step :: proc(environment: ^engine_runtime.Environment, script_vm: ^vm.VM) {
	engine_runtime.Environment_Update_Step(environment, script_vm, 1.0 / 60.0)
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	// Bodies are created during the physics step rather than when a Part is
	// parented, so the scene is stepped once before any of these members has a body
	// to talk to.
	run_script(&script_vm, `
at_rest = function(v)
    return math.abs(v.X) < 0.001 and math.abs(v.Y) < 0.001 and math.abs(v.Z) < 0.001
end

platform = Instance.new("Part", workspace)
platform.Name = "Platform"
platform.Anchored = true
platform.Size = vector.create(60, 1, 60)
platform.Position = vector.create(0, 0, 0)

box = Instance.new("Part", workspace)
box.Name = "Box"
box.Anchored = false
box.Size = vector.create(2, 2, 2)
box.Position = vector.create(0, 10, 0)

mesh = Instance.new("MeshPart", workspace)
mesh.Name = "Rock"
mesh.Anchored = true
mesh.Size = vector.create(2, 2, 2)
mesh.Position = vector.create(10, 10, 0)
`, "part_velocity_setup")
	step(&environment, &script_vm)

	run_script(&script_vm, `
-- An anchored Part has no solver body, so it reports zero and drops writes.
assert(at_rest(platform.AssemblyLinearVelocity), "anchored linear velocity was not zero")
platform.AssemblyLinearVelocity = Vector3.new(5, 0, 0)
assert(at_rest(platform.AssemblyLinearVelocity), "anchored Part accepted a linear velocity")
platform.AssemblyAngularVelocity = Vector3.new(0, 5, 0)
assert(at_rest(platform.AssemblyAngularVelocity), "anchored Part accepted an angular velocity")

-- A body-backed Part reports and accepts solver velocity.
box.AssemblyLinearVelocity = Vector3.new(0, 0, 10)
local linear = box.AssemblyLinearVelocity
assert(math.abs(linear.X) < 0.001, "linear X was " .. linear.X)
assert(math.abs(linear.Y) < 0.001, "linear Y was " .. linear.Y)
assert(math.abs(linear.Z - 10) < 0.001, "linear Z was " .. linear.Z)

box.AssemblyAngularVelocity = Vector3.new(0, 3, 0)
local angular = box.AssemblyAngularVelocity
assert(math.abs(angular.Y - 3) < 0.001, "angular Y was " .. angular.Y)

-- Settle both back to rest so the impulse below is measured on its own.
box.AssemblyLinearVelocity = Vector3.zero
box.AssemblyAngularVelocity = Vector3.zero
assert(at_rest(box.AssemblyLinearVelocity), "linear velocity did not settle")

-- ApplyImpulse changes the body's velocity.
box:ApplyImpulse(Vector3.new(0, 0, 200))
local shoved = box.AssemblyLinearVelocity
assert(shoved.Z > 0.01, "ApplyImpulse did not change velocity, Z was " .. shoved.Z)

-- Roblox's second argument is a world-space position, the thing that lets a
-- launch spin a Part. The Jolt wrapper only exposes centre-of-mass impulses, so it
-- is accepted and ignored -- but the call must not error.
box.AssemblyLinearVelocity = Vector3.zero
box:ApplyImpulse(Vector3.new(0, 0, 200), box.Position + Vector3.new(0, 1, 0))
assert(box.AssemblyLinearVelocity.Z > 0.01, "two-argument ApplyImpulse did nothing")

-- MeshPart is a Part, so it carries the same members.
assert(at_rest(mesh.AssemblyLinearVelocity), "MeshPart linear velocity was not zero")
mesh.AssemblyLinearVelocity = Vector3.new(1, 1, 1)
assert(at_rest(mesh.AssemblyLinearVelocity), "anchored MeshPart accepted a velocity")
mesh:ApplyImpulse(Vector3.new(0, 10, 0))
`, "part_velocity_members")
	step(&environment, &script_vm)

	// A written velocity has to actually drive the body, not merely read back.
	// Launched clear of the platform so nothing it can collide with perturbs the
	// result.
	run_script(&script_vm, `
box.AssemblyLinearVelocity = Vector3.zero
box.AssemblyAngularVelocity = Vector3.zero
box.Position = vector.create(0, 200, 0)
box.AssemblyLinearVelocity = Vector3.new(0, 0, 40)
launch_z = box.CFrame.Z
`, "part_velocity_launch")
	step(&environment, &script_vm)
	run_script(&script_vm, `
assert(box.CFrame.Z > launch_z + 0.5, "velocity was not integrated by the solver")
assert(box.AssemblyLinearVelocity.Z > 30, "velocity did not survive the step")
`, "part_velocity_after_step")

	// Position and CFrame are one placement held in two fields, and everything
	// else in the engine keeps them in step. The solver's read-back used to update
	// only CFrame, which left Position reporting where a moving Part used to be --
	// and made a scripted impulse look like it had done nothing.
	run_script(&script_vm, `
free = Instance.new("Part", workspace)
free.Name = "Free"
free.Anchored = false
free.Size = vector.create(1, 1, 1)
free.Position = vector.create(0, 300, 0)
`, "part_velocity_free_setup")
	step(&environment, &script_vm)
	run_script(&script_vm, `
assert(free.CFrame.Y < 300, "gravity did not move the free Part")
assert(
    math.abs(free.Position.Y - free.CFrame.Y) < 0.001,
    "Position and CFrame disagree after a step: " .. free.Position.Y .. " vs " .. free.CFrame.Y
)
`, "part_velocity_position_sync")

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("PART_VELOCITY_SMOKE_PASSED")
}