package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:strings"

AnimationClip_Class := Class_Info {
	name   = "AnimationClip",
	parent = &Instance_Class,
}
KeyframeSequence_Class := Class_Info {
	name   = "KeyframeSequence",
	parent = &AnimationClip_Class,
}
Keyframe_Class := Class_Info {
	name   = "Keyframe",
	parent = &Instance_Class,
}
Pose_Class := Class_Info {
	name   = "Pose",
	parent = &Instance_Class,
}
KeyframeMarker_Class := Class_Info {
	name   = "KeyframeMarker",
	parent = &Instance_Class,
}

AnimationClip :: struct {
	using object: Object,
	looped:       bool,
	priority:     i32, // native priority
}
KeyframeSequence :: struct {
	using clip: AnimationClip,
}
Keyframe :: struct {
	using object: Object,
	time:         f32,
}
Pose :: struct {
	using object: Object,
	cframe:       datatypes.CFrame,
	weight:       f32,
}
KeyframeMarker :: struct {
	using object: Object,
	value:        string,
}

animation_clip_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(AnimationClip)
	value.object = Object_Init(&AnimationClip_Class, "AnimationClip")
	return &value.object
}
animation_clip_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^AnimationClip)object)
}
animation_clip_get :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	clip := cast(^AnimationClip)object
	switch key {
	case "Loop":
		vm.PushBoolean(L, clip.looped)
	case "Priority":
		Animation_Push_Priority(L, enum_registry, clip.priority)
	case:
		return false
	}
	return true
}
animation_clip_set :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	clip := cast(^AnimationClip)object
	switch key {
	case "Loop":
		clip.looped = vm.ArgBoolean(L, index)
	case "Priority":
		clip.priority = Animation_Arg_Priority(L, enum_registry, index)
	case:
		return false
	}
	return true
}
animation_clip_clone :: proc(source, target: ^Object) {
	a := cast(^AnimationClip)source
	b := cast(^AnimationClip)target
	b.looped = a.looped
	b.priority = a.priority
}

animation_sequence_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(KeyframeSequence)
	value.clip.object = Object_Init(&KeyframeSequence_Class, "KeyframeSequence")
	return &value.object
}
animation_sequence_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^KeyframeSequence)object)
}
Animation_Push_Children :: proc(L: ^vm.State, root: ^Object, info: ^Class_Info) {
	vm.NewTable(L, 0)
	if root == nil {return}
	index := 0
	for child in root.children {
		if child != nil && !child.destroyed && Is_A_Class(child, info) {
			index += 1
			Push_Object(L, child)
			vm.SetArrayValue(L, -2, index)
		}
	}
}
Animation_Parent_Child :: proc(
	L: ^vm.State,
	parent: ^Object,
	index: int,
	info: ^Class_Info,
) -> (
	i32,
	bool,
) {
	child := object_from_argument(L, index)
	if child == nil || !Is_A_Class(child, info) {
		return vm.RaiseError(L, "expected animation child Instance"), true
	}
	Set_Parent(child, parent)
	return 0, true
}
animation_sequence_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enums: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "GetKeyframes":
		Animation_Push_Children(L, object, &Keyframe_Class)
		return 1, true
	case "AddKeyframe":
		return Animation_Parent_Child(L, object, 2, &Keyframe_Class)
	case "RemoveKeyframe":
		child := object_from_argument(L, 2)
		if child != nil &&
		   child.parent == object &&
		   Is_A_Class(child, &Keyframe_Class) {Set_Parent(child, nil)}
		return 0, true
	}
	return 0, false
}

animation_keyframe_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(Keyframe)
	value.object = Object_Init(&Keyframe_Class, "Keyframe")
	return &value.object
}
animation_keyframe_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^Keyframe)object)
}
animation_keyframe_get :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "Time":
		vm.PushNumber(L, f64((cast(^Keyframe)object).time))
	case:
		return false
	}
	return true
}
animation_keyframe_set :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	switch key {
	case "Time":
		time := vm.ArgNumber(L, index)
		if time < 0 || time > 36000 {return false}
		(cast(^Keyframe)object).time = f32(time)
	case:
		return false
	}
	return true
}
animation_keyframe_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enums: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "GetPoses":
		Animation_Push_Children(L, object, &Pose_Class)
		return 1, true
	case "AddPose":
		return Animation_Parent_Child(L, object, 2, &Pose_Class)
	case "RemovePose":
		child := object_from_argument(L, 2)
		if child != nil &&
		   child.parent == object &&
		   Is_A_Class(child, &Pose_Class) {Set_Parent(child, nil)}
		return 0, true
	case "GetMarkers":
		Animation_Push_Children(L, object, &KeyframeMarker_Class)
		return 1, true
	case "AddMarker":
		return Animation_Parent_Child(L, object, 2, &KeyframeMarker_Class)
	case "RemoveMarker":
		child := object_from_argument(L, 2)
		if child != nil &&
		   child.parent == object &&
		   Is_A_Class(child, &KeyframeMarker_Class) {Set_Parent(child, nil)}
		return 0, true
	}
	return 0, false
}
animation_keyframe_clone :: proc(source, target: ^Object) {
	(cast(^Keyframe)target).time = (cast(^Keyframe)source).time
}

animation_pose_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(Pose)
	value.object = Object_Init(&Pose_Class, "Pose")
	value.cframe = datatypes.CFrame_Identity
	value.weight = 1
	return &value.object
}
animation_pose_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^Pose)object)
}
animation_pose_get :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
) -> bool {
	pose := cast(^Pose)object
	switch key {
	case "CFrame":
		datatypes.Push_CFrame(L, types, pose.cframe)
	case "Weight":
		vm.PushNumber(L, f64(pose.weight))
	case:
		return false
	}
	return true
}
animation_pose_set :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	pose := cast(^Pose)object
	switch key {
	case "CFrame":
		pose.cframe = datatypes.Arg_CFrame(L, index, types)
	case "Weight":
		pose.weight = f32(vm.ArgNumber(L, index))
	case:
		return false
	}
	return true
}
animation_pose_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enums: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "GetSubPoses":
		Animation_Push_Children(L, object, &Pose_Class)
		return 1, true
	case "AddSubPose":
		return Animation_Parent_Child(L, object, 2, &Pose_Class)
	case "RemoveSubPose":
		child := object_from_argument(L, 2)
		if child != nil &&
		   child.parent == object &&
		   Is_A_Class(child, &Pose_Class) {Set_Parent(child, nil)}
		return 0, true
	}
	return 0, false
}
animation_pose_clone :: proc(source, target: ^Object) {
	(cast(^Pose)target).cframe = (cast(^Pose)source).cframe
	(cast(^Pose)target).weight = (cast(^Pose)source).weight
}

animation_marker_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	value := new(KeyframeMarker)
	value.object = Object_Init(&KeyframeMarker_Class, "KeyframeMarker")
	return &value.object
}
animation_marker_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	marker := cast(^KeyframeMarker)object
	delete(marker.value)
	Object_Destroy(object)
	free(marker)
}
animation_marker_get :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "Value":
		vm.PushString(L, (cast(^KeyframeMarker)object).value)
	case:
		return false
	}
	return true
}
animation_marker_set :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	switch key {
	case "Value":
		marker := cast(^KeyframeMarker)object
		delete(marker.value)
		marker.value = strings.clone(vm.ArgString(L, index))
	case:
		return false
	}
	return true
}
animation_marker_clone :: proc(source, target: ^Object) {
	(cast(^KeyframeMarker)target).value = strings.clone((cast(^KeyframeMarker)source).value)
}

Register_AnimationAuthoring :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&AnimationClip_Class,
		animation_clip_construct,
		animation_clip_destroy,
		creatable = false,
		get = animation_clip_get,
		set = animation_clip_set,
		clone = animation_clip_clone,
		properties = []string{"Loop", "Priority"},
	)
	Register_Class(
		registry,
		&KeyframeSequence_Class,
		animation_sequence_construct,
		animation_sequence_destroy,
		get = animation_clip_get,
		set = animation_clip_set,
		namecall = animation_sequence_namecall,
		clone = animation_clip_clone,
		properties = []string{"Loop", "Priority"},
		methods = []string{"GetKeyframes", "AddKeyframe", "RemoveKeyframe"},
	)
	Register_Class(
		registry,
		&Keyframe_Class,
		animation_keyframe_construct,
		animation_keyframe_destroy,
		get = animation_keyframe_get,
		set = animation_keyframe_set,
		namecall = animation_keyframe_namecall,
		clone = animation_keyframe_clone,
		properties = []string{"Time"},
		methods = []string {
			"GetPoses",
			"AddPose",
			"RemovePose",
			"GetMarkers",
			"AddMarker",
			"RemoveMarker",
		},
	)
	Register_Class(
		registry,
		&Pose_Class,
		animation_pose_construct,
		animation_pose_destroy,
		get = animation_pose_get,
		set = animation_pose_set,
		namecall = animation_pose_namecall,
		clone = animation_pose_clone,
		properties = []string{"CFrame", "Weight"},
		methods = []string{"GetSubPoses", "AddSubPose", "RemoveSubPose"},
	)
	Register_Class(
		registry,
		&KeyframeMarker_Class,
		animation_marker_construct,
		animation_marker_destroy,
		get = animation_marker_get,
		set = animation_marker_set,
		clone = animation_marker_clone,
		properties = []string{"Value"},
	)
}
