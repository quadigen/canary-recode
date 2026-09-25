package classes

import "core:math"
import datatypes "../datatypes"

MovementController_Class := Class_Info {
	name   = "MovementController",
	parent = &Instance_Class,
}

MovementController :: struct {
	using object: Object,

	input_direction: datatypes.Vector3,
	desired_velocity: datatypes.Vector3,
	walk_speed: f32,
	acceleration: f32,
	jump_buffered: bool,
	jump_buffer_time: f32,
}

movement_controller_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	mc := new(MovementController)
	mc.object = Object_Init(&MovementController_Class, "MovementController")
	mc.walk_speed = 16
	mc.acceleration = 160
	return &mc.object
}

movement_controller_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^MovementController)object)
}

MovementController_Queue_Jump :: proc(mc: ^MovementController) {
	if mc == nil {return}
	mc.jump_buffered = true
	mc.jump_buffer_time = 0.1
}

MovementController_Step :: proc(mc: ^MovementController, dt: f32) -> (move_dir: datatypes.Vector3, jump: bool) {
	if mc == nil {return datatypes.Vector3{}, false}
	flat := datatypes.Vector3{mc.input_direction.x, 0, mc.input_direction.z}
	length := math.sqrt(flat.x * flat.x + flat.z * flat.z)
	if length > 0.0001 {
		flat.x /= length
		flat.z /= length
	}
	target_x, target_z := flat.x * mc.walk_speed, flat.z * mc.walk_speed
	step := mc.acceleration * dt
	mc.desired_velocity.x = move_toward(mc.desired_velocity.x, target_x, step)
	mc.desired_velocity.z = move_toward(mc.desired_velocity.z, target_z, step)
	if mc.jump_buffer_time > 0 {
		mc.jump_buffer_time -= dt
		if mc.jump_buffer_time <= 0 {mc.jump_buffered = false}
	}
	return datatypes.Vector3{mc.desired_velocity.x, 0, mc.desired_velocity.z}, mc.jump_buffered
}

move_toward :: proc(current, target, max_delta: f32) -> f32 {
	if current < target {return min(current + max_delta, target)}
	if current > target {return max(current - max_delta, target)}
	return current
}

Register_MovementController :: proc(registry: ^Registry) {
	Register_Class(registry, &MovementController_Class, movement_controller_construct, movement_controller_destroy)
}