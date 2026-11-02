package main

import "core:fmt"
import "core:strings"
import "core:time"

import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

TERRAIN_SCRIPT_PREAMBLE :: "local Terrain = game:GetService(\"Terrain\")\n"

run_script :: proc(script_vm: ^vm.VM, body, name: string) {
	source := strings.concatenate({TERRAIN_SCRIPT_PREAMBLE, body})
	defer delete(source)
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(name)
		fmt.eprintln(err)
		delete(err)
		panic("terrain collision bench failed")
	}
}


measure_rebuild :: proc(
	physics: ^services.Physics,
	terrain: ^services.Terrain,
) -> (
	total_ms: f64,
	worst_ms: f64,
) {
	total := time.Duration(0)
	worst := time.Duration(0)
	calls := 0
	for {
		start := time.now()
		services.Physics_Synchronize_Terrain(physics)
		d := time.since(start)
		total += d
		worst = max(worst, d)
		calls += 1
		if physics.terrain_version == terrain.geometry_version || calls > 100000 {
			break
		}
	}
	return f64(total) / f64(time.Millisecond), f64(worst) / f64(time.Millisecond)
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	physics := cast(^services.Physics)services.Ensure_Service(&environment.services, "Physics")
	terrain := cast(^services.Terrain)services.Ensure_Service(&environment.services, "Terrain")

	run_script(&script_vm, `Terrain.VoxelSize = 0.5`, "terrain_collision_bench_voxel")

	sizes := []int{16, 24, 32, 40, 48}
	for size in sizes {
		run_script(&script_vm, `Terrain:Clear()`, "terrain_collision_bench_clear")
		run_script(
			&script_vm,
			fmt.tprintf(
				`Terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(%d, %d, %d), Enum.Material.Slate)`,
				size,
				size,
				size,
			),
			"terrain_collision_bench_fill",
		)
		total, worst := measure_rebuild(physics, terrain)
		fmt.printf(
			"%-10s cells=%d total=%8.2f ms worst=%7.2f ms triangles=%d\n",
			fmt.tprintf("%d studs", size),
			services.Terrain_Cell_Count(terrain),
			total,
			worst,
			physics.terrain_triangles,
		)
	}


	run_script(&script_vm, `Terrain:Clear()`, "terrain_collision_bench_inc_clear")
	run_script(
		&script_vm,
		`Terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(48, 48, 48), Enum.Material.Slate)`,
		"terrain_collision_bench_inc_fill",
	)
	build_total, build_worst := measure_rebuild(physics, terrain)
	fmt.printf(
		"\n48-stud world build=%8.2f ms worst=%7.2f ms triangles=%d\n",
		build_total,
		build_worst,
		physics.terrain_triangles,
	)

	for i in 0 ..< 6 {
		y := 48 + i * 4
		run_script(
			&script_vm,
			fmt.tprintf(
				`Terrain:FillBlock(CFrame.new(0, %d, 0), Vector3.new(8, 8, 8), Enum.Material.Slate)`,
				y,
			),
			"terrain_collision_bench_inc_add",
		)
		add_ms, _ := measure_rebuild(physics, terrain)

		run_script(
			&script_vm,
			fmt.tprintf(
				`Terrain:FillBlock(CFrame.new(0, %d, 0), Vector3.new(8, 8, 8), Enum.Material.Air)`,
				y,
			),
			"terrain_collision_bench_inc_sub",
		)
		sub_ms, _ := measure_rebuild(physics, terrain)

		fmt.printf(
			"edit %d: add=%8.3f ms subtract=%8.3f ms triangles=%d\n",
			i,
			add_ms,
			sub_ms,
			physics.terrain_triangles,
		)
	}
}
