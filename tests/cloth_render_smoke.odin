package main

import k "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:time"

draw :: proc(env: ^engine_runtime.Environment, state: ^vm.VM, render: ^renderer.RendererObject) {
	classes.Step(&env.classes, state.L, 1.0/60, phase = .Render_3D)
	services.Render_3D(&env.services, state.L, render, 1.0/60)
	k.Kine_Filament_RenderFrame(render.Filament, 1.0/60)
	time.sleep(16 * time.Millisecond)
}

main :: proc() {
	ctx := k.Kine_Filament_Create(128, 128)
	assert(ctx != nil, "Could not create an offscreen Filament renderer")
	defer k.Kine_Filament_Destroy(ctx)
	render := renderer.RendererObject{Filament = ctx}
	state := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &state, &render)
	defer {vm.Close(&state); engine_runtime.Environment_Destroy(&env)}
	ok, err := vm.Run(&state, `
workspace.SimulatePhysics = false
cloth = Instance.new("Cloth", workspace)
cloth.ClothType = Enum.ClothType.Curtain
cloth.SegmentsX = 24
cloth.SegmentsY = 24
cloth.RenderSegmentsX = 48
cloth.RenderSegmentsY = 48
cloth.FoldDepth = 0.3
cloth.Color = Color3.fromRGB(140, 20, 35)
decal = Instance.new("Decal", cloth)
decal.Face = Enum.NormalId.Front
`, "cloth_render_setup")
	assert(ok, err)
	vm.GetGlobal(state.L, "cloth")
	cloth := cast(^classes.Cloth)classes.Object_From_Argument(state.L, -1)
	vm.Pop(state.L)
	vm.GetGlobal(state.L, "decal")
	decal := cast(^classes.Decal)classes.Object_From_Argument(state.L, -1)
	vm.Pop(state.L)
	texel: [4]u8 = {255, 255, 255, 255}
	decal.native_texture = k.Kine_Filament_CreateTexFromPixels(ctx, 1, 1, 4, &texel[0])
	assert(decal.native_texture != nil)
	decal.texture_dirty = false
	k.Kine_Filament_SetCameraPerspective(ctx, 60, 1, 0.1, 100)
	k.Kine_Filament_SetCameraLookAt(ctx, 2, -2, 12, 2, -2, 0, 0, 1, 0)
	for _ in 0..<3 {draw(&env, &state, &render)}
	assert(cloth.mesh != nil && decal.cloth_mesh != nil)
	assert(cloth.render_grid == ([2]int{48, 48}))
	center, extent: [3]f32
	assert(k.Kine_Filament_GetMeshBounds(cloth.mesh, &center[0], &extent[0]))
	before := extent.z
	mesh := cloth.mesh
	cloth.particles[len(cloth.particles) - 1].position.z += 5
	cloth.revision += 1
	draw(&env, &state, &render)
	assert(cloth.mesh == mesh)
	stats: k.KineFilamentBatchStats
	k.Kine_Filament_GetBatchStats(ctx, &stats)
	assert(stats.boundsUpdates > 0, "A deformation with unchanged transform must refresh Filament batch bounds")
	assert(k.Kine_Filament_GetMeshBounds(cloth.mesh, &center[0], &extent[0]) && extent.z > before + 2)
	assert(k.Kine_Filament_GetMeshBounds(decal.cloth_mesh, &center[0], &extent[0]) && extent.z > before + 2)
	assert(decal.cloth_revision == cloth.revision)
	k.Kine_Filament_SetCameraLookAt(ctx, 2, -2, -12, 2, -2, 0, 0, 1, 0)
	draw(&env, &state, &render)
	ok, err = vm.Run(&state, "cloth.RenderSegmentsY = 64", "cloth_render_resize")
	assert(ok, err)
	draw(&env, &state, &render)
	assert(cloth.mesh != nil && decal.cloth_mesh != nil && cloth.render_grid.y == 64)
	assert(cloth.mesh_topology_revision == decal.cloth_topology_revision)
	fmt.println("CLOTH_RENDER_SMOKE_PASSED")
}
