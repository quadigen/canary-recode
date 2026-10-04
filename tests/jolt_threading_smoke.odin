package main

import "core:fmt"
import "core:time"
import kineffi "../src/engine/bindings"
import physics "../src/engine/physics"

FLOOR_HALF  :: kineffi.JPH_Vec3{40, 1, 40}
BOX_HALF    :: kineffi.JPH_Vec3{0.5, 0.5, 0.5}
GRID        :: 14
BOX_COUNT   :: GRID * GRID * 6
STEP_COUNT  :: 90

// Threads the engine would spawn on this machine. Zero means there is nothing to
// prove and the test reports a skip instead of a pass.
auto_threads :: proc() -> u32 {
	cores := kineffi.JPH_Get_Num_Cores()
	return cores < 2 ? 0 : physics.default_job_system_threads()
}

// Rejects NaN and anything that has run away, matching the engine's own idea of
// a finite coordinate (see physics_finite_f32 in PhysicsBodies.odin).
finite_f64 :: proc(value: f64) -> bool {
	return value == value && value > -1.0e20 && value < 1.0e20
}

// ids[0] is the floor, ids[1 .. BOX_COUNT] are the pile.
build_scene :: proc(system: ^physics.System, ids: ^[BOX_COUNT + 1]kineffi.JPH_BodyID) {
	floor_rotation := kineffi.JPH_Quat{0, 0, 0, 1}
	floor_position := kineffi.JPH_RVec3{0, -1, 0}
	floor_half := FLOOR_HALF
	floor_shape := kineffi.JPH_BoxShape_Create(&floor_half, 0.05)
	floor_settings := kineffi.JPH_BodyCreationSettings_Create3(
		floor_shape,
		&floor_position,
		&floor_rotation,
		.Static,
		physics.OBJECT_LAYER_NON_MOVING,
	)
	floor := kineffi.JPH_BodyInterface_CreateBody(system.body_interface, floor_settings)
	kineffi.JPH_BodyCreationSettings_Destroy(floor_settings)
	ids[0] = kineffi.JPH_Body_GetID(floor)
	kineffi.JPH_BodyInterface_AddBody(system.body_interface, ids[0], .DontActivate)

	box_half := BOX_HALF
	box_shape := kineffi.JPH_BoxShape_Create(&box_half, 0.05)

	// Boxes exactly touching, so the whole pile collapses into one island. A
	// pile of separate boxes would give one island per box and the pool would
	// have nothing to parallelise.
	for layer in 0..<6 {
		for row in 0..<GRID {
			for column in 0..<GRID {
				i := layer * GRID * GRID + row * GRID + column
				position := kineffi.JPH_RVec3 {
					f64(column) - f64(GRID) / 2,
					2.0 + f64(layer) * 1.0,
					f64(row) - f64(GRID) / 2,
				}
				rotation := kineffi.JPH_Quat{0, 0, 0, 1}
				settings := kineffi.JPH_BodyCreationSettings_Create3(
					box_shape,
					&position,
					&rotation,
					.Dynamic,
					physics.OBJECT_LAYER_MOVING,
				)
				body := kineffi.JPH_BodyInterface_CreateBody(system.body_interface, settings)
				kineffi.JPH_BodyCreationSettings_Destroy(settings)
				ids[i + 1] = kineffi.JPH_Body_GetID(body)
				kineffi.JPH_BodyInterface_AddBody(system.body_interface, ids[i + 1], .Activate)
			}
		}
	}

	kineffi.JPH_Shape_Destroy(floor_shape)
	kineffi.JPH_Shape_Destroy(box_shape)
	kineffi.JPH_PhysicsSystem_OptimizeBroadPhase(system.handle)
}

tear_down_scene :: proc(system: ^physics.System, ids: ^[BOX_COUNT + 1]kineffi.JPH_BodyID) {
	for i in 0..=BOX_COUNT {
		if ids[i] != kineffi.JPH_BODY_ID_INVALID {
			kineffi.JPH_BodyInterface_RemoveAndDestroyBody(system.body_interface, ids[i])
		}
	}
}

run_pile :: proc(num_threads: u32, observe: bool) -> (resting_y: f64, ms: f64) {
	settings := physics.DEFAULT_SYSTEM_SETTINGS
	settings.num_threads = num_threads
	settings.observe_threads = observe

	system, ok := physics.System_Create_3D(settings)
	assert(ok)
	defer physics.System_Destroy_3D(&system)

	assert(system.job_system != nil)
	assert(
		u32(physics.System_Num_Threads(&system)) == max(num_threads, 1),
		"reported thread count disagrees with the requested one",
	)

	ids: [BOX_COUNT + 1]kineffi.JPH_BodyID
	build_scene(&system, &ids)

	start := time.now()
	for _ in 0..<STEP_COUNT {
		physics.System_Step(&system, 1.0 / 60.0, 1)
	}
	ms = time.duration_seconds(time.since(start)) * 1000

	resting_y = 1.0e30
	for i in 0..<BOX_COUNT {
		position: kineffi.JPH_RVec3
		kineffi.JPH_BodyInterface_GetPosition(system.body_interface, ids[i + 1], &position)
		assert(finite_f64(position.x) && finite_f64(position.y) && finite_f64(position.z))
		assert(abs(position.x) < 200 && abs(position.z) < 200)
		resting_y = min(resting_y, position.y)
	}

	observed := physics.System_Observed_Threads(&system)
	if observe {
		fmt.printfln(
			"pool reports %d live threads (allows %d)",
			observed,
			physics.System_Num_Threads(&system),
		)
		if num_threads == 1 {
			assert(
				observed == 1,
				"a single-threaded job system reported extra threads",
			)
		} else {
			assert(
				observed >= 2,
				"no worker thread ever started, so the pool is not actually running",
			)
		}
	}

	tear_down_scene(&system, &ids)
	return
}

main :: proc() {
	cores := kineffi.JPH_Get_Num_Cores()
	fmt.printfln("cores reported by jolt: %d", cores)
	fmt.printfln("default job system threads: %d", physics.default_job_system_threads())

	threads := auto_threads()
	if threads == 0 {
		fmt.println("JOLT_THREADING_SMOKE_SKIPPED_SINGLE_CORE")
		return
	}
	assert(threads >= 2)

	// Same scene, forced onto one thread, purely for the timing comparison.
	// Observation is left on deliberately: a single-threaded job system must
	// report exactly one thread, which is what makes the threaded assertion
	// above mean something rather than passing by accident.
	single_y, single_ms := run_pile(1, true)
	fmt.printfln("single threaded: %0.2f ms for %d steps", single_ms, STEP_COUNT)

	multi_y, multi_ms := run_pile(threads, true)
	fmt.printfln("%d threaded:  %0.2f ms for %d steps", threads, multi_ms, STEP_COUNT)

	// Both runs have to be sane before they are compared. A box resting on the
	// floor sits at y = 0 (floor top at -0.5, box half extent 0.5), and the
	// pile is six layers tall so it has to stay well below its drop height.
	assert(single_y > -0.2 && single_y < 2.0)
	assert(multi_y > -0.2 && multi_y < 2.0)
	fmt.printfln("lowest box centre: single %0.4f, multi %0.4f", single_y, multi_y)

	// Reported, not asserted. Timing on a shared machine is too noisy to fail a
	// build over, and a regression that made threading slower would show up here
	// long before it showed up as a failure.
	fmt.printfln("speedup: %0.2fx", single_ms / max(multi_ms, 0.0001))

	fmt.println("JOLT_THREADING_SMOKE_PASSED")
}