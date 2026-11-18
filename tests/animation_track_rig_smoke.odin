// Exercises AnimationTrack on an imported rigged MeshPart.
//
// Everything that touches Animation, Animator, and AnimationTrack is Luau: the
// script creates the MeshPart, points it at the FBX asset, discovers the
// imported bones/clips, builds the Animation, loads and scrubs tracks, and
// asserts playback/event/parameter semantics. Odin only owns the window,
// camera, render loop, and pixel checks.
//
// Headless by default: renders a hidden window, saves pose frames and a
// contact sheet under build/, and fails if the animation does not visibly move
// the rig. Pass --visual to watch the clip play in a real window. Pass a mesh
// path to test another rig; the default is the Boxing.fbx fixture.

package main

import k "../src/engine/bindings"
import classes "../src/engine/classes"
import datatypes "../src/engine/datatypes"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:math"
import "core:os"
import "core:time"
import sdl "vendor:sdl3"

WIDTH :: 480
HEIGHT :: 480
POSE_COUNT :: 4
POSE_FRACTIONS := [POSE_COUNT]f64{0, 0.33, 0.66, 0.99}
BACKGROUND := [3]u8{16, 18, 24}

run :: proc(v: ^vm.VM, source, label: string) {
	ok, err := vm.Run(v, source, label)
	assert(ok, err)
}

write_ppm :: proc(path: string, width, height: int, pixels: []u8) -> bool {
	file, err := os.create(path)
	if err != nil {return false}
	defer os.close(file)
	header := fmt.tprintf("P6\n%d %d\n255\n", width, height)
	_, _ = os.write(file, transmute([]u8)header)
	_, _ = os.write(file, pixels)
	return true
}

// Renders one frame of the current pose and copies the composited pixels out.
capture_frame :: proc(
	env: ^engine_runtime.Environment,
	v: ^vm.VM,
	ctx: ^k.KineFilamentContext,
	view: ^renderer.RendererObject,
	compositor: ^k.KineVulkanCompositor,
	pixels: []u8,
	path: string,
	read_pixels := true,
) {
	services.Prepare_3D(&env.services, view)
	base := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(compositor)
	assert(base != nil)
	k.Kine_Skia_Surface_Clear(base, BACKGROUND[0], BACKGROUND[1], BACKGROUND[2], 255)
	engine_runtime.Environment_Render_2D(env, v, base, WIDTH, HEIGHT, 1.0 / 60.0)
	engine_runtime.Environment_Render_3D(env, v, 1.0 / 60.0)
	k.Kine_Filament_RenderFrame(ctx, 1.0 / 60.0)
	overlay := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginOverlay(compositor)
	assert(overlay != nil)
	engine_runtime.Environment_Render_Overlay(env, v, overlay, WIDTH, HEIGHT, 1.0 / 60.0)
	if read_pixels {
		assert(len(pixels) >= WIDTH * HEIGHT * 3, "pixel buffer too small")
		for y in 0 ..< HEIGHT {
			for x in 0 ..< WIDTH {
				r, g, b, a: u8
				k.Kine_Skia_Surface_GetPixel(overlay, i32(x), i32(y), &r, &g, &b, &a)
				offset := (y * WIDTH + x) * 3
				pixels[offset] = r
				pixels[offset + 1] = g
				pixels[offset + 2] = b
			}
		}
	}
	assert(k.Kine_VulkanCompositor_EndFrame(compositor) != 0)
	if path != "" {
		assert(read_pixels, "cannot write a frame without reading pixels")
		assert(write_ppm(path, WIDTH, HEIGHT, pixels), "could not write pose frame")
	}
}

frame_difference :: proc(reference, frame: []u8) -> (changed: int, mean_delta: f64) {
	pixel_count := len(frame) / 3
	total: u64
	for i := 0; i < pixel_count * 3; i += 3 {
		delta :=
			abs(int(frame[i]) - int(reference[i])) +
			abs(int(frame[i + 1]) - int(reference[i + 1])) +
			abs(int(frame[i + 2]) - int(reference[i + 2]))
		if delta > 24 {changed += 1}
		total += u64(delta)
	}
	return changed, f64(total) / f64(max(pixel_count, 1))
}

save_contact_sheet :: proc(frames: [][]u8, path: string) -> bool {
	sheet_width := WIDTH * 2
	sheet_height := HEIGHT * 2
	sheet := make([]u8, sheet_width * sheet_height * 3)
	defer delete(sheet)
	for pose in 0 ..< len(frames) {
		cell_x := (pose % 2) * WIDTH
		cell_y := (pose / 2) * HEIGHT
		for y in 0 ..< HEIGHT {
			for x in 0 ..< WIDTH {
				src := (y * WIDTH + x) * 3
				dst := ((cell_y + y) * sheet_width + cell_x + x) * 3
				sheet[dst] = frames[pose][src]
				sheet[dst + 1] = frames[pose][src + 1]
				sheet[dst + 2] = frames[pose][src + 2]
			}
		}
	}
	return write_ppm(path, sheet_width, sheet_height, sheet)
}

main :: proc() {
	mesh_path := "tests/assets/Boxing.fbx"
	visual := false
	for arg in os.args[1:] {
		if arg == "--visual" {visual = true} else {mesh_path = arg}
	}
	if _, err := os.stat(mesh_path, context.allocator); err != nil {
		fmt.println("ANIMATION_RIG_MESH_MISSING", mesh_path)
		os.exit(1)
	}

	assert(sdl.Init({.VIDEO}))
	defer sdl.Quit()
	flags := sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN
	if visual {flags = sdl.WINDOW_VULKAN}
	window := sdl.CreateWindow("AnimationTrack rig smoke", WIDTH, HEIGHT, flags)
	assert(window != nil)
	defer sdl.DestroyWindow(window)
	ctx := k.Kine_Filament_CreateForVulkanCompositorWindow(window, WIDTH, HEIGHT)
	assert(ctx != nil)
	defer k.Kine_Filament_Destroy(ctx)
	compositor := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(ctx)
	assert(compositor != nil)
	view := renderer.RendererObject {
		Filament        = ctx,
		HasViewportRect = true,
		ViewportRect    = {0, 0, WIDTH, HEIGHT},
	}
	v := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &v, &view)
	defer {
		vm.Close(&v)
		engine_runtime.Environment_Destroy(&env)
	}

	// The rig is built in Luau, including its FBX path.
	run(
		&v,
		fmt.tprintf(
			`
local rig = Instance.new("MeshPart")
rig.Name = "BoxingRig"
rig.MeshId = %q
rig.Size = Vector3.new(1, 1, 1)
rig.CFrame = CFrame.new(0, 0, 0)
rig.Anchored = true
rig.CanCollide = false
rig.Parent = workspace
`,
			mesh_path,
		),
		"rig_setup",
	)

	workspace := cast(^services.Workspace)services.Ensure_Service(&env.services, "Workspace")
	rig := cast(^classes.MeshPart)classes.Find_First_Child(&workspace.object, "BoxingRig")
	assert(rig != nil, "Luau did not create the rig MeshPart")

	pose_frames := make([][]u8, POSE_COUNT)
	for pose in 0 ..< POSE_COUNT {pose_frames[pose] = make([]u8, WIDTH * HEIGHT * 3)}
	defer {
		for frame in pose_frames {delete(frame)}
		delete(pose_frames)
	}
	scratch := make([]u8, WIDTH * HEIGHT * 3)
	defer delete(scratch)
	// control is the same view with the rig hidden, so pose pixels can be
	// separated from the sky and lighting behind the rig.
	control := make([]u8, WIDTH * HEIGHT * 3)
	defer delete(control)

	// Prime the workspace so the MeshPart imports its native geometry.
	capture_frame(&env, &v, ctx, &view, compositor, scratch, "", !visual)
	assert(rig.native_mesh != nil, "MeshPart failed to import the FBX rig")

	center, half: [3]f32
	assert(k.Kine_Filament_GetMeshBounds(rig.native_mesh, &center[0], &half[0]))
	scale := f32(0.5) // rig.Size = (1, 1, 1); MeshPart render scale is Size * 0.5.
	target := datatypes.Vector3{center[0] * scale, center[1] * scale, center[2] * scale}
	radius := max(
		f32(math.sqrt(f64(half[0] * half[0] + half[1] * half[1] + half[2] * half[2]))) * scale,
		f32(0.5),
	)
	camera := cast(^classes.Camera)view.ActiveCamera
	assert(camera != nil, "workspace has no active camera")
	camera.CameraType = .Scriptable
	camera.field_of_view = 35
	camera.viewport_width = WIDTH
	camera.viewport_height = HEIGHT
	direction := datatypes.Vector3{0.6, 0.12, 1}
	direction_length := f32(
		math.sqrt(f64(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)),
	)
	distance :=
		radius / f32(math.sin(math.to_radians(f64(camera.field_of_view) * 0.5))) * 1.12
	eye := datatypes.Vector3 {
		target.x + direction.x / direction_length * distance,
		target.y + direction.y / direction_length * distance,
		target.z + direction.z / direction_length * distance,
	}
	camera.CFrame = datatypes.CFrame_LookAt_Default(eye, target)
	fmt.println(
		"ANIMATION_RIG_FRAME",
		rig.native_mesh != nil,
		"center",
		center,
		"half",
		half,
		"radius",
		radius,
		"distance",
		distance,
	)

	if !visual {
		run(&v, `workspace.BoxingRig.Transparency = 1`, "control_hide_rig")
		capture_frame(
			&env,
			&v,
			ctx,
			&view,
			compositor,
			control,
			"build/animation_track_rig_control.ppm",
		)
		run(&v, `workspace.BoxingRig.Transparency = 0`, "control_show_rig")
	}

	// Clip discovery, Animation construction, track loading, and baseline
	// playback properties all happen in Luau.
	run(
		&v,
		`
local rig = workspace.BoxingRig
local bones = rig:GetBoneNames()
local clips = rig:GetAnimationClips()
assert(#bones > 0, "rig exposed no bones")
assert(type(bones[1]) == "string" and bones[1] ~= "", "bone name is not a string")
assert(#clips > 0, "rig exposed no animation clips")
for _, clip in clips do
    assert(type(clip.Index) == "number" and clip.Index >= 0, "clip index")
    assert(type(clip.Name) == "string" and clip.Name ~= "", "clip name")
    assert(clip.Length > 0, "clip length")
end
RIG_BONES = #bones
RIG_CLIPS = #clips
FIRST_CLIP = clips[1].Name
FIRST_LENGTH = clips[1].Length

local anim = Instance.new("Animation")
anim.Name = "BoxingClip"
anim.ClipName = FIRST_CLIP
anim.Looped = true
anim.Priority = Enum.AnimationPriority.Action
assert(anim.Source == nil)
assert(anim.ClipName == FIRST_CLIP)

-- Assigning only the parent must discover the rigged MeshPart (docs promise
-- ancestry discovery). Do not set MeshPart explicitly.
local animator = Instance.new("Animator")
animator.Parent = rig
assert(animator.MeshPart == rig, "Animator did not discover its MeshPart parent")
assert(animator.EvaluationThrottled == false)
assert(animator.PreferLodEnabled == true)
ANIMATOR = animator

PLAYED = 0
STOPPED = 0
ENDED = 0
LOOPS = 0
KEYFRAMES = 0
animator.AnimationPlayed:Connect(function(track)
    PLAYED += 1
    assert(track == TRACK, "AnimationPlayed received the wrong track")
end)

local track = animator:LoadAnimation(anim)
TRACK = track
track.Stopped:Connect(function() STOPPED += 1 end)
track.Ended:Connect(function() ENDED += 1 end)
track.DidLoop:Connect(function() LOOPS += 1 end)
track.KeyframeReached:Connect(function(name) KEYFRAMES += 1 end)

assert(track.Animation == anim, "track.Animation")
assert(track.IsPlaying == false, "fresh track is already playing")
assert(track.Looped == true, "Looped did not come from Animation")
assert(track.Priority == Enum.AnimationPriority.Action, "track priority")
assert(track.Length > 0 and math.abs(track.Length - FIRST_LENGTH) < 0.01, "track length")
assert(track.Speed == 1, "initial speed")
assert(track.TimePosition == 0, "initial time")
assert(track.WeightCurrent == 0 and track.WeightTarget == 0, "initial weight")
assert(#animator:GetPlayingAnimationTracks() == 0, "idle track list is not empty")

-- Parameters accept any value and disappear when set to nil.
track:SetParameter("phase", { value = 7 })
assert(track:GetParameter("phase").value == 7, "table parameter")
track:SetParameter("phase", "second")
assert(track:GetParameter("phase") == "second", "replacement parameter")
track:SetParameter("phase", nil)
assert(track:GetParameter("phase") == nil, "parameter removal")
assert(next(track:GetParameterDefaults()) == nil, "parameter defaults must be empty")

-- Play with a zero fade and zero speed so the test can scrub deterministically.
track:Play(0, 1, 0)
assert(track.IsPlaying, "track did not start")
assert(track.WeightCurrent == 1 and track.WeightTarget == 1, "instant weight")
assert(track.Speed == 0, "play speed was not applied")
assert(PLAYED == 1, "AnimationPlayed did not fire once")
local playing = animator:GetPlayingAnimationTracks()
assert(#playing == 1 and playing[1] == track, "playing track list")

track.Priority = Enum.AnimationPriority.Movement
assert(track.Priority == Enum.AnimationPriority.Movement, "priority setter")
track.Priority = Enum.AnimationPriority.Action
track:AdjustSpeed(2)
assert(track.Speed == 2, "AdjustSpeed")
track:AdjustSpeed(0)
track:AdjustWeight(0.5, 0)
assert(track.WeightTarget == 0.5 and track.WeightCurrent == 0.5, "AdjustWeight")
track:AdjustWeight(1, 0)
`,
		"track_setup",
	)

	// The pose frames are a headless-only visual regression check. Reading the
	// surface back five times is what made the visible run feel like it hung.
	if !visual {
	// Occlude nothing: capture at evenly spaced times through the clip.
	for fraction, pose in POSE_FRACTIONS {
		run(
			&v,
			fmt.tprintf(
				`
local track = TRACK
local target = track.Length * %v
track.TimePosition = target
assert(math.abs(track.TimePosition - target) < 0.02, "TimePosition setter")
ANIMATOR:StepAnimations(0)
assert(track.IsPlaying, "scrubbing stopped the track")
assert(track.WeightCurrent == 1, "scrubbing changed the weight")
POSED_TIME = track.TimePosition
`,
				fraction,
			),
			"pose_scrub",
		)
		capture_frame(
			&env,
			&v,
			ctx,
			&view,
			compositor,
			pose_frames[pose],
			fmt.tprintf("build/animation_track_rig_pose_%d.ppm", pose),
		)
	}

	foreground: [POSE_COUNT]int
	changed: [POSE_COUNT]int
	mean: [POSE_COUNT]f64
	for frame, pose in pose_frames {
		foreground[pose], _ = frame_difference(control, frame)
		changed[pose], mean[pose] = frame_difference(pose_frames[0], frame)
		fmt.println(
			"ANIMATION_RIG_FRAME",
			pose,
			"time_fraction",
			POSE_FRACTIONS[pose],
			"foreground",
			foreground[pose],
			"changed_vs_rest",
			changed[pose],
			"mean_delta",
			mean[pose],
		)
	}
	for pose in 0 ..< POSE_COUNT {
		assert(foreground[pose] > 500, "the rig is not visible in the captured frame")
	}
	assert(changed[1] > 100, "the animation does not visibly change the rig pose")
	assert(changed[2] > 100, "the animation does not visibly change the rig pose")
	assert(changed[3] > 100, "the animation does not visibly change the rig pose")
	assert(save_contact_sheet(pose_frames, "build/animation_track_rig_contact.ppm"))
	fmt.println(
		"ANIMATION_RIG_VISUAL",
		"build/animation_track_rig_pose_0.ppm",
		"build/animation_track_rig_pose_1.ppm",
		"build/animation_track_rig_pose_2.ppm",
		"build/animation_track_rig_pose_3.ppm",
		"build/animation_track_rig_contact.ppm",
	)
	}

	// Looping restarts the clip and fires DidLoop during the Update phase.
	run(
		&v,
		`
local track = TRACK
track.Looped = true
track:AdjustSpeed(1)
track.TimePosition = track.Length - 0.05
ANIMATOR:StepAnimations(0.2)
assert(track.IsPlaying, "looping ended the track")
assert(track.TimePosition >= 0 and track.TimePosition < track.Length, "loop wrap position")
`,
		"loop_step",
	)
	engine_runtime.Environment_Update_Step(&env, &v, 1.0 / 60.0)
	run(&v, `assert(LOOPS >= 1, "DidLoop did not fire")`, "loop_events")

	// A non-looped track stops at its end and degrades through Stopped/Ended.
	run(
		&v,
		`
local track = TRACK
track.Looped = false
track.TimePosition = track.Length - 0.01
ANIMATOR:StepAnimations(0.1)
assert(track.IsPlaying == false, "finished track still reports playing")
assert(track.TimePosition <= track.Length, "finished track left its length")
`,
		"end_step",
	)
	engine_runtime.Environment_Update_Step(&env, &v, 1.0 / 60.0)
	run(
		&v,
		`assert(STOPPED >= 1, "Stopped did not fire")
assert(ENDED >= 1, "Ended did not fire")`,
		"end_events",
	)
	run(&v, `TRACK:Stop(0); assert(TRACK.IsPlaying == false)`, "stop_idempotent")

	// A dead track must not keep reporting its cached live state, and methods
	// that need a live rig must fail instead of touching freed native data.
	run(
		&v,
		`
local track = TRACK
track:Play(0, 1, 0)
assert(track.IsPlaying, "track did not restart")
assert(track.WeightCurrent == 1, "restart weight")
ANIMATOR:Destroy()
assert(track.IsPlaying == false, "destroyed animator left a live track")
assert(track.WeightCurrent == 0, "destroyed track kept its cached weight")
local played, err = pcall(function() track:Play() end)
assert(not played, "Play on a dead track must raise")
assert(pcall(function() track:Stop(0); track:AdjustSpeed(1); track:AdjustWeight(1, 0) end), "death should not crash Stop/Adjust")
`,
		"track_death",
	)

	// A fresh Animator parented directly to the MeshPart must discover the rig
	// and control it again after the previous animator was destroyed.
	run(
		&v,
		`
local rig = workspace.BoxingRig
local anim = Instance.new("Animation")
anim.ClipName = FIRST_CLIP
anim.Looped = true
ANIM = anim
local animator = Instance.new("Animator")
animator.Parent = rig
ANIMATOR2 = animator
local track = animator:LoadAnimation(anim)
TRACK2 = track
assert(animator.MeshPart == rig, "replacement Animator did not discover the rig")
assert(track:GetMarkerReachedSignal("phase") ~= nil, "marker signal")
assert(not pcall(function() return track:GetTimeOfKeyframe("missing") end), "missing keyframe must raise")
track:SetParameter("x", 4)
assert(track:GetParameter("x") == 4, "parameter round-trip")
track:SetParameter("x", nil)
assert(track:GetParameter("x") == nil, "parameter removal")
track:Play(0, 1, 0)
assert(track.IsPlaying and track.WeightCurrent == 1, "replacement track playback")

local other = Instance.new("Animator", rig)
local ok_second = pcall(function() return other:LoadAnimation(anim) end)
assert(not ok_second, "two Animators must not drive one rig")
other:Destroy()
local ok_missing = pcall(function() return animator:LoadAnimation(anim) end)
assert(ok_missing, "replacement animator should load its clip")
local bad = Instance.new("Animation")
bad.ClipName = "ThisClipDoesNotExist"
assert(not pcall(function() return animator:LoadAnimation(bad) end), "missing clip must raise")
assert(not pcall(function() return animator:LoadAnimation(rig) end), "non-Animation must raise")

-- AnimationId is the asset-facing clip source and must round-trip as a
-- property. Loading it is covered by the asset round-trip test; importing a
-- second full mesh here would stall the visible swapchain.
local by_asset = Instance.new("Animation")
by_asset.AnimationId = rig.MeshId
by_asset.ClipName = FIRST_CLIP
assert(by_asset.AnimationId == rig.MeshId, "AnimationId getter")
`,
		"replacement_animator",
	)

	if visual {
		// Manual stepping keeps the test deterministic headlessly; the visible
		// mode advances the same track one frame at a time. Do not read the
		// 480x480 surface back here: that is 230k pixel calls per frame and was
		// the reason watching this test felt sluggish.
		run(&v, `TRACK2:AdjustSpeed(1)`, "visual_speed")
		visual_start := time.tick_now()
		for frame in 0 ..< 240 {
			frame_start := time.tick_now()
			run(&v, `ANIMATOR2:StepAnimations(1.0 / 60.0)`, "visual_step")
			engine_runtime.Environment_Update_Step(&env, &v, 1.0 / 60.0)
			capture_frame(&env, &v, ctx, &view, compositor, scratch, "", false)
			sdl.PumpEvents()
			if elapsed := time.tick_since(frame_start); elapsed < 16 * time.Millisecond {
				time.sleep(16 * time.Millisecond - elapsed)
			}
		}
		fmt.println(
			"ANIMATION_RIG_VISUAL_SECONDS",
			f64(time.tick_since(visual_start)) / f64(time.Second),
		)
	}

	fmt.println("ANIMATION_TRACK_RIG_SMOKE_PASSED")
	if visual {
		// The visible swapchain teardown can block waiting for a present that no
		// event loop will consume after the test. The OS reclaims these resources
		// when the visual smoke process exits.
		os.exit(0)
	}
}
