package main


import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:time"


MODEL_PARTS :: 2601
FRAMES :: 30


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


	run_script(
		&script_vm,
		fmt.tprintf(
			`
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
`,
			GRID,
			MODEL_PARTS,
		),
		"bench_build",
	)

	physics := physics_of(&environment)
	workspace := workspace_of(&environment)
	if physics == nil || workspace == nil {
		panic("no physics or workspace service")
	}


	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)

	run_script(
		&script_vm,
		fmt.tprintf(
			`
local p = game:GetService("Physics")
assert(p.BodyCount == %d, "expected every Part to have a body, got " .. tostring(p.BodyCount))
`,
			MODEL_PARTS,
		),
		"bench_verify",
	)

	fmt.printfln("bodies: %d", len(physics.bodies))


	for _ in 0 ..< 5 {
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	}

	step_total := time.Duration{}
	warm_total := time.Duration{}
	for _ in 0 ..< FRAMES {
		start := time.now()
		engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
		step_total += time.since(start)


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


	walk_total := time.Duration{}
	for _ in 0 ..< FRAMES {
		classes.Hierarchy_Touched()
		start := time.now()
		services.Physics_Synchronize(physics, workspace)
		walk_total += time.since(start)
	}
	walk_ms := f64(walk_total) / f64(time.Second) * 1000.0 / per_frame

	fmt.printfln("property-only sync:       %0.3f ms", walk_ms)
	if walk_ms > 0.0 {
		fmt.printfln("per Part:               %0.3f us", walk_ms * 1000.0 / f64(MODEL_PARTS))
	}
	structure_total := time.Duration{}
	for _ in 0 ..< FRAMES {
		classes.Hierarchy_Touched()
		classes.Hierarchy_Structure_Touched()
		start := time.now()
		services.Physics_Synchronize(physics, workspace)
		structure_total += time.since(start)
	}
	fmt.printfln(
		"structural sync:       %0.3f ms",
		f64(structure_total) / f64(time.Second) * 1000.0 / per_frame,
	)


	collect_total := time.Duration{}
	found := 0
	for _ in 0 ..< FRAMES {
		classes.Hierarchy_Touched()
		start := time.now()
		gathered := services.Physics_Collect_Service_Parts(physics, workspace)
		collect_total += time.since(start)
		found = len(gathered)
	}
	fmt.printfln(
		"  tree walk only:       %0.3f ms  (%d Parts found)",
		f64(collect_total) / f64(time.Second) * 1000.0 / per_frame,
		found,
	)

	fmt.println("PHYSICS_SYNC_BENCH_OK")
	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
}
