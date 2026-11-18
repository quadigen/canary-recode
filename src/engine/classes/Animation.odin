package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:strings"

Animation_Class := Class_Info {
	name   = "Animation",
	parent = &Instance_Class,
}
Animation :: struct {
	using object: Object,
	clip_index:   i32,
	clip_name:    string,
	animation_id: string,
	looped:       bool,
	priority:     i32,
	sequence:     ^Object, // weak reference; always validated before use
}

animation_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	anim := new(Animation)
	anim.object = Object_Init(&Animation_Class, "Animation")
	return &anim.object
}
animation_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	anim := cast(^Animation)object
	delete(anim.clip_name)
	delete(anim.animation_id)
	Object_Destroy(object)
	free(anim)
}
animation_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	anim := cast(^Animation)object
	switch key {
	case "ClipIndex":
		vm.PushNumber(L, f64(anim.clip_index))
	case "ClipName":
		vm.PushString(L, anim.clip_name)
	case "AnimationId":
		vm.PushString(L, anim.animation_id)
	case "Looped":
		vm.PushBoolean(L, anim.looped)
	case "Priority":
		Animation_Push_Priority(L, enum_registry, anim.priority)
	case "Source":
		if Animation_Is_Live(object.signal_registry, "KeyframeSequence", anim.sequence) {
			Push_Object(L, anim.sequence)
		} else {vm.PushNil(L)}
	case:
		return false
	}
	return true
}
animation_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	anim := cast(^Animation)object
	switch key {
	case "ClipIndex":
		value := vm.ArgNumber(L, index)
		if value < 0 || value > 100000 {return false}
		anim.clip_index = i32(value)
	case "ClipName":
		delete(anim.clip_name)
		anim.clip_name = strings.clone(vm.ArgString(L, index))
	case "AnimationId":
		delete(anim.animation_id)
		anim.animation_id = strings.clone(vm.ArgString(L, index))
	case "Looped":
		anim.looped = vm.ArgBoolean(L, index)
	case "Priority":
		anim.priority = Animation_Arg_Priority(L, enum_registry, index)
	case "Source":
		if vm.IsNil(L, index) {anim.sequence = nil; return true}
		seq := object_from_argument(L, index)
		if seq == nil || !Is_A_Class(seq, &KeyframeSequence_Class) {return false}
		anim.sequence = seq
	case:
		return false
	}
	return true
}
animation_clone :: proc(source, destination: ^Object) {
	src := cast(^Animation)source
	dst := cast(^Animation)destination
	dst.clip_index = src.clip_index
	dst.clip_name = strings.clone(src.clip_name)
	dst.animation_id = strings.clone(src.animation_id)
	dst.looped = src.looped
	dst.priority = src.priority
	dst.sequence = src.sequence
}

Animation_Compile_Pose :: proc(
	mesh: ^kineffi.KineFilamentMesh,
	index: i32,
	keytime: f32,
	object: ^Object,
) {
	if mesh == nil ||
	   object == nil ||
	   object.destroyed ||
	   !Is_A_Class(object, &Pose_Class) {return}
	pose := cast(^Pose)object
	cf := pose.cframe
	mat := [12]f32 {
		cf.x,
		cf.y,
		cf.z,
		cf.r00,
		cf.r01,
		cf.r02,
		cf.r10,
		cf.r11,
		cf.r12,
		cf.r20,
		cf.r21,
		cf.r22,
	}
	bone_name := strings.clone_to_cstring(object.name)
	_ = kineffi.Kine_Filament_MeshAddAnimationPose(
		mesh,
		index,
		bone_name,
		keytime,
		&mat[0],
		clamp(pose.weight, f32(0), f32(1)),
	)
	delete(bone_name)
	for child in object.children {
		if Is_A_Class(child, &Pose_Class) {Animation_Compile_Pose(mesh, index, keytime, child)}
	}
}
Animation_Compile_Sequence :: proc(
	mesh: ^kineffi.KineFilamentMesh,
	sequence_object: ^Object,
) -> i32 {
	if mesh == nil ||
	   sequence_object == nil ||
	   !Is_A_Class(sequence_object, &KeyframeSequence_Class) {return -1}
	duration: f32 = 0.001
	count := 0
	for child in sequence_object.children {
		if child != nil && !child.destroyed && Is_A_Class(child, &Keyframe_Class) {
			duration = max(duration, (cast(^Keyframe)child).time)
			count += 1
		}
	}
	if count == 0 {return -1}
	clip_name := strings.clone_to_cstring(sequence_object.name)
	index := kineffi.Kine_Filament_MeshCreateAnimation(mesh, clip_name, duration)
	delete(clip_name)
	if index < 0 {return -1}
	for child in sequence_object.children {
		if child == nil || child.destroyed || !Is_A_Class(child, &Keyframe_Class) {continue}
		key := cast(^Keyframe)child
		key_name := strings.clone_to_cstring(child.name)
		_ = kineffi.Kine_Filament_MeshAddAnimationEvent(mesh, index, key.time, key_name, "", false)
		delete(key_name)
		for item in child.children {
			if item == nil || item.destroyed {continue}
			if Is_A_Class(item, &Pose_Class) {Animation_Compile_Pose(mesh, index, key.time, item)}
			if Is_A_Class(item, &KeyframeMarker_Class) {
				marker := cast(^KeyframeMarker)item
				marker_name := strings.clone_to_cstring(item.name)
				parameter := strings.clone_to_cstring(marker.value)
				_ = kineffi.Kine_Filament_MeshAddAnimationEvent(
					mesh,
					index,
					key.time,
					marker_name,
					parameter,
					true,
				)
				delete(marker_name)
				delete(parameter)
			}
		}
	}
	return index
}
Animation_Find_Clip :: proc(mesh: ^kineffi.KineFilamentMesh, anim: ^Animation) -> i32 {
	if mesh == nil || anim == nil {return -1}
	count := kineffi.Kine_Filament_GetMeshAnimationCount(mesh)
	if anim.clip_name != "" {
		for index: i32 = 0; index < count; index += 1 {
			name := kineffi.Kine_Filament_GetMeshAnimationName(mesh, index)
			if name != nil && string(name) == anim.clip_name {return index}
		}
		return -1
	}
	if anim.clip_index < 0 || anim.clip_index >= count {return -1}
	return anim.clip_index
}
Animation_Resolve_Clip :: proc(
	mesh: ^kineffi.KineFilamentMesh,
	ctx: ^kineffi.KineFilamentContext,
	anim: ^Animation,
) -> i32 {
	if mesh == nil || anim == nil {return -1}
	if Animation_Is_Live(anim.object.signal_registry, "KeyframeSequence", anim.sequence) {
		return Animation_Compile_Sequence(mesh, anim.sequence)
	}
	// A clip already on the rig wins, so loading the same Animation twice does
	// not duplicate the imported clip. Otherwise an AnimationId supplies the
	// missing clip, imported by bone name.
	if index := Animation_Find_Clip(mesh, anim); index >= 0 {return index}
	if anim.animation_id != "" && Animation_Import_Clips(ctx, mesh, anim.animation_id) {
		return Animation_Find_Clip(mesh, anim)
	}
	return -1
}
Register_Animation :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Animation_Class,
		animation_construct,
		animation_destroy,
		get = animation_get,
		set = animation_set,
		clone = animation_clone,
		properties = []string{"ClipIndex", "ClipName", "AnimationId", "Looped", "Priority", "Source"},
	)
}
