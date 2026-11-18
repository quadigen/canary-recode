package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"
import "core:strings"

AnimationTrack_Class := Class_Info {
	name   = "AnimationTrack",
	parent = &Instance_Class,
}
AnimationMarkerBinding :: struct {
	name:   string,
	signal: ^signals.Signal,
}
AnimationTrack :: struct {
	using object:     Object,
	owner:            ^Animator,
	animation:        ^Object,
	native_track:     ^kineffi.KineFilamentAnimationTrack,
	clip_index:       i32,
	cached_state:     kineffi.KineAnimationTrackState,
	stopped:          ^signals.Signal,
	ended:            ^signals.Signal,
	did_loop:         ^signals.Signal,
	keyframe_reached: ^signals.Signal,
	markers:          [dynamic]AnimationMarkerBinding,
	parameters:       map[string]i32, // retained Luau VM references; supports any Variant
}

animation_track_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	t := new(AnimationTrack)
	t.object = Object_Init(&AnimationTrack_Class, "AnimationTrack")
	return &t.object
}
animation_track_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	t := cast(^AnimationTrack)object
	if Animation_Track_Valid(t) {
		kineffi.Kine_Filament_AnimationTrackDestroy(t.native_track)
	}
	if t.owner != nil {
		for child, i in t.owner.tracks {
			if child == t {ordered_remove(&t.owner.tracks, i); break}
		}
	}
	t.native_track = nil
	t.owner = nil
	Animation_Signal_Destroy(&t.stopped)
	Animation_Signal_Destroy(&t.ended)
	Animation_Signal_Destroy(&t.did_loop)
	Animation_Signal_Destroy(&t.keyframe_reached)
	for item in t.markers {
		if item.signal != nil &&
		   t.object.signal_registry != nil &&
		   t.object.signal_registry.signal_registry != nil {signals.Destroy(item.signal)}
		delete(item.name)
	}
	delete(t.markers)
	if t.parameters != nil {
		for name, ref in t.parameters {
			if object.signal_registry != nil && object.signal_registry.vm_state != nil && ref > 0 {
				vm.ReleaseValue(object.signal_registry.vm_state.L, ref)
			}
			delete(name)
		}
		delete(t.parameters)
	}
	Object_Destroy(object)
	free(t)
}
Animation_Track_Snapshot :: proc(t: ^AnimationTrack) -> kineffi.KineAnimationTrackState {
	if !Animation_Track_Valid(t) {
		if t != nil {t.cached_state = {}}
		return {}
	}
	_ = kineffi.Kine_Filament_AnimationTrackGetState(t.native_track, &t.cached_state)
	return t.cached_state
}
animation_track_get :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	t := cast(^AnimationTrack)object
	switch key {
	case "Animation":
		if Animation_Is_Live(
			object.signal_registry,
			"Animation",
			t.animation,
		) {Push_Object(L, t.animation)} else {vm.PushNil(L)}
	case "IsPlaying":
		vm.PushBoolean(L, Animation_Track_Snapshot(t).isPlaying != 0)
	case "Length":
		vm.PushNumber(L, f64(Animation_Track_Snapshot(t).length))
	case "Looped":
		vm.PushBoolean(L, Animation_Track_Snapshot(t).looped != 0)
	case "Priority":
		Animation_Push_Priority(L, enum_registry, Animation_Track_Snapshot(t).priority)
	case "Speed":
		vm.PushNumber(L, f64(Animation_Track_Snapshot(t).speed))
	case "TimePosition":
		vm.PushNumber(L, f64(Animation_Track_Snapshot(t).timePosition))
	case "WeightCurrent":
		vm.PushNumber(L, f64(Animation_Track_Snapshot(t).weightCurrent))
	case "WeightTarget":
		vm.PushNumber(L, f64(Animation_Track_Snapshot(t).weightTarget))
	case "Stopped":
		signal := Animation_Signal(object, &t.stopped)
		if signal == nil {return false}
		signals.Push(L, signal)
	case "Ended":
		signal := Animation_Signal(object, &t.ended)
		if signal == nil {return false}
		signals.Push(L, signal)
	case "DidLoop":
		signal := Animation_Signal(object, &t.did_loop)
		if signal == nil {return false}
		signals.Push(L, signal)
	case "KeyframeReached":
		signal := Animation_Signal(object, &t.keyframe_reached)
		if signal == nil {return false}
		signals.Push(L, signal)
	case:
		return false
	}
	return true
}
animation_track_set :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	t := cast(^AnimationTrack)object
	if !Animation_Track_Valid(t) {return false}
	switch key {
	case "Looped":
		return kineffi.Kine_Filament_AnimationTrackSetLooped(
			t.native_track,
			vm.ArgBoolean(L, index),
		)
	case "Priority":
		return kineffi.Kine_Filament_AnimationTrackSetPriority(
			t.native_track,
			Animation_Arg_Priority(L, enum_registry, index),
		)
	case "TimePosition":
		return kineffi.Kine_Filament_AnimationTrackSetTimePosition(
			t.native_track,
			f32(vm.ArgNumber(L, index)),
		)
	case:
		return false
	}
}
animation_track_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	t := cast(^AnimationTrack)object
	switch method {
	case "Play":
		if !Animation_Track_Valid(
			t,
		) {return vm.RaiseError(L, "AnimationTrack is no longer attached to a rig"), true}
		fade := f32(vm.ArgOptionalNumber(L, 2, 0.1))
		weight := f32(vm.ArgOptionalNumber(L, 3, 1))
		speed := f32(vm.ArgOptionalNumber(L, 4, 1))
		if !kineffi.Kine_Filament_AnimationTrackPlay(t.native_track, fade, weight, speed) {
			return vm.RaiseError(L, "AnimationTrack:Play received invalid parameters"), true
		}
		Animation_Signal_Fire_Object(L, t.owner.animation_played, object)
		container := t.owner.object.parent
		if container != nil &&
		   !container.destroyed &&
		   Is_A_Class(container, &AnimationController_Class) {
			Animation_Signal_Fire_Object(
				L,
				(cast(^AnimationController)container).animation_played,
				object,
			)
		} else if container != nil &&
		   !container.destroyed &&
		   Is_A_Class(container, &Humanoid_Class) {
			Animation_Signal_Fire_Object(L, (cast(^Humanoid)container).animation_played, object)
		}
		Render_3D_Mark_Dirty()
		return 0, true
	case "Stop":
		if !Animation_Track_Valid(t) {return 0, true}
		_ = kineffi.Kine_Filament_AnimationTrackStop(
			t.native_track,
			f32(vm.ArgOptionalNumber(L, 2, 0.1)),
		)
		Render_3D_Mark_Dirty()
		return 0, true
	case "AdjustSpeed":
		if !Animation_Track_Valid(t) {return 0, true}
		_ = kineffi.Kine_Filament_AnimationTrackAdjustSpeed(
			t.native_track,
			f32(vm.ArgOptionalNumber(L, 2, 1)),
		)
		return 0, true
	case "AdjustWeight":
		if !Animation_Track_Valid(t) {return 0, true}
		weight := f32(vm.ArgOptionalNumber(L, 2, 1))
		fade := f32(vm.ArgOptionalNumber(L, 3, 0.1))
		_ = kineffi.Kine_Filament_AnimationTrackAdjustWeight(t.native_track, weight, fade)
		Render_3D_Mark_Dirty()
		return 0, true
	case "GetMarkerReachedSignal":
		name := vm.ArgString(L, 2)
		for item in t.markers {
			if item.name == name {signals.Push(L, item.signal); return 1, true}
		}
		if object.signal_registry == nil ||
		   object.signal_registry.signal_registry ==
			   nil {return vm.RaiseError(L, "signals unavailable"), true}
		signal := signals.Create(object.signal_registry.signal_registry)
		append(&t.markers, AnimationMarkerBinding{name = strings.clone(name), signal = signal})
		signals.Push(L, signal)
		return 1, true
	case "GetTimeOfKeyframe":
		if !Animation_Track_Valid(t) {return vm.RaiseError(L, "track is not attached"), true}
		name := strings.clone_to_cstring(vm.ArgString(L, 2))
		seconds := kineffi.Kine_Filament_MeshGetKeyframeTime(
			t.owner.native_mesh,
			t.clip_index,
			name,
		)
		delete(name)
		if seconds < 0 {return vm.RaiseError(L, "keyframe name not found"), true}
		vm.PushNumber(L, f64(seconds))
		return 1, true
	case "GetParameter":
		if t.parameters == nil {vm.PushNil(L); return 1, true}
		ref, found := t.parameters[vm.ArgString(L, 2)]
		if found && ref > 0 {vm.PushRegistryReference(L, ref)} else {vm.PushNil(L)}
		return 1, true
	case "SetParameter":
		if t.parameters == nil {t.parameters = make(map[string]i32)}
		name := vm.ArgString(L, 2)
		old_ref, found := t.parameters[name]
		if found && old_ref > 0 {vm.ReleaseValue(L, old_ref)}
		if vm.IsNil(L, 3) {
			owned_name: string
			for stored_name in t.parameters {
				if stored_name == name {owned_name = stored_name; break}
			}
			delete_key(&t.parameters, name)
			delete(owned_name)
		} else {
			vm.PushValue(L, 3)
			ref := vm.RetainValue(L)
			vm.Pop(L)
			if found {t.parameters[name] = ref} else {t.parameters[strings.clone(name)] = ref}
		}
		return 0, true
	case "GetParameterDefaults":
		vm.NewTable(L, 0)
		return 1, true
	}
	return 0, false
}

animation_track_step :: proc(object: ^Object, ctx: ^Class_Step_Context) {
	t := cast(^AnimationTrack)object
	if !Animation_Track_Valid(t) {return}
	events: kineffi.KineAnimationTrackEvents
	if kineffi.Kine_Filament_AnimationTrackConsumeEvents(t.native_track, &events) {
		for i in 0 ..< min(32, int(events.didLoop)) {Animation_Signal_Fire(ctx.L, t.did_loop)}
		for i in 0 ..< min(32, int(events.stopped)) {Animation_Signal_Fire(ctx.L, t.stopped)}
		for i in 0 ..< min(32, int(events.ended)) {Animation_Signal_Fire(ctx.L, t.ended)}
	}
	marker: kineffi.KineAnimationEvent
	count := 0
	for count < 1024 && kineffi.Kine_Filament_AnimationTrackPopEvent(t.native_track, &marker) {
		count += 1
		name := string(cstring(&marker.name[0]))
		if marker.kind == 1 {
			Animation_Signal_Fire_String(ctx.L, t.keyframe_reached, name)
		} else if marker.kind == 2 {
			for item in t.markers {
				if item.name == name {
					Animation_Signal_Fire_String(
						ctx.L,
						item.signal,
						string(cstring(&marker.parameter[0])),
					)
				}
			}
		}
	}
}
Register_AnimationTrack :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&AnimationTrack_Class,
		animation_track_construct,
		animation_track_destroy,
		creatable = false,
		get = animation_track_get,
		set = animation_track_set,
		namecall = animation_track_namecall,
		_step = animation_track_step,
		_step_phase = .Update,
		properties = []string {
			"Animation",
			"IsPlaying",
			"Length",
			"Looped",
			"Priority",
			"Speed",
			"TimePosition",
			"WeightCurrent",
			"WeightTarget",
		},
		methods = []string {
			"Play",
			"Stop",
			"AdjustSpeed",
			"AdjustWeight",
			"GetMarkerReachedSignal",
			"GetTimeOfKeyframe",
			"GetParameter",
			"SetParameter",
			"GetParameterDefaults",
		},
		events = []string{"Stopped", "Ended", "DidLoop", "KeyframeReached"},
	)
}
