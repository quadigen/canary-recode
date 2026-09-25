package classes

import "core:math"
import datatypes "../datatypes"

RotationController_Class := Class_Info {
	name   = "RotationController",
	parent = &Instance_Class,
}

RotationController :: struct {
	using object: Object,

	yaw:       f32,
	target_yaw: f32,
	turn_rate: f32,
}

rotation_controller_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	rc := new(RotationController)
	rc.object = Object_Init(&RotationController_Class, "RotationController")
	rc.turn_rate = 720
	return &rc.object
}

rotation_controller_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^RotationController)object)
}

RotationController_Set_Target :: proc(rc: ^RotationController, direction: datatypes.Vector3) {
	if rc == nil {return}
	target := math.atan2(direction.x, direction.z) * 180 / math.PI
	rc.target_yaw = target
}

RotationController_Step :: proc(rc: ^RotationController, dt: f32) -> (yaw: f32) {
	if rc == nil {return 0}
	diff := wrap_angle_180(rc.target_yaw - rc.yaw)
	move := rc.turn_rate * dt
	if math.abs(diff) <= move {
		rc.yaw = rc.target_yaw
	} else {
		rc.yaw += math.sign(diff) * move
	}
	return rc.yaw
}

wrap_angle_180 :: proc(angle: f32) -> f32 {
	value := math.mod(angle, 360)
	if value > 180 {value -= 360}
	return value
}

Register_RotationController :: proc(registry: ^Registry) {
	Register_Class(registry, &RotationController_Class, rotation_controller_construct, rotation_controller_destroy)
}