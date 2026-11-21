package classes
import enums "../enum"
import vm "../vm"

import datatypes "../datatypes"
import "core:math"

GroundDetector_Class := Class_Info {
	name   = "GroundDetector",
	parent = &Instance_Class,
}

GroundDetector :: struct {
	using object:  Object,
	grounded:      bool,
	rest_y:        f32,
	slope_angle:   f32,
	ray_count:     i32,
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

ground_detector_clone :: proc(source, destination: ^Object) {
	src := cast(^GroundDetector)source
	dst := cast(^GroundDetector)destination
	dst.snap_distance = src.snap_distance
}

ground_detector_get :: proc(
	L: ^vm.State,
	object: ^Object,
	_: ^datatypes.Registry,
	_: ^enums.Registry,
	key: string,
) -> bool {
	obj := cast(^GroundDetector)object
	switch key {
	case "SnapDistance":
		vm.PushNumber(L, f64(obj.snap_distance))
	case "Grounded":
		vm.PushBoolean(L, obj.grounded)
	case "SlopeAngle":
		vm.PushNumber(L, f64(obj.slope_angle))
	case "RestY":
		vm.PushNumber(L, f64(obj.rest_y))
	case:
		return false
	}
	return true
}

ground_detector_set :: proc(
	L: ^vm.State,
	object: ^Object,
	_: ^datatypes.Registry,
	_: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	obj := cast(^GroundDetector)object
	switch key {
	case "SnapDistance":
		obj.snap_distance = f32(
			character_tuning_number(L, value_index, 0, 20, f64(obj.snap_distance)),
		)
	case:
		return false
	}
	return true
}

Register_GroundDetector :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&GroundDetector_Class,
		ground_detector_construct,
		ground_detector_destroy,
		clone = ground_detector_clone,
		get = ground_detector_get,
		set = ground_detector_set,
		properties = []string{"SnapDistance", "Grounded", "SlopeAngle", "RestY"},
	)
}
