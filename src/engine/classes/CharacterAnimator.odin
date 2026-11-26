package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:math"
import "core:strings"

CharacterAnimator_Class := Class_Info {
	name   = "CharacterAnimator",
	parent = &Instance_Class,
}
CHARACTER_ANIMATION_STATES := [7]string{"Idle", "Walk", "Run", "Sprint", "Jump", "Fall", "Land"}
CHARACTER_ANIMATION_PROPERTIES :: [7]string {
	"IdleClip",
	"WalkClip",
	"RunClip",
	"SprintClip",
	"JumpClip",
	"FallClip",
	"LandClip",
}


CharacterAnimator :: struct {
	using object:                        Object,
	enabled:                             bool,
	rig_name:                            string,
	clips:                               [7]string,
	fade_time:                           f32,
	walk_speed, run_speed, sprint_speed: f32,
	status, state:                       string,
	horizontal_speed:                    f32,
	native_animator:                     ^kineffi.KineFilamentAnimator,
	native_mesh:                         ^kineffi.KineFilamentMesh,
	native_context:                      ^kineffi.KineFilamentContext,
	tracks:                              [7]^kineffi.KineFilamentAnimationTrack,
	lengths:                             [7]f32,
	weights:                             [7]f32,
	shot_time, shot_speed:               [7]f32,
	last_position:                       datatypes.Vector3,
	position_valid, was_grounded:        bool,
	land_time:                           f32,
	current_state:                       int,
}

character_animator_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	a := new(CharacterAnimator)
	a.object = Object_Init(&CharacterAnimator_Class, "CharacterAnimator")
	a.fade_time = 0.14
	a.walk_speed = 5.5; a.run_speed = 24; a.sprint_speed = 36
	a.status = "Disabled"; a.current_state = -1
	for name, i in CHARACTER_ANIMATION_STATES {a.clips[i] = strings.clone(strings.concatenate({"Locomotion_", name}, context.temp_allocator))}
	return &a.object
}

CharacterAnimator_Release :: proc(a: ^CharacterAnimator) {
	if a == nil {return}


	live := false
	if a.native_animator != nil && a.signal_registry != nil {
		for o in Find_Class(a.signal_registry, "MeshPart").instances {
			p := cast(^MeshPart)o
			if p != nil &&
			   p.native_mesh == a.native_mesh &&
			   p.native_context == a.native_context {live = true; break}
		}
	}
	if live {kineffi.Kine_Filament_AnimatorDestroy(a.native_animator)}
	a.native_animator = nil; a.native_mesh = nil; a.native_context = nil
	a.tracks =
		{}; a.lengths = {}; a.weights = {}; a.shot_time = {}; a.shot_speed = {}; a.position_valid = false
	a.current_state = -1; a.state = ""; a.land_time = 0
}

CharacterAnimator_Invalidate_Mesh :: proc(part: ^MeshPart) {
	if part == nil || part.signal_registry == nil {return}
	descriptor := Find_Class(part.signal_registry, "CharacterAnimator")
	if descriptor == nil {return}
	for o in descriptor.instances {
		a := cast(^CharacterAnimator)o
		if a != nil &&
		   a.native_mesh == part.native_mesh &&
		   a.native_context == part.native_context {CharacterAnimator_Release(a)}
	}
}

character_animator_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	a := cast(^CharacterAnimator)object
	CharacterAnimator_Release(a)
	delete(a.rig_name)
	for clip in a.clips {delete(clip)}
	Object_Destroy(object); free(a)
}

character_animator_clone :: proc(source, destination: ^Object) {
	s, d := cast(^CharacterAnimator)source, cast(^CharacterAnimator)destination
	d.enabled = s.enabled; d.rig_name = strings.clone(s.rig_name)
	d.fade_time =
		s.fade_time; d.walk_speed = s.walk_speed; d.run_speed = s.run_speed; d.sprint_speed = s.sprint_speed
	for clip, i in s.clips {delete(d.clips[i]); d.clips[i] = strings.clone(clip)}
}

character_animator_get :: proc(
	L: ^vm.State,
	o: ^Object,
	t: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
) -> bool {
	a := cast(^CharacterAnimator)o
	switch key {
	case "Enabled":
		vm.PushBoolean(L, a.enabled)
	case "RigMeshName":
		vm.PushString(L, a.rig_name)
	case "FadeTime":
		vm.PushNumber(L, f64(a.fade_time))
	case "WalkAnimationSpeed":
		vm.PushNumber(L, f64(a.walk_speed))
	case "RunAnimationSpeed":
		vm.PushNumber(L, f64(a.run_speed))
	case "SprintAnimationSpeed":
		vm.PushNumber(L, f64(a.sprint_speed))
	case "Status":
		vm.PushString(L, a.status)
	case "State":
		vm.PushString(L, a.state)
	case "HorizontalSpeed":
		vm.PushNumber(L, f64(a.horizontal_speed))
	case:
		for property, i in CHARACTER_ANIMATION_PROPERTIES {
			if key == property {vm.PushString(L, a.clips[i]); return true}
		}
		return false
	}
	return true
}

character_animator_set :: proc(
	L: ^vm.State,
	o: ^Object,
	t: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	a := cast(^CharacterAnimator)o
	switch key {
	case "Enabled":
		a.enabled = vm.ArgBoolean(L, index)
		if !a.enabled {CharacterAnimator_Release(a); a.status = "Disabled"}
	case "RigMeshName":
		CharacterAnimator_Release(a); delete(a.rig_name)
		a.rig_name = strings.clone(vm.ArgString(L, index))
	case "FadeTime", "WalkAnimationSpeed", "RunAnimationSpeed", "SprintAnimationSpeed":
		value := f32(vm.ArgNumber(L, index))
		if math.is_nan(value) || math.is_inf(value) {return false}
		switch key {
		case "FadeTime":
			a.fade_time = clamp(value, 0, 2)
		case "WalkAnimationSpeed":
			a.walk_speed = clamp(value, 0.1, 200)
		case "RunAnimationSpeed":
			a.run_speed = clamp(value, 0.1, 200)
		case "SprintAnimationSpeed":
			a.sprint_speed = clamp(value, 0.1, 200)
		}
	case:
		for property, i in CHARACTER_ANIMATION_PROPERTIES {
			if key == property {
				CharacterAnimator_Release(
					a,
				); delete(a.clips[i]); a.clips[i] = strings.clone(vm.ArgString(L, index)); return true
			}
		}
		return false
	}
	return true
}

character_animator_ready :: proc(a: ^CharacterAnimator, mesh: ^MeshPart) -> bool {
	if a.native_animator != nil &&
	   (a.native_mesh != mesh.native_mesh ||
			   a.native_context != mesh.native_context) {CharacterAnimator_Release(a)}
	if a.native_animator != nil {return true}
	count := kineffi.Kine_Filament_GetMeshAnimationCount(mesh.native_mesh)
	indices: [7]i32
	for &index in indices {index = -1}
	for i: i32 = 0; i < count; i += 1 {
		name := kineffi.Kine_Filament_GetMeshAnimationName(mesh.native_mesh, i)
		if name == nil {continue}
		for clip, j in a.clips {if clip != "" && string(name) == clip {indices[j] = i}}
	}
	if indices[0] < 0 ||
	   indices[1] < 0 ||
	   indices[2] < 0 {a.status = "MissingLocomotionClips"; return false}
	a.native_animator = kineffi.Kine_Filament_AnimatorCreate(mesh.native_context, mesh.native_mesh)
	if a.native_animator == nil {a.status = "AnimatorBusy"; return false}
	a.native_mesh = mesh.native_mesh; a.native_context = mesh.native_context
	for index, i in indices {
		if index < 0 {continue}
		a.tracks[i] = kineffi.Kine_Filament_AnimatorLoadAnimation(a.native_animator, index)
		a.lengths[i] = kineffi.Kine_Filament_GetMeshAnimationDuration(mesh.native_mesh, index)
		_ = kineffi.Kine_Filament_AnimationTrackSetLooped(a.tracks[i], i != 4 && i != 6)
		if i < 4 ||
		   i == 5 {_ = kineffi.Kine_Filament_AnimationTrackPlay(a.tracks[i], 0, i == 0 ? 1 : 0, 1)}
	}
	a.weights[0] = 1
	return true
}

character_animator_step :: proc(o: ^Object, ctx: ^Class_Step_Context) {
	a := cast(^CharacterAnimator)o
	if !a.enabled {if a.native_animator != nil {CharacterAnimator_Release(a)}; a.status = "Disabled"; return}
	if a.parent == nil ||
	   !Is_A_Class(
			   a.parent,
			   &CharacterController_Class,
		   ) {a.status = "NoCharacterController"; return}
	cc := cast(^CharacterController)a.parent
	root := CharacterController_Root(cc)
	if root == nil {a.status = "NoRootPart"; return}
	candidate := Animation_Search_Mesh(cc.parent)
	if a.rig_name != "" {
		named := CharacterPhysicsSolver_Find_Named_Rig(cc.parent, a.rig_name)
		candidate = nil
		if named != nil && Is_A_Class(named, &MeshPart_Class) {candidate = cast(^MeshPart)named}
	}
	if candidate == nil ||
	   candidate.native_mesh == nil ||
	   candidate.native_context ==
		   nil {CharacterAnimator_Release(a); a.status = "WaitingForMesh"; return}
	if !character_animator_ready(a, candidate) {return}
	dt := clamp(ctx.delta_time, 0.0001, 0.1)
	position := datatypes.CFrame_Position(root.cframe)
	speed: f64
	if a.position_valid {
		delta := datatypes.Vec3_Subtract(position, a.last_position)
		distance := math.sqrt(delta.x * delta.x + delta.z * delta.z)
		if distance < 12 {speed = distance / f64(dt)}
	}
	a.last_position = position; a.position_valid = true
	a.horizontal_speed += f32((speed - f64(a.horizontal_speed)) * (1 - math.exp(-f64(dt) * 14)))
	gd := cast(^GroundDetector)CharacterController_Find(cc, "GroundDetector")
	grounded := gd != nil && gd.grounded
	if grounded && !a.was_grounded && a.current_state >= 0 {a.land_time = 0.2}
	a.was_grounded = grounded
	target: [7]f32
	state := 0
	if !grounded {
		state = cc.vertical_speed > 1 ? 4 : 5
		if a.tracks[state] == nil {state = 0}
		target[state] = 1
		a.land_time = 0
	} else if a.land_time > 0 && a.tracks[6] != nil {
		a.land_time = max(0, a.land_time - dt); state = 6; target[6] = 1
	} else {
		v := a.horizontal_speed
		moving := clamp(v / 0.8, f32(0), f32(1))
		run := clamp(
			(v - a.walk_speed * 1.3) / max(a.run_speed * 0.6 - a.walk_speed * 1.3, 1),
			f32(0),
			f32(1),
		)
		sprint :=
			a.tracks[3] != nil ? clamp((v - a.run_speed * 0.95) / max(a.sprint_speed * 0.8 - a.run_speed * 0.95, 1), f32(0), f32(1)) : 0
		target[0] = 1 - moving; target[1] = moving * (1 - run)
		target[2] = moving * run * (1 - sprint); target[3] = moving * run * sprint
		for w, i in target {if w > target[state] {state = i}}
		_ = kineffi.Kine_Filament_AnimationTrackAdjustSpeed(
			a.tracks[1],
			clamp(v / a.walk_speed, 0.15, 2.5),
		)
		_ = kineffi.Kine_Filament_AnimationTrackAdjustSpeed(
			a.tracks[2],
			clamp(v / a.run_speed, 0.15, 2.5),
		)
		if a.tracks[3] !=
		   nil {_ = kineffi.Kine_Filament_AnimationTrackAdjustSpeed(a.tracks[3], clamp(v / a.sprint_speed, 0.15, 2.5))}
	}
	if state != a.current_state {
		if state == 4 || state == 6 {
			seconds := state == 4 ? max(cc.vertical_speed / max(cc.gravity, 1) + 0.08, 0.18) : 0.24
			_ = kineffi.Kine_Filament_AnimationTrackPlay(a.tracks[state], 0, 0, 0)
			a.shot_time[state] = 0; a.shot_speed[state] = a.lengths[state] / seconds
		}
		a.current_state = state; a.state = CHARACTER_ANIMATION_STATES[state]
	}

	reference := 0
	for w, i in a.weights {if i < 4 && w > a.weights[reference] {reference = i}}
	snapshot: kineffi.KineAnimationTrackState
	_ = kineffi.Kine_Filament_AnimationTrackGetState(a.tracks[reference], &snapshot)
	for w, i in target {
		if a.tracks[i] == nil {continue}
		if i > 0 && i < 4 && w > 0.01 && a.weights[i] <= 0.01 && a.lengths[reference] > 0 {
			_ = kineffi.Kine_Filament_AnimationTrackSetTimePosition(
				a.tracks[i],
				snapshot.timePosition / a.lengths[reference] * a.lengths[i],
			)
		}
		_ = kineffi.Kine_Filament_AnimationTrackAdjustWeight(a.tracks[i], w, a.fade_time)
	}
	shot_slots := [2]int{4, 6}
	for slot in shot_slots {
		if a.tracks[slot] != nil && (target[slot] > 0 || a.weights[slot] > 0) {
			a.shot_time[slot] = min(
				a.shot_time[slot] + dt * a.shot_speed[slot],
				max(0, a.lengths[slot] - 0.0001),
			)
			_ = kineffi.Kine_Filament_AnimationTrackSetTimePosition(
				a.tracks[slot],
				a.shot_time[slot],
			)
		}
	}
	a.weights = target; a.status = "Playing"
	Render_3D_Mark_Dirty()
}

Register_CharacterAnimator :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&CharacterAnimator_Class,
		character_animator_construct,
		character_animator_destroy,
		get = character_animator_get,
		set = character_animator_set,
		clone = character_animator_clone,
		_step = character_animator_step,
		_step_phase = .Update,
		properties = []string {
			"Enabled",
			"RigMeshName",
			"FadeTime",
			"WalkAnimationSpeed",
			"RunAnimationSpeed",
			"SprintAnimationSpeed",
			"IdleClip",
			"WalkClip",
			"RunClip",
			"SprintClip",
			"JumpClip",
			"FallClip",
			"LandClip",
			"Status",
			"State",
			"HorizontalSpeed",
		},
	)
}
