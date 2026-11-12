package classes

import kineffi "../bindings"

COLLISION_STEP_HEIGHT :: 0.5
COLLISION_SKIN :: 0.05

CollisionController_Class := Class_Info {
	name   = "CollisionController",
	parent = &Instance_Class,
}

CollisionController :: struct {
	using object: Object,

	half_height:  f32,
	radius:       f32,
	shape:        kineffi.JPH_ShapeRef,
	body_id:      kineffi.JPH_BodyID,
	body_created: bool,
	deformable_only: bool,
	// ragdoll flips the capsule between a kinematic body the character
	// controller teleports each frame and a dynamic one the solver integrates.
	// It is sticky so a body created after the character dies is still dynamic.
	ragdoll: bool,
	// Bodies the character touched on the previous/current simulation step.
	// Touched is an enter-only signal, so sweeps report against these sets
	// instead of firing every frame the capsule stays in contact.
	touching_prev: map[kineffi.JPH_BodyID]bool,
	touching_now:  map[kineffi.JPH_BodyID]bool,
}

collision_controller_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	coll := new(CollisionController)
	coll.object = Object_Init(&CollisionController_Class, "CollisionController")
	coll.body_id = kineffi.JPH_BODY_ID_INVALID
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

Register_CollisionController :: proc(registry: ^Registry) {
	Register_Class(registry, &CollisionController_Class, collision_controller_construct, collision_controller_destroy)
}