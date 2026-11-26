package main

import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:time"

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.Run(v, source, "terrain_scheduler_smoke")
	assert(ok, err)
}

main :: proc() {
	v := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &v)
	defer {vm.Close(&v); engine_runtime.Environment_Destroy(&environment)}
	terrain := cast(^services.Terrain)services.Ensure_Service(&environment.services, "Terrain")
	run(
		&v,
		`
local terrain = game:GetService("Terrain")
terrain.FrameBudgetMs = 0.5
terrain.MeshLODEnabled = true
terrain.MeshLODDistance = 256
assert(terrain.FrameBudgetMs == 0.5)
assert(terrain.MeshLODEnabled and terrain.MeshLODDistance == 256)
assert(not pcall(function() terrain.FrameBudgetMs = 0/0 end))
assert(not pcall(function() terrain.MeshLODDistance = math.huge end))
terrain:Fill(0, 0, 0, 2, 2, {type="flat", caves=false})
`,
	)
	started := time.tick_now()
	for terrain.generation != nil {
		engine_runtime.Environment_Update_Step(&environment, &v, 1.0 / 60)
		assert(
			time.tick_since(started) < 5 * time.Second,
			"headless terrain generation did not finish through runtime frame hook",
		)
		time.sleep(time.Millisecond)
	}
	assert(services.Terrain_Cell_Count(terrain) > 0)
	assert(terrain.frame_work.last_ms >= 0)
	fmt.printfln(
		"TERRAIN_SCHEDULER_SMOKE_PASSED cells=%d prepare_ms=%.3f",
		services.Terrain_Cell_Count(terrain),
		terrain.frame_work.last_ms,
	)
}
