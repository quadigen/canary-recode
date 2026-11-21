package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

Animator_Class := Class_Info {
	name   = "Animator",
	parent = &Instance_Class,
}
Animator :: struct {
	using object:       Object,
	mesh_part:          ^Object,
	native_animator:    ^kineffi.KineFilamentAnimator,
	native_mesh:        ^kineffi.KineFilamentMesh,
	native_context:     ^kineffi.KineFilamentContext,
	tracks:             [dynamic]^AnimationTrack,
	animation_played:   ^signals.Signal,
	prefer_lod_enabled: bool,
}

animator_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	a := new(Animator)
	a.object = Object_Init(&Animator_Class, "Animator")
	a.prefer_lod_enabled = true
	return &a.object
}
Animation_Animator_Release :: proc(a: ^Animator) {
	if a == nil {return}
	live := Animation_Native_Live(a)
	native := a.native_animator
	Animation_Invalidate_Tracks(a)
	if live && native != nil {kineffi.Kine_Filament_AnimatorDestroy(native)}
}
animator_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	a := cast(^Animator)object
	Animation_Animator_Release(a)
	for t in a.tracks {
		if t != nil {
			t.owner = nil
			t.native_track = nil
			t.cached_state = {}
		}
	}
	delete(a.tracks)
	Animation_Signal_Destroy(&a.animation_played)
	Object_Destroy(object)
	free(a)
}
animator_clone :: proc(source, target: ^Object) {
	(cast(^Animator)target).prefer_lod_enabled = (cast(^Animator)source).prefer_lod_enabled
}
animator_get :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
) -> bool {
	a := cast(^Animator)object
	switch key {
	case "MeshPart":
		mesh := Animation_Resolve_Mesh(a)
		if mesh == nil {vm.PushNil(L)} else {Push_Object(L, &mesh.object)}
	case "AnimationPlayed":
		signal := Animation_Signal(object, &a.animation_played)
		if signal == nil {return false}
		signals.Push(L, signal)
	case "EvaluationThrottled":
		vm.PushBoolean(L, false)
	case "PreferLodEnabled":
		vm.PushBoolean(L, a.prefer_lod_enabled)
	case:
		return false
	}
	return true
}
animator_set :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	a := cast(^Animator)object
	switch key {
	case "MeshPart":
		target := object_from_argument(L, index)
		if !vm.IsNil(L, index) &&
		   (target == nil || !Is_A_Class(target, &MeshPart_Class)) {return false}
		Animation_Animator_Release(a)
		a.mesh_part = target
	case "PreferLodEnabled":
		a.prefer_lod_enabled = vm.ArgBoolean(L, index)
	case:
		return false
	}
	return true
}

Animation_Load_Track :: proc(L: ^vm.State, a: ^Animator, source: ^Object) -> (i32, bool) {
	if source == nil || !Is_A_Class(source, &Animation_Class) {
		return vm.RaiseError(L, "Animator:LoadAnimation expects an Animation Instance"), true
	}
	if !Animation_Animator_Ready(a) {
		return vm.RaiseError(
				L,
				"Animator has no ready rigged MeshPart (or mesh is controlled by another Animator)",
			),
			true
	}
	anim := cast(^Animation)source
	clip_index := Animation_Resolve_Clip(a.native_mesh, a.native_context, anim)
	if clip_index < 0 {
		return vm.RaiseError(L, "animation clip not found or source KeyframeSequence is empty"),
			true
	}
	native := kineffi.Kine_Filament_AnimatorLoadAnimation(a.native_animator, clip_index)
	if native == nil {return vm.RaiseError(L, "failed to load native animation track"), true}
	registry := a.object.signal_registry
	if registry == nil || registry.vm_state == nil {
		kineffi.Kine_Filament_AnimationTrackDestroy(native)
		return vm.RaiseError(L, "class registry is not initialized"), true
	}
	object, ok := Push_New(registry, registry.vm_state, "AnimationTrack", false)
	if !ok {
		kineffi.Kine_Filament_AnimationTrackDestroy(native)
		return vm.RaiseError(L, "AnimationTrack class not registered"), true
	}
	vm.Pop(registry.vm_state.L)
	track := cast(^AnimationTrack)object
	track.owner = a
	track.animation = source
	track.native_track = native
	track.clip_index = clip_index
	track.cached_state = {}
	if Animation_Is_Live(registry, "KeyframeSequence", anim.sequence) {
		seq := cast(^KeyframeSequence)anim.sequence
		_ = kineffi.Kine_Filament_AnimationTrackSetLooped(native, seq.looped)
		_ = kineffi.Kine_Filament_AnimationTrackSetPriority(native, seq.priority)
	} else {
		_ = kineffi.Kine_Filament_AnimationTrackSetLooped(native, anim.looped)
		_ = kineffi.Kine_Filament_AnimationTrackSetPriority(native, anim.priority)
	}
	append(&a.tracks, track)
	Push_Object(L, object)
	return 1, true
}
animator_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enums: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	a := cast(^Animator)object
	switch method {
	case "LoadAnimation":
		return Animation_Load_Track(L, a, object_from_argument(L, 2))
	case "GetTrackByAnimationId":
		id := vm.ArgString(L, 2)
		for t in a.tracks {
			if t == nil || t.object.destroyed || t.native_track == nil {continue}
			if Animation_Is_Live(object.signal_registry, "Animation", t.animation) &&
			   (cast(^Animation)t.animation).animation_id == id {
				Push_Object(L, &t.object)
				return 1, true
			}
		}
		vm.PushNil(L)
		return 1, true
	case "GetPlayingAnimationTracks":
		Animation_Push_Track_Array(L, a)
		return 1, true
	case "StepAnimations":
		if !Animation_Animator_Ready(
			a,
		) {return vm.RaiseError(L, "Animator has no ready mesh"), true}
		dt := f32(vm.ArgNumber(L, 2))
		kineffi.Kine_Filament_SetAnimationAutoStep(a.native_context, false)
		if !kineffi.Kine_Filament_AnimatorStep(
			a.native_animator,
			dt,
		) {return vm.RaiseError(L, "animation stepping failed"), true}
		Render_3D_Mark_Dirty()
		return 0, true
	}
	return 0, false
}
animator_step :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	a := cast(^Animator)object
	if !Animation_Animator_Valid(a) {return}
	for t in a.tracks {
		if t == nil || t.object.destroyed || t.native_track == nil {continue}
		state: kineffi.KineAnimationTrackState
		if kineffi.Kine_Filament_AnimationTrackGetState(t.native_track, &state) &&
		   state.active != 0 {
			Render_3D_Mark_Dirty()
			break
		}
	}
}
Register_Animator :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Animator_Class,
		animator_construct,
		animator_destroy,
		get = animator_get,
		set = animator_set,
		namecall = animator_namecall,
		_step = animator_step,
		_step_phase = .Update,
		clone = animator_clone,
		properties = []string{"MeshPart", "EvaluationThrottled", "PreferLodEnabled"},
		methods = []string {
			"LoadAnimation",
			"GetPlayingAnimationTracks",
			"GetTrackByAnimationId",
			"StepAnimations",
		},
		events = []string{"AnimationPlayed"},
	)
}
