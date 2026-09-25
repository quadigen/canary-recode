package classes

import "core:math"
import datatypes "../datatypes"

GroundDetector_Class := Class_Info {
	name   = "GroundDetector",
	parent = &Instance_Class,
}

GroundDetector :: struct {
	using object: Object,

	grounded:    bool,
	rest_y:      f32,
	slope_angle: f32,
	ray_count:   i32,
	snap_distance: f32,
}

ground_detector_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	gd := new(GroundDetector)
	gd.object = Object_Init(&GroundDetector_Class, "GroundDetector")
	gd.ray_count = 5
	gd.snap_distance = 0.6
	return &gd.object
}

ground_detector_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^GroundDetector)object)
}

GroundDetector_Is_Airborne :: proc(gd: ^GroundDetector) -> bool {return gd == nil || !gd.grounded}

Register_GroundDetector :: proc(registry: ^Registry) {
	Register_Class(registry, &GroundDetector_Class, ground_detector_construct, ground_detector_destroy)
}