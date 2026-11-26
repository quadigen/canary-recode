package main

import k "../src/engine/bindings"
import classes "../src/engine/classes"
import d "../src/engine/datatypes"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"
import sdl "vendor:sdl3"

main :: proc() {
	assert(sdl.Init({.VIDEO}))
	defer sdl.Quit()
	window := sdl.CreateWindow(
		"Kinemium - prebuilt locomotion animations",
		1280,
		720,
		sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN,
	)
	assert(window != nil)
	defer sdl.DestroyWindow(window)
	ctx := k.Kine_Filament_CreateForVulkanCompositorWindow(window, 1280, 720)
	assert(ctx != nil)
	defer k.Kine_Filament_Destroy(ctx)
	view := renderer.RendererObject {
		Filament        = ctx,
		HasViewportRect = true,
		ViewportRect    = {0, 0, 1280, 720},
	}
	state := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &state, &view)
	engine_runtime.Environment_Set_Mode(&env, .Singleplayer)
	assert(engine_runtime.Load_Map(&env, &state, "build/locomotion-test.kine"))
	players := cast(^services.Players)services.Ensure_Service(&env.services, "Players")
	players.local_player = services.Players_Add(players, state.L, 77, "XBotPlayer")
	cs := cast(^services.CharacterService)services.Ensure_Service(
		&env.services,
		"CharacterService",
	)
	model := services.CharacterService_Load(cs, players.local_player)
	assert(model != nil)
	root := classes.CharacterModel_Root(model)
	mesh_obj := classes.Find_First_Child(&model.object, "XBot")
	assert(mesh_obj != nil)
	rig := cast(^classes.MeshPart)mesh_obj
	assert(services.workspace_meshpart_mesh(rig, ctx) != nil)
	assert(k.Kine_Filament_GetMeshBoneCount(rig.native_mesh) == 68)
	cc := classes.CharacterController_From_Model(model)
	assert(cc != nil)
	solver := cast(^classes.CharacterPhysicsSolver)classes.CharacterController_Find(
		cc,
		"CharacterPhysicsSolver",
	)
	assert(solver != nil && !solver.enabled)
	animator := cast(^classes.CharacterAnimator)classes.Find_First_Child(
		&cc.object,
		"CharacterAnimator",
	)
	assert(animator != nil && !animator.enabled)
	cs.native_input_enabled = false
	workspace := cast(^services.Workspace)services.Ensure_Service(&env.services, "Workspace")
	camera := workspace.current_camera
	classes.Model_Pivot_To(&model.model, d.CFrame_New_XYZ(0, 44, 0))
	camera.CameraType = .Scriptable
	camera.field_of_view = 45
	movement := cast(^classes.MovementController)classes.CharacterController_Find(
		cc,
		"MovementController",
	)
	cc.walk_speed = 5.5
	movement.walk_speed = 5.5
	compositor := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(ctx)
	output, output_error := os.create("captures/animation-demo/frames.rgba")
	assert(output_error == nil); defer os.close(output)
	raster := k.Kine_Skia_Surface_Create(1280, 720); assert(raster != nil)
	defer k.Kine_Skia_Surface_Destroy(raster)
	limit := 1560
	if len(os.args) > 1 && os.args[1] == "--preview" {limit = 4}
	for frame in 0 ..< limit {
		event: sdl.Event
		for sdl.PollEvent(&event) {}
		t := f64(frame) / 60.0
		cs.move_direction = {}
		cc.walk_speed = 5.5
		if t >= 3 && t < 8 {cs.move_direction = {1, 0, 0}}
		if t >= 9 && t < 13 {cs.move_direction = {0, 0, 1}; cc.walk_speed = 16}
		if t >= 14 && t < 18 {cs.move_direction = {-1, 0, 0}; cc.walk_speed = 5.5}
		if t >= 19 && t < 21 {cs.move_direction = {0, 0, -1}; cc.walk_speed = 30}
		if frame == 660 ||
		   frame == 930 ||
		   frame == 1200 {classes.MovementController_Queue_Jump(movement)}
		engine_runtime.Environment_Update_Step(&env, &state, 1.0 / 60.0)
		target := d.Vector3{root.cframe.x, root.cframe.y, root.cframe.z}
		target.y += 2.2
		camera.CFrame = d.CFrame_LookAt(d.Vec3_Add(target, {10, 5, 13}), target)
		services.Prepare_3D(&env.services, &view)
		base := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(compositor)
		assert(base != nil)
		k.Kine_Skia_Surface_Clear(base, 20, 30, 40, 255)
		engine_runtime.Environment_Render_2D(&env, &state, base, 1280, 720, 1.0 / 60.0)
		engine_runtime.Environment_Render_3D(&env, &state, 1.0 / 60.0)
		k.Kine_Filament_RenderFrame(ctx, 1.0 / 60.0)
		overlay := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginOverlay(compositor)
		assert(overlay != nil)
		engine_runtime.Environment_Render_Overlay(&env, &state, overlay, 1280, 720, 1.0 / 60.0)
		if frame % 2 == 0 {


			k.Kine_Skia_Surface_SetBackdropFromSurface(overlay, overlay)
			assert(k.Kine_Skia_Surface_BeginPicture(overlay) != 0)
			k.Kine_Skia_Surface_DrawBackdropRect(
				overlay,
				0,
				0,
				1280,
				720,
				0,
				0,
				2,
				0,
				0,
				0,
				0,
				1,
				1,
				0,
				0,
				0,
				0,
				1,
				255,
				0,
				0,
				0,
				0,
			)
			picture := k.Kine_Skia_Surface_EndPicture(overlay); assert(picture != nil)
			k.Kine_Skia_Surface_DrawPicture(raster, picture)
			k.Kine_Skia_Picture_Destroy(picture)
			pixels := cast(^[1280 *
			720 *
			4]u8)k.Kine_Skia_Surface_GetPixels(raster); assert(pixels != nil)
			count, err := os.write(
				output,
				pixels[:],
			); assert(err == nil && count == 1280 * 720 * 4)
			k.Kine_Skia_Surface_ClearBackdrop(overlay)
		}
		assert(k.Kine_VulkanCompositor_EndFrame(compositor) != 0)
		if frame % 60 ==
		   0 {fmt.printf("ANIMATION_TRACKS t=%.1f root=(%.2f,%.2f,%.2f)\n", t, root.cframe.x, root.cframe.y, root.cframe.z)}
	}
	fmt.println("DEMO_COMPLETE")
}
