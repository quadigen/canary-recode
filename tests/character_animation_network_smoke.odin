package main

import kineffi "../src/engine/bindings"
import classes "../src/engine/classes"
import rt "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import sdl "vendor:sdl3"

run :: proc(state: ^vm.VM, source: string) {
	ok, err := vm.RunInternal(state, source, "character_animation_network")
	assert(ok, err)
}

step :: proc(server, owner, observer: ^rt.Environment, sv, ov, rv: ^vm.VM, frames: int) {
	for _ in 0 ..< frames {
		rt.Environment_Update_Step(server, sv, 1.0 / 60)
		rt.Environment_Update_Step(owner, ov, 1.0 / 60)
		rt.Environment_Update_Step(observer, rv, 1.0 / 60)
		time.sleep(2 * time.Millisecond)
	}
}

find_rig :: proc(rep: ^services.ReplicatorService, user: u32) -> ^services.Replication_Entity {
	for entity in rep.entity_list {
		if classes.Is_A(entity.object, "MeshPart") &&
		   services.replication_character_pose_owner(rep, entity.object) == user {return entity}
	}
	return nil
}

main :: proc() {
	assert(len(os.args) > 1, "pass a rigged GLB asset path")
	assert(sdl.Init({.VIDEO}))
	defer sdl.Quit()
	window := sdl.CreateWindow(
		"Character animation networking",
		320,
		240,
		sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN,
	)
	assert(window != nil)
	defer sdl.DestroyWindow(window)
	ctx := kineffi.Kine_Filament_CreateForVulkanCompositorWindow(window, 320, 240)
	assert(ctx != nil)
	defer kineffi.Kine_Filament_Destroy(ctx)
	sv, ov, rv := vm.New(), vm.New(), vm.New()
	server, owner, observer: rt.Environment
	rt.Environment_Init(&server, &sv, nil, .Server)
	rt.Environment_Init(&owner, &ov, nil, .Client)
	rt.Environment_Init(&observer, &rv, nil, .Client)
	run(
		&sv,
		`
local floor = Instance.new("Part", workspace)
floor.Name = "Spawn"
floor.Anchored = true
floor.Size = Vector3.new(500, 2, 500)
floor.Position = Vector3.new(0, -1, 0)
local starter = game:GetService("StarterPlayer")
local template = Instance.new("Model", starter)
template.Name = "StarterCharacter"
local root = Instance.new("Part", template)
root.Name = "HumanoidRootPart"
root.Anchored = true
root.Size = Vector3.new(2,5,2)
local body = Instance.new("MeshPart", template)
body.Name = "Rig"
body.Anchored = true
body.CanCollide = false
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39579))
`,
	)
	run(&ov, `assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39579))`)
	run(&rv, `assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39579))`)
	sr := cast(^services.ReplicatorService)services.Find_Service(&server.services, "ReplicatorService").object
	or := cast(^services.ReplicatorService)services.Find_Service(&owner.services, "ReplicatorService").object
	rr := cast(^services.ReplicatorService)services.Find_Service(&observer.services, "ReplicatorService").object
	for _ in 0 ..< 1000 {
		step(&server, &owner, &observer, &sv, &ov, &rv, 1)
		if or.replication_finished && rr.replication_finished {break}
	}
	assert(or.replication_finished && rr.replication_finished)
	user := services.ownership_local_user_id(or)
	source, cached, remote := find_rig(or, user), find_rig(sr, user), find_rig(rr, user)
	assert(source != nil && cached != nil && remote != nil)
	source_mesh, remote_mesh :=
		cast(^classes.MeshPart)source.object, cast(^classes.MeshPart)remote.object
	path := strings.clone_to_cstring(os.args[1])
	defer delete(path)
	source_mesh.native_mesh = kineffi.Kine_Filament_CreateMeshFromPathIndexed(ctx, path, 0)
	remote_mesh.native_mesh = kineffi.Kine_Filament_CreateMeshFromPathIndexed(ctx, path, 0)
	source_mesh.native_context, remote_mesh.native_context = ctx, ctx
	assert(source_mesh.native_mesh != nil && remote_mesh.native_mesh != nil)
	count := kineffi.Kine_Filament_GetMeshBoneCount(source_mesh.native_mesh)
	assert(count > 0)
	bind: [16]f32
	assert(
		kineffi.Kine_Filament_CopyMeshBoneGlobalTransform(
			remote_mesh.native_mesh,
			count - 1,
			&bind[0],
		),
	)
	clip := kineffi.Kine_Filament_MeshCreateAnimation(source_mesh.native_mesh, "NetworkPose", 1)
	bone := kineffi.Kine_Filament_GetMeshBoneName(source_mesh.native_mesh, count - 1)
	assert(clip >= 0 && bone != nil)
	transform := [12]f32{0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1}
	assert(
		kineffi.Kine_Filament_MeshAddAnimationPose(
			source_mesh.native_mesh,
			clip,
			bone,
			0,
			&transform[0],
			1,
		),
	)
	transform[0] = 0.5
	assert(
		kineffi.Kine_Filament_MeshAddAnimationPose(
			source_mesh.native_mesh,
			clip,
			bone,
			1,
			&transform[0],
			1,
		),
	)
	animator := kineffi.Kine_Filament_AnimatorCreate(ctx, source_mesh.native_mesh)
	assert(animator != nil)
	track := kineffi.Kine_Filament_AnimatorLoadAnimation(animator, clip)
	assert(track != nil && kineffi.Kine_Filament_AnimationTrackPlay(track, 0, 1, 1))
	assert(kineffi.Kine_Filament_AnimatorStep(animator, 0.5))
	expected: [16]f32
	assert(
		kineffi.Kine_Filament_CopyMeshBoneGlobalTransform(
			source_mesh.native_mesh,
			count - 1,
			&expected[0],
		),
	)
	assert(expected != bind)
	step(&server, &owner, &observer, &sv, &ov, &rv, 150)
	assert(len(cached.pose) == int(count), "headless server did not receive skeleton")
	assert(
		len(remote.pose) == int(count) && remote.pose_applied_valid,
		"observer did not apply skeleton",
	)
	actual: [16]f32
	assert(
		kineffi.Kine_Filament_CopyMeshBoneGlobalTransform(
			remote_mesh.native_mesh,
			count - 1,
			&actual[0],
		),
	)
	for i in 0 ..< 16 {assert(abs(expected[i] - actual[i]) < 0.001, "remote rendered pose mismatch")}
	server_mesh := cast(^classes.MeshPart)cached.object
	server_mesh.native_mesh = kineffi.Kine_Filament_CreateMeshFromPathIndexed(ctx, path, 0)
	server_mesh.native_context = ctx
	assert(server_mesh.native_mesh != nil)
	sequence := cached.pose_sequence
	assert(kineffi.Kine_Filament_AnimatorStep(animator, 0.25))
	assert(
		kineffi.Kine_Filament_CopyMeshBoneGlobalTransform(
			source_mesh.native_mesh,
			count - 1,
			&expected[0],
		),
	)
	assert(expected != actual, "animation did not advance")
	step(&server, &owner, &observer, &sv, &ov, &rv, 120)
	assert(cached.pose_sequence > sequence && remote.pose_sequence == cached.pose_sequence)
	assert(cached.pose_applied_valid)
	server_actual: [16]f32
	assert(
		kineffi.Kine_Filament_CopyMeshBoneGlobalTransform(
			server_mesh.native_mesh,
			count - 1,
			&server_actual[0],
		),
	)
	assert(
		kineffi.Kine_Filament_CopyMeshBoneGlobalTransform(
			remote_mesh.native_mesh,
			count - 1,
			&actual[0],
		),
	)
	for i in 0 ..< 16 {
		assert(abs(expected[i] - actual[i]) < 0.001, "observer animation did not advance")
		assert(
			abs(expected[i] - server_actual[i]) < 0.001,
			"graphical server animation did not advance",
		)
	}
	accepted_sequence := cached.pose_sequence
	forged := remote^
	forged.pose_sequence += 100
	payload: [dynamic]u8
	defer delete(payload)
	services.replication_character_pose_encode(&forged, &payload)
	assert(
		services.replication_send(
			rr,
			rr.remote,
			services.Replication_Kind_Character_Pose,
			payload[:],
			false,
		),
	)
	step(&server, &owner, &observer, &sv, &ov, &rv, 60)
	assert(
		cached.pose_sequence == accepted_sequence,
		"observer modified another player's skeleton",
	)
	classes.MeshPart_Release_Native_Mesh(server_mesh)
	fmt.printf(
		"Skeletal animation replicated: %d bones, server sequence=%d observer sequence=%d\n",
		count,
		cached.pose_sequence,
		remote.pose_sequence,
	)
	kineffi.Kine_Filament_AnimatorDestroy(animator)
	classes.MeshPart_Release_Native_Mesh(source_mesh)
	classes.MeshPart_Release_Native_Mesh(remote_mesh)
	vm.Close(&rv)
	vm.Close(&ov)
	vm.Close(&sv)
	rt.Environment_Destroy(&observer)
	rt.Environment_Destroy(&owner)
	rt.Environment_Destroy(&server)
	fmt.println("CHARACTER_ANIMATION_NETWORK_SMOKE_PASSED")
}
