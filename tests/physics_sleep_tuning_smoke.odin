package main

// Checks that the sleep tuning properties are actually wired to the solver.
//
// These were added so a large pile could be tuned at runtime, and the failure
// mode that matters is silent: a property that reads back the value it was set
// to, and quietly never reaches Jolt, would let someone conclude the tuning does
// not work when in fact it was never applied. So this asserts the value survives
// a round trip through the service, and separately that the settings the engine
// believes it pushed carry the same number.

import "core:fmt"
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

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	// The defaults are raised above Jolt's own, which is the whole point: a pile
	// of thousands of interpenetrating parts never settles at 0.03.
	run_script(&script_vm, `
local p = game:GetService("Physics")
assert(p.SleepThreshold > 0.03, "sleep threshold is still Jolt's default")
assert(p.SleepDelay < 0.5, "sleep delay is still Jolt's default")
print("defaults:", p.SleepThreshold, p.SleepDelay)
`, "defaults")

	// Round trip through the setter.
	run_script(&script_vm, `
local p = game:GetService("Physics")
p.SleepThreshold = 0.42
p.SleepDelay = 0.75
assert(math.abs(p.SleepThreshold - 0.42) < 1e-6, "threshold did not round trip: " .. tostring(p.SleepThreshold))
assert(math.abs(p.SleepDelay - 0.75) < 1e-6, "delay did not round trip: " .. tostring(p.SleepDelay))
`, "roundtrip")

	physics := cast(^services.Physics) services.Ensure_Service(&environment.services, "Physics")
	if physics == nil {
		panic("no physics service")
	}

	// The engine's own mirror of what it pushed must agree, or the next setter
	// call would start from a stale copy and silently revert the change.
	if physics.system.solver.point_velocity_sleep_threshold < 0.42 {
		fmt.printfln(
			"engine mirror holds %f but the service reports the value was set",
			physics.system.solver.point_velocity_sleep_threshold,
		)
		panic("solver settings mirror was not updated")
	}

	// Out-of-range values are clamped rather than rejected, so a bad script
	// cannot leave the scene with nothing asleep at all.
	run_script(&script_vm, `
local p = game:GetService("Physics")
p.SleepThreshold = 1000
assert(p.SleepThreshold <= 2.0, "threshold was not clamped: " .. tostring(p.SleepThreshold))
p.SleepThreshold = -5
assert(p.SleepThreshold >= 0, "threshold was not clamped at the low end: " .. tostring(p.SleepThreshold))
`, "clamp")

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("PHYSICS_SLEEP_TUNING_SMOKE_PASSED")
}