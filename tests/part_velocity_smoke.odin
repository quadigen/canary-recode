


package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

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


	run_script(
		&script_vm,
		`
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
`,
		"part_velocity_setup",
	)
	step(&environment, &script_vm)

	run_script(
		&script_vm,
		`
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

box.AssemblyLinearVelocity = Vector3.zero
box.AssemblyAngularVelocity = Vector3.zero
box:ApplyAngularImpulse(Vector3.new(0, 1, 0))
assert(math.abs(box.AssemblyAngularVelocity.Y) > 0.0001)
box.AssemblyAngularVelocity = Vector3.zero
box:ApplyImpulseAtPosition(Vector3.new(0, 0, 200), box.Position + Vector3.new(0, 1, 0))
assert(box.AssemblyLinearVelocity.Z > 0.001)
assert(math.abs(box.AssemblyAngularVelocity.X) > 0.0001)
assert(box:GetMass() > 0 and box.Mass == box:GetMass())
-- MeshPart is a Part, so it carries the same members.
assert(at_rest(mesh.AssemblyLinearVelocity), "MeshPart linear velocity was not zero")
mesh.AssemblyLinearVelocity = Vector3.new(1, 1, 1)
assert(at_rest(mesh.AssemblyLinearVelocity), "anchored MeshPart accepted a velocity")
mesh:ApplyImpulse(Vector3.new(0, 10, 0))
`,
		"part_velocity_members",
	)
	step(&environment, &script_vm)


	run_script(
		&script_vm,
		`
box.AssemblyLinearVelocity = Vector3.zero
box.AssemblyAngularVelocity = Vector3.zero
box.Position = vector.create(0, 200, 0)
box.AssemblyLinearVelocity = Vector3.new(0, 0, 40)
launch_z = box.CFrame.Z
`,
		"part_velocity_launch",
	)
	step(&environment, &script_vm)
	run_script(
		&script_vm,
		`
assert(box.CFrame.Z > launch_z + 0.5, "velocity was not integrated by the solver")
assert(box.AssemblyLinearVelocity.Z > 30, "velocity did not survive the step")
`,
		"part_velocity_after_step",
	)


	run_script(
		&script_vm,
		`
free = Instance.new("Part", workspace)
free.Name = "Free"
free.Anchored = false
free.Size = vector.create(1, 1, 1)
free.Position = vector.create(0, 300, 0)
`,
		"part_velocity_free_setup",
	)
	step(&environment, &script_vm)
	run_script(
		&script_vm,
		`
assert(free.CFrame.Y < 300, "gravity did not move the free Part")
assert(
    math.abs(free.Position.Y - free.CFrame.Y) < 0.001,
    "Position and CFrame disagree after a step: " .. free.Position.Y .. " vs " .. free.CFrame.Y
)
`,
		"part_velocity_position_sync",
	)

	run_script(
		&script_vm,
		`
wood = Instance.new("Part", workspace)
wood.Anchored = false
wood.Size = Vector3.one
wood.Position = Vector3.new(-10, 100, 0)
wood.Material = Enum.Material.Wood
metal = Instance.new("Part", workspace)
metal.Anchored = false
metal.Size = Vector3.one
metal.Position = Vector3.new(10, 100, 0)
metal.Material = Enum.Material.Metal
`,
		"material_mass_setup",
	)
	step(&environment, &script_vm)
	run_script(
		&script_vm,
		`
local impulse = Vector3.new(1, 0, 0)
wood:ApplyImpulse(impulse)
metal:ApplyImpulse(impulse)
assert(math.abs(wood.AssemblyLinearVelocity.X - 1 / 0.35) < 0.001)
assert(math.abs(metal.AssemblyLinearVelocity.X - 1 / 7.85) < 0.001)

wood.Material = Enum.Material.Metal
wood:ApplyImpulse(impulse)
assert(math.abs(wood.AssemblyLinearVelocity.X - (1 / 0.35 + 1 / 7.85)) < 0.001,
    "a material change should update mass while preserving velocity")
metal.Material = Enum.Material.Wood
`,
		"material_mass_and_immediate_change",
	)
	step(&environment, &script_vm)
	run_script(
		&script_vm,
		`
metal.AssemblyLinearVelocity = Vector3.zero
metal:ApplyImpulse(Vector3.new(1, 0, 0))
assert(math.abs(metal.AssemblyLinearVelocity.X - 1 / 0.35) < 0.001)
`,
		"material_mass_after_sync",
	)

	run_script(
		&script_vm,
		`
local floor = Instance.new("Part", workspace)
floor.Anchored = true
floor.Size = Vector3.new(10, 2, 10)
floor.Position = Vector3.new(100, 0, 0)
floor.Material = Enum.Material.Concrete
bouncer = Instance.new("Part", workspace)
bouncer.Anchored = false
bouncer.Gravity = Vector3.zero
bouncer.Size = Vector3.one
bouncer.Position = Vector3.new(100, 2, 0)
bouncer.Material = Enum.Material.Rubber
`,
		"material_bounce_setup",
	)
	step(&environment, &script_vm)
	run_script(
		&script_vm,
		`bouncer.AssemblyLinearVelocity = Vector3.new(0, -20, 0)`,
		"material_bounce_drop",
	)
	for _ in 0 ..< 4 {step(&environment, &script_vm)}
	run_script(
		&script_vm,
		`
local rebound = bouncer.AssemblyLinearVelocity.Y
-- Rubber has elasticity 0.95 with weight 2, and concrete has 0.2 with weight 1.
assert(math.abs(rebound - 14) < 0.3, "expected weighted bounce speed near 14, got " .. rebound)
`,
		"material_bounce_weight",
	)

	run_script(
		&script_vm,
		`
bouncer.Gravity = Vector3.new(0, -196.2, 0)
game:GetService("Physics").SleepThreshold = 0.2
slope = Instance.new("Part", workspace)
slope.Size = Vector3.new(40, 2, 12)
slope.CFrame = CFrame.new(0, 40, 120) * CFrame.Angles(0, 0, math.rad(12))
slope.Material = Enum.Material.Sand
slider = Instance.new("Part", workspace)
slider.Anchored = false
slider.Size = Vector3.new(2, 2, 2)
slider.CFrame = slope.CFrame * CFrame.new(0, 2, 0)
slider.Material = Enum.Material.Wood
slider_start = slider.Position.X
`,
		"material_friction_setup",
	)
	for _ in 0 ..< 120 {step(&environment, &script_vm)}
	run_script(
		&script_vm,
		`
assert(math.abs(slider.Position.X - slider_start) < 0.3, "sand should hold the box in place")
slope.Material = Enum.Material.Ice
`,
		"material_ice_change",
	)
	for _ in 0 ..< 60 {step(&environment, &script_vm)}
	run_script(
		&script_vm,
		`
local displacement = slider.Position.X - slider_start
assert(displacement < -2, "ice should let the box slide downhill, X displacement: " .. displacement)
`,
		"material_friction_after_sync",
	)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("PART_VELOCITY_SMOKE_PASSED")
}
