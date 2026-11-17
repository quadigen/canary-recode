package animation

import kineffi "../bindings"

Animator :: struct {
	handle: ^kineffi.KineFilamentAnimator,
}

Track :: struct {
	handle: ^kineffi.KineFilamentAnimationTrack,
}

create_animator :: proc(
	ctx: ^kineffi.KineFilamentContext,
	mesh: ^kineffi.KineFilamentMesh,
) -> Animator {
	return Animator{handle = kineffi.Kine_Filament_AnimatorCreate(ctx, mesh)}
}

destroy_animator :: proc(animator: ^Animator) {
	if animator == nil || animator.handle == nil {return}
	kineffi.Kine_Filament_AnimatorDestroy(animator.handle)
	animator.handle = nil
}

load_animation :: proc(animator: Animator, animation_index: i32) -> Track {
	if animator.handle == nil {return {}}
	return Track {
		handle = kineffi.Kine_Filament_AnimatorLoadAnimation(animator.handle, animation_index),
	}
}

destroy_track :: proc(track: ^Track) {
	if track == nil || track.handle == nil {return}
	kineffi.Kine_Filament_AnimationTrackDestroy(track.handle)
	track.handle = nil
}

play :: proc(track: Track, fade_time: f32 = 0.1, weight: f32 = 1, speed: f32 = 1) -> bool {
	return(
		track.handle != nil &&
		kineffi.Kine_Filament_AnimationTrackPlay(track.handle, fade_time, weight, speed) \
	)
}

stop :: proc(track: Track, fade_time: f32 = 0.1) -> bool {
	return track.handle != nil && kineffi.Kine_Filament_AnimationTrackStop(track.handle, fade_time)
}

adjust_weight :: proc(track: Track, weight: f32 = 1, fade_time: f32 = 0.1) -> bool {
	return(
		track.handle != nil &&
		kineffi.Kine_Filament_AnimationTrackAdjustWeight(track.handle, weight, fade_time) \
	)
}

adjust_speed :: proc(track: Track, speed: f32 = 1) -> bool {
	return(
		track.handle != nil &&
		kineffi.Kine_Filament_AnimationTrackAdjustSpeed(track.handle, speed) \
	)
}

set_time :: proc(track: Track, position_seconds: f32) -> bool {
	return(
		track.handle != nil &&
		kineffi.Kine_Filament_AnimationTrackSetTimePosition(track.handle, position_seconds) \
	)
}

set_looped :: proc(track: Track, looped: bool) -> bool {
	return(
		track.handle != nil &&
		kineffi.Kine_Filament_AnimationTrackSetLooped(track.handle, looped) \
	)
}

set_priority :: proc(track: Track, priority: i32) -> bool {
	return(
		track.handle != nil &&
		kineffi.Kine_Filament_AnimationTrackSetPriority(track.handle, priority) \
	)
}

get_state :: proc(track: Track) -> (kineffi.KineAnimationTrackState, bool) {
	state: kineffi.KineAnimationTrackState
	if track.handle == nil {return state, false}
	ok := kineffi.Kine_Filament_AnimationTrackGetState(track.handle, &state)
	return state, ok
}

consume_events :: proc(track: Track) -> (kineffi.KineAnimationTrackEvents, bool) {
	events: kineffi.KineAnimationTrackEvents
	if track.handle == nil {return events, false}
	ok := kineffi.Kine_Filament_AnimationTrackConsumeEvents(track.handle, &events)
	return events, ok
}

step :: proc(animator: Animator, delta_time: f32) -> bool {
	return(
		animator.handle != nil &&
		kineffi.Kine_Filament_AnimatorStep(animator.handle, delta_time) \
	)
}

set_automatic_step :: proc(ctx: ^kineffi.KineFilamentContext, enabled: bool) {
	kineffi.Kine_Filament_SetAnimationAutoStep(ctx, enabled)
}
