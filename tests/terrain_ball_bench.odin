


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
		panic("terrain ball bench failed")
	}
}

ms :: proc(d: time.Duration) -> f64 {
	return f64(d) / f64(time.Millisecond)
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)
	defer {
		vm.Close(&script_vm)
		engine_runtime.Environment_Destroy(&environment)
	}

	physics := cast(^services.Physics)services.Ensure_Service(&environment.services, "Physics")

	run_script(&script_vm, `Terrain.VoxelSize = 0.5`, "terrain_ball_voxel")
	run_script(&script_vm, `Terrain:Clear()`, "terrain_ball_clear")

	fill_start := time.now()
	run_script(
		&script_vm,
		`Terrain:FillBall(Vector3.new(0, 0, 0), 15, Enum.Material.Slate)`,
		"terrain_ball_fill",
	)
	fill_ms := ms(time.since(fill_start))

	terrain := cast(^services.Terrain)services.Ensure_Service(&environment.services, "Terrain")
	chunks := len(terrain.chunks)


	drain_total := time.Duration(0)
	drain_max := time.Duration(0)
	drain_calls := 0
	for {
		start := time.now()
		services.Physics_Synchronize_Terrain(physics)
		d := time.since(start)
		drain_total += d
		drain_max = max(drain_max, d)
		drain_calls += 1
		if physics.terrain_version == terrain.geometry_version || drain_calls > 4096 {
			break
		}
	}

	keys := make([dynamic]services.Terrain_Chunk_Key, 0, chunks)
	defer delete(keys)
	for key, chunk in terrain.chunks {
		if chunk != nil {
			append(&keys, key)
		}
	}

	mesh_start := time.now()
	for key in keys {
		vd := make([dynamic]f32, 0)
		mw := make([dynamic]f32, 0)
		idx := make([dynamic]u16, 0)
		_ = services.Terrain_Build_Chunk_Mesh(terrain, key, &vd, &mw, &idx)
		delete(vd)
		delete(mw)
		delete(idx)
	}
	mesh_ms := ms(time.since(mesh_start))

	fmt.printf(
		"ball r=15 @0.5 | cells=%d chunks=%d\n",
		services.Terrain_Cell_Count(terrain),
		chunks,
	)
	fmt.printf("  fill    =%8.2f ms\n", fill_ms)
	fmt.printf(
		"  physics =%8.2f ms total, %8.2f ms worst frame, %d frames, triangles=%d\n",
		ms(drain_total),
		ms(drain_max),
		drain_calls,
		physics.terrain_triangles,
	)
	fmt.printf("  cpu mesh=%8.2f ms (all chunks, serial)\n", mesh_ms)
}
