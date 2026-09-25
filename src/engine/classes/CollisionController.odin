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
}

collision_controller_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	coll := new(CollisionController)
	coll.object = Object_Init(&CollisionController_Class, "CollisionController")
	coll.body_id = kineffi.JPH_BODY_ID_INVALID
	return &coll.object
}

collision_controller_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^CollisionController)object)
}

Register_CollisionController :: proc(registry: ^Registry) {
	Register_Class(registry, &CollisionController_Class, collision_controller_construct, collision_controller_destroy)
}