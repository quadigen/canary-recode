package classes
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

import kineffi "../bindings"

COLLISION_STEP_HEIGHT :: 0.5
COLLISION_SKIN :: 0.05

CollisionController_Class := Class_Info {
	name   = "CollisionController",
	parent = &Instance_Class,
}

CollisionController :: struct {
	using object:     Object,
	step_height:      f32,
	skin_width:       f32,
	sweep_iterations: i32,
	half_height:      f32,
	radius:           f32,
	shape:            kineffi.JPH_ShapeRef,
	body_id:          kineffi.JPH_BodyID,
	body_created:     bool,
	deformable_only:  bool,
	ragdoll:          bool,
	touching_prev:    map[kineffi.JPH_BodyID]bool,
	touching_now:     map[kineffi.JPH_BodyID]bool,
}

collision_controller_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	coll := new(CollisionController)
	coll.object = Object_Init(&CollisionController_Class, "CollisionController")
	coll.body_id = kineffi.JPH_BODY_ID_INVALID
	coll.step_height = COLLISION_STEP_HEIGHT
	coll.skin_width = COLLISION_SKIN
	coll.sweep_iterations = 4
	coll.touching_prev = make(map[kineffi.JPH_BodyID]bool)
	coll.touching_now = make(map[kineffi.JPH_BodyID]bool)
	return &coll.object
}

collision_controller_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	coll := cast(^CollisionController)object
	delete(coll.touching_prev)
	delete(coll.touching_now)
	coll.touching_prev = nil
	coll.touching_now = nil
	Object_Destroy(object)
	free(coll)
}

collision_controller_clone :: proc(source, destination: ^Object) {
	src := cast(^CollisionController)source
	dst := cast(^CollisionController)destination
	dst.step_height = src.step_height
	dst.skin_width = src.skin_width
	dst.sweep_iterations = src.sweep_iterations
}

collision_controller_get :: proc(
	L: ^vm.State,
	object: ^Object,
	_: ^datatypes.Registry,
	_: ^enums.Registry,
	key: string,
) -> bool {
	obj := cast(^CollisionController)object
	switch key {
	case "StepHeight":
		vm.PushNumber(L, f64(obj.step_height))
	case "SkinWidth":
		vm.PushNumber(L, f64(obj.skin_width))
	case "SweepIterations":
		vm.PushNumber(L, f64(obj.sweep_iterations))
	case "Radius":
		vm.PushNumber(L, f64(obj.radius))
	case "HalfHeight":
		vm.PushNumber(L, f64(obj.half_height))
	case:
		return false
	}
	return true
}

collision_controller_set :: proc(
	L: ^vm.State,
	object: ^Object,
	_: ^datatypes.Registry,
	_: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	obj := cast(^CollisionController)object
	switch key {
	case "StepHeight":
		obj.step_height = f32(character_tuning_number(L, value_index, 0, 20, f64(obj.step_height)))
	case "SkinWidth":
		obj.skin_width = f32(
			character_tuning_number(L, value_index, 0.001, 1, f64(obj.skin_width)),
		)
	case "SweepIterations":
		obj.sweep_iterations = i32(
			character_tuning_number(L, value_index, 1, 16, f64(obj.sweep_iterations)),
		)
	case:
		return false
	}
	return true
}

Register_CollisionController :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&CollisionController_Class,
		collision_controller_construct,
		collision_controller_destroy,
		clone = collision_controller_clone,
		get = collision_controller_get,
		set = collision_controller_set,
		properties = []string {
			"StepHeight",
			"SkinWidth",
			"SweepIterations",
			"Radius",
			"HalfHeight",
		},
	)
}
