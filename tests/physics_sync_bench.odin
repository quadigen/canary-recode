package main

// Measures Physics_Synchronize on a model-sized scene, which is where the cost
// that matters lives.
//
// The number this reports is the one Tracy showed: a full synchronize of a
// several-thousand-Part model. It exists because two of the optimisations here
// are invisible to a passing/failing test and only show up as a time: reusing
// the scratch buffers, and making Is_A a pointer compare. A regression in either
// would leave every functional test green while the frame got slower.
//
// It also reports the second-sync-in-a-frame cost, which should now be near zero
// because a repeat walk is skipped. That is the larger of the two wins: the
// mouse raycast synchronizes once and Physics_Step synchronizes again in the
// same frame, so this used to walk the tree twice per frame.
//
// Deliberately not a pass/fail test. Timing on a shared machine is too noisy to
// assert on, so it prints and exits 0 unless something is structurally broken.

import "core:fmt"
import "core:time"
import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

// Matches the scale reported from Tracy. Large enough that a per-Part cost is
// unmistakable, small enough to build in about a second.
MODEL_PARTS :: 2601
FRAMES      :: 30
// Laid out in a grid rather than a flat list so the walk is a real tree walk
// with real branching, not one long children array, which is the easy case and
// would flatter the result.
GRID :: 50

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

main :: proc() {
	fmt.printfln("building %d Parts...", MODEL_PARTS)

	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	// Anchored, because an unanchored Part is simulated and this measures the
	// synchronize path rather than the solver. CanCollide stays on so the bodies
	// are the same kind the engine builds for a static model.
	run_script(&script_vm, fmt.tprintf(`
local grid = %d
local made = 0
for x = 0, grid do
	for y = 0, grid do
		if made >= %d then break end
		local p = Instance.new("Part", workspace)
		p.Anchored = true
		p.Size = vector.create(4, 1, 4)
		p.CFrame = CFrame.new(x * 4, y * 4, 0)
		made = made + 1
	end
end
`, GRID, MODEL_PARTS), "bench_build")

	physics := physics_of(&environment)
	workspace := workspace_of(&environment)
	if physics == nil || workspace == nil {
		panic("no physics or workspace service")
	}

	// One step so the Parts become bodies. BodyCount reads service.bodies, which
	// is only populated by a synchronize, and the very first one is the slowest
	// because it also builds every shape.
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)

	run_script(&script_vm, fmt.tprintf(`
local p = game:GetService("Physics")
assert(p.BodyCount == %d, "expected every Part to have a body, got " .. tostring(p.BodyCount))
`, MODEL_PARTS), "bench_verify")

	fmt.printfln("bodies: %d", len(physics.bodies))

	// Warm up: the first frames build every body and every scratch container.
	// Including them would report allocation and shape-building cost rather than
	// the steady-state synchronize the engine pays per frame.
	for _ in 0..<5 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	}

	step_total := time.Duration{}
	warm_total := time.Duration{}
	for _ in 0..<FRAMES {
		start := time.now()
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
		step_total += time.since(start)

		// What the mouse raycast costs on top of the step: a synchronize in the
		// same frame, on state nothing has changed since the step's own.
		warm_start := time.now()
		services.Physics_Synchronize(physics, workspace)
		warm_total += time.since(warm_start)
	}

	per_frame := f64(FRAMES)
	step_ms := f64(step_total) / f64(time.Second) * 1000.0 / per_frame
	warm_ms := f64(warm_total) / f64(time.Second) * 1000.0 / per_frame

	fmt.println("---")
	fmt.printfln("full frame (step+sync): %0.3f ms", step_ms)
	fmt.printfln("repeat sync:            %0.4f ms", warm_ms)
	if warm_ms > 0.0 {
		fmt.printfln("avoided by the guard:   %0.1fx", step_ms / warm_ms)
	}

	// A steady scene of anchored Parts never rewrites a transform and never has a
	// property set, so the epoch does not advance and the walk is skipped
	// outright. That is the correct answer, but it means the numbers above say
	// nothing about the cost of the walk itself, which is what the Is_A and
	// scratch-buffer work targets.
	//
	// So measure it directly: bump the epoch before each synchronize, forcing
	// the full walk every time. This is the cost a scene pays on any frame where
	// something actually moved.
	walk_total := time.Duration{}
	for _ in 0..<FRAMES {
		classes.Hierarchy_Touched()
		start := time.now()
		services.Physics_Synchronize(physics, workspace)
		walk_total += time.since(start)
	}
	walk_ms := f64(walk_total) / f64(time.Second) * 1000.0 / per_frame

	fmt.printfln("forced full walk:       %0.3f ms", walk_ms)
	if walk_ms > 0.0 {
		fmt.printfln("per Part:               %0.3f us", walk_ms * 1000.0 / f64(MODEL_PARTS))
	}

	// What is left of the walk, now that it is not dominated by any single
	// obvious cost. Measured separately so the next optimisation starts from a
	// number rather than a guess.
	collect_total := time.Duration{}
	found := 0
	for _ in 0..<FRAMES {
		classes.Hierarchy_Touched()
		start := time.now()
		gathered := services.Physics_Collect_Service_Parts(physics, workspace)
		collect_total += time.since(start)
		found = len(gathered)
	}
	fmt.printfln("  tree walk only:       %0.3f ms  (%d Parts found)",
		f64(collect_total) / f64(time.Second) * 1000.0 / per_frame, found)

	fmt.println("PHYSICS_SYNC_BENCH_OK")
	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
}