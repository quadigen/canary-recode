package main

import k "../src/engine/bindings"
import classes "../src/engine/classes"
import d "../src/engine/datatypes"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:math"
import sdl "vendor:sdl3"

main :: proc() {
	assert(sdl.Init({.VIDEO}))
	defer sdl.Quit()
	window := sdl.CreateWindow(
		"Kinemium - prebuilt locomotion animations",
		320,
		240,
		sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN,
	)
	assert(window != nil)
	defer sdl.DestroyWindow(window)
	ctx := k.Kine_Filament_CreateForVulkanCompositorWindow(window, 320, 240)
	assert(ctx != nil)
	defer k.Kine_Filament_Destroy(ctx)
	view := renderer.RendererObject {
		Filament        = ctx,
		HasViewportRect = true,
		ViewportRect    = {0, 0, 320, 240},
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
	legacy := cast(^classes.CharacterAnimator)classes.Find_First_Child(
		&cc.object,
		"CharacterAnimator",
	)
	assert(legacy != nil && !legacy.enabled)
	assert(
		k.Kine_Filament_GetMeshAnimationCount(rig.native_mesh) == 0,
		"the rig has no built-in locomotion",
	)
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
	for _ in 0 ..< 120 {step(&env, &state)}
	animator := cast(^classes.Animator)classes.Find_First_Child(&cc.object, "Animator")
	assert(animator != nil && animator.native_animator != nil)
	assert(len(animator.tracks) == 7)
	assert(state_name(animator) == "Idle")
	assert(k.Kine_Filament_GetMeshAnimationCount(rig.native_mesh) == 7)
	assert(
		!solver.enabled && solver.solve_count == 0,
		"authored locomotion must not invoke the procedural body gait",
	)
	head := classes.Animation_MeshPart_Find_Bone(rig.native_mesh, "mixamorig:Head_06")
	foot := classes.Animation_MeshPart_Find_Bone(rig.native_mesh, "mixamorig:LeftFoot_00")
	shoulder := classes.Animation_MeshPart_Find_Bone(rig.native_mesh, "mixamorig:LeftArm_011")
	wrist := classes.Animation_MeshPart_Find_Bone(rig.native_mesh, "mixamorig:LeftHand_013")
	h, hok := classes.Animation_MeshPart_Bone_World_CFrame(rig, int(head))
	f, fok := classes.Animation_MeshPart_Bone_World_CFrame(rig, int(foot))
	sh, shok := classes.Animation_MeshPart_Bone_World_CFrame(rig, int(shoulder))
	w, wok := classes.Animation_MeshPart_Bone_World_CFrame(rig, int(wrist))
	fmt.printf(
		"Idle rendered joints headY=%.3f footY=%.3f shoulderY=%.3f wristY=%.3f\n",
		h.y,
		f.y,
		sh.y,
		w.y,
	)
	assert(hok && fok && shok && wok)
	assert(h.y - f.y > 6, "retargeted animation must remain upright")
	assert(sh.y - w.y > 1.5, "authored idle arms must hang naturally")
	event: sdl.Event
	event.type = .KEY_DOWN; event.key.scancode = .LSHIFT
	engine_runtime.Environment_SetEvent(&env, &state, event); step(&env, &state)
	assert(cc.walk_speed == 16, "saved run input must respond to Left Shift")
	event.key.scancode = .LCTRL
	engine_runtime.Environment_SetEvent(&env, &state, event); step(&env, &state)
	assert(cc.walk_speed == 30, "saved sprint input must respond to Left Ctrl")
	event.type = .KEY_UP
	engine_runtime.Environment_SetEvent(&env, &state, event); step(&env, &state)
	assert(cc.walk_speed == 16)
	event.key.scancode = .LSHIFT
	engine_runtime.Environment_SetEvent(&env, &state, event); step(&env, &state)
	assert(cc.walk_speed == 5.5)
	start := root.cframe.x
	cs.move_direction = {1, 0, 0}
	for _ in 0 ..< 90 {step(&env, &state)}
	assert(state_name(animator) == "Walk" && root.cframe.x > start + 5)
	before, _ := classes.Animation_MeshPart_Bone_World_CFrame(rig, int(wrist))
	for _ in 0 ..< 16 {step(&env, &state)}
	after, _ := classes.Animation_MeshPart_Bone_World_CFrame(rig, int(wrist))
	assert(
		math.abs(before.r00 - after.r00) +
			math.abs(before.r11 - after.r11) +
			math.abs(before.r22 - after.r22) >
		0.005,
		"walk clip must animate the skeleton",
	)
	cc.walk_speed = 16; cs.move_direction = {0, 0, 1}
	for _ in 0 ..< 90 {step(&env, &state)}
	assert(state_name(animator) == "Run")
	cc.walk_speed = 30; cs.move_direction = {-1, 0, 0}
	for _ in 0 ..< 40 {step(&env, &state)}
	assert(state_name(animator) == "Sprint")
	cc.walk_speed = 5.5; cs.move_direction = {}
	for _ in 0 ..< 90 {step(&env, &state)}
	assert(state_name(animator) == "Idle")
	classes.MovementController_Queue_Jump(movement)
	seen: [7]bool
	for _ in 0 ..< 100 {
		step(&env, &state)
		assert(state_index(animator) >= 0 && state_index(animator) < 7)
		seen[state_index(animator)] = true
		sum: f32
		for track in animator.tracks {
			assert(track != nil)
			snapshot: k.KineAnimationTrackState
			assert(k.Kine_Filament_AnimationTrackGetState(track.native_track, &snapshot))
			sum += snapshot.weightCurrent
		}
		assert(
			sum > 0.95 && sum < 1.05,
			"one-shot transitions must not fall back through the bind T-pose",
		)
		assert(
			math.abs((root.cframe.y - rig.cframe.y) - 2.5) < 0.001,
			"animation must preserve the authored weld offset",
		)
	}
	fmt.printf("Jump states=%v\n", seen)
	assert(seen[4] && seen[5] && seen[6] && state_name(animator) == "Idle")

	animate := classes.Find_First_Child(&model.object, "Animate")
	run_asset := cast(^classes.Animation)classes.Find_First_Child(animate, "Run")
	selector := classes.Animation {
		animation_id = run_asset.animation_id,
		clip_name    = "Locomotion_Walk",
	}
	assert(classes.Animation_Resolve_Clip(animator, &selector) == -1)
	selector.clip_name = ""; selector.clip_index = 0
	selected := classes.Animation_Resolve_Clip(animator, &selector)
	assert(
		selected >= 0 && k.Kine_Filament_GetMeshAnimationDuration(rig.native_mesh, selected) < 1,
	)
	selected_count := k.Kine_Filament_GetMeshAnimationCount(rig.native_mesh)
	assert(classes.Animation_Resolve_Clip(animator, &selector) == selected)
	assert(k.Kine_Filament_GetMeshAnimationCount(rig.native_mesh) == selected_count)
	selector.animation_id = "/missing-user-animation.glb"; selector.clip_name = "Locomotion_Idle"
	assert(
		classes.Animation_Resolve_Clip(animator, &selector) == -1,
		"explicit invalid files must fail instead of using rig clips",
	)

	for track in animator.tracks {
		assert(track.animation != nil && classes.Is_A(track.animation, "Animation"))
		assert((cast(^classes.Animation)track.animation).animation_id != "")
	}


	run(
		&state,
		`
        local c=game:GetService("Players").LocalPlayer.Character
        local a=c.CharacterController.Animator
        local walk=c.Animate.Walk
        local t=a:LoadAnimation(walk)
        assert(t.Animation==walk and t.Length>1)
        local count=#c.XBot:GetAnimationClips()
        local again=a:LoadAnimation(walk)
        assert(#c.XBot:GetAnimationClips()==count)
        t:Play(0,0.25,0.5)
        assert(t.IsPlaying and t.Speed==0.5)
        t.TimePosition=0.3
        assert(math.abs(t.TimePosition-0.3)<0.001)
        t:Stop(0); t:Destroy(); again:Destroy()
        -- Swap a walking slot to a different authored file at runtime.
        walk.AnimationId=c.Animate.Run.AnimationId
        walk.ClipName=c.Animate.Run.ClipName
    `,
	)
	for _ in 0 ..< 5 {step(&env, &state)}
	run(
		&state,
		`
        local c=game:GetService("Players").LocalPlayer.Character
        local a=c.CharacterController.Animator
        local found=false
        for _,t in a:GetPlayingAnimationTracks() do
            if t.Animation==c.Animate.Walk then
                assert(t.Length<1 and t.Length>0.8)
                found=true
            end
        end
        assert(found,"walk slot must reload from the user-selected file")
    `,
	)
	classes.MeshPart_Release_Native_Mesh(rig)
	assert(animator.native_animator == nil, "mesh release must invalidate public tracks")
	assert(services.workspace_meshpart_mesh(rig, ctx) != nil)
	for _ in 0 ..< 60 {step(&env, &state)}
	assert(animator.native_animator != nil && state_name(animator) == "Idle")
	fmt.println(
		"Public tracks, seven states, user animation swap, file caching and mesh reload passed",
	)
	vm.Close(&state); engine_runtime.Environment_Destroy(&env)
	fmt.println("CHARACTER_ANIMATION_TRACKS_SMOKE_PASSED")
}

step :: proc(env: ^engine_runtime.Environment, state: ^vm.VM) {
	engine_runtime.Environment_Update_Step(env, state, 1.0 / 60.0)
	for o in classes.Find_Class(&env.classes, "Animator").instances {
		a := cast(^classes.Animator)o
		if a.native_animator !=
		   nil {assert(k.Kine_Filament_AnimatorStep(a.native_animator, 1.0 / 60.0))}
	}
}
state_index :: proc(a: ^classes.Animator) -> int {
	best: f32 = -1
	result := -1
	for t in a.tracks {
		if t.native_track == nil {continue}
		snapshot: k.KineAnimationTrackState
		if !k.Kine_Filament_AnimationTrackGetState(t.native_track, &snapshot) {continue}
		if snapshot.weightTarget > best {
			for name, i in classes.CHARACTER_ANIMATION_STATES {
				if t.name == name {best = snapshot.weightTarget; result = i}
			}
		}
	}
	return result
}
state_name :: proc(a: ^classes.Animator) -> string {
	i := state_index(a)
	return i >= 0 ? classes.CHARACTER_ANIMATION_STATES[i] : ""
}
run :: proc(v: ^vm.VM, source: string) {
	ok, error := vm.Run(v, source, "animation_tracks_smoke")
	if !ok {fmt.println(error)}
	assert(ok)
}
