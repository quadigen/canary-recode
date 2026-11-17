package classes

import datatypes "../datatypes"
import enums "../enum"
import signals "../signals"
import vm "../vm"

AnimationController_Class := Class_Info {
	name   = "AnimationController",
	parent = &Instance_Class,
}
AnimationController :: struct {
	using object:     Object,
	mesh_part:        ^Object,
	animation_played: ^signals.Signal,
}
animation_controller_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	c := new(AnimationController)
	c.object = Object_Init(&AnimationController_Class, "AnimationController")
	return &c.object
}
animation_controller_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	c := cast(^AnimationController)object
	Animation_Signal_Destroy(&c.animation_played)
	Object_Destroy(object)
	free(c)
}
animation_controller_get :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
) -> bool {
	c := cast(^AnimationController)object
	switch key {
	case "MeshPart":
		if Animation_Is_Live(
			object.signal_registry,
			"MeshPart",
			c.mesh_part,
		) {Push_Object(L, c.mesh_part)} else {vm.PushNil(L)}
	case "AnimationPlayed":
		signal := Animation_Signal(object, &c.animation_played)
		if signal == nil {return false}
		signals.Push(L, signal)
	case:
		return false
	}
	return true
}
animation_controller_set :: proc(
	L: ^vm.State,
	object: ^Object,
	types: ^datatypes.Registry,
	enums: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	c := cast(^AnimationController)object
	switch key {
	case "MeshPart":
		target := object_from_argument(L, index)
		if !vm.IsNil(L, index) &&
		   (target == nil || !Is_A_Class(target, &MeshPart_Class)) {return false}
		for child in object.children {
			if Is_A_Class(child, &Animator_Class) {
				Animation_Animator_Release(cast(^Animator)child)
			}
		}
		c.mesh_part = target
	case:
		return false
	}
	return true
}
animation_controller_namecall :: proc(
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
	case "LoadAnimation":
		a := Animation_Ensure_Child_Animator(L, object)
		if a == nil {return vm.RaiseError(L, "could not construct child Animator"), true}
		return Animation_Load_Track(L, a, object_from_argument(L, 2))
	case "GetPlayingAnimationTracks":
		for child in object.children {
			if Is_A_Class(child, &Animator_Class) {
				Animation_Push_Track_Array(L, cast(^Animator)child)
				return 1, true
			}
		}
		vm.NewTable(L, 0)
		return 1, true
	}
	return 0, false
}
Register_AnimationController :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&AnimationController_Class,
		animation_controller_construct,
		animation_controller_destroy,
		get = animation_controller_get,
		set = animation_controller_set,
		namecall = animation_controller_namecall,
		properties = []string{"MeshPart"},
		methods = []string{"LoadAnimation", "GetPlayingAnimationTracks"},
		events = []string{"AnimationPlayed"},
	)
}
