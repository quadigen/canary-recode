package classes
import enums "../enum"
import vm "../vm"

import datatypes "../datatypes"
import "core:math"

MovementController_Class := Class_Info {
	name   = "MovementController",
	parent = &Instance_Class,
}

MovementController :: struct {
	using object:               Object,
	input_direction:            datatypes.Vector3,
	desired_velocity:           datatypes.Vector3,
	walk_speed:                 f32,
	acceleration:               f32,
	use_automatic_acceleration: bool,
	deceleration_multiplier:    f32,
	air_control:                f32,
	speed_multiplier:           f32,
	jump_buffer_duration:       f32,
	analog_input:               bool,
	jump_buffered:              bool,
	jump_buffer_time:           f32,
}

movement_controller_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	mc := new(MovementController)
	mc.object = Object_Init(&MovementController_Class, "MovementController")
	mc.walk_speed = 16
	mc.acceleration = 160
	mc.use_automatic_acceleration = true
	mc.deceleration_multiplier = 1
	mc.air_control = 1
	mc.speed_multiplier = 1
	mc.jump_buffer_duration = 0.1
	mc.analog_input = false
	return &mc.object
}

movement_controller_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^MovementController)object)
}

MovementController_Queue_Jump :: proc(mc: ^MovementController) {
	if mc == nil {return}
	mc.jump_buffered = true
	mc.jump_buffer_time = mc.jump_buffer_duration
}

MovementController_Step :: proc(
	mc: ^MovementController,
	dt: f32,
	grounded := true,
) -> (
	move_dir: datatypes.Vector3,
	jump: bool,
) {
	if mc == nil {return datatypes.Vector3{}, false}
	flat := datatypes.Vector3{mc.input_direction.x, 0, mc.input_direction.z}
	length := math.sqrt(flat.x * flat.x + flat.z * flat.z)
	if length > 0.0001 && (!mc.analog_input || length > 1) {
		flat.x /= length
		flat.z /= length
	}
	target_x, target_z :=
		flat.x *
		f64(mc.walk_speed * mc.speed_multiplier),
		flat.z *
		f64(mc.walk_speed * mc.speed_multiplier)
	acceleration := mc.use_automatic_acceleration ? 10 * mc.walk_speed : mc.acceleration
	step := acceleration * dt
	if length <= 0.0001 {step *= mc.deceleration_multiplier}
	if !grounded {step *= mc.air_control}
	mc.desired_velocity.x = f64(move_toward(f32(mc.desired_velocity.x), f32(target_x), step))
	mc.desired_velocity.z = f64(move_toward(f32(mc.desired_velocity.z), f32(target_z), step))
	jump = mc.jump_buffered
	if mc.jump_buffer_time > 0 {
		mc.jump_buffer_time -= dt
		if mc.jump_buffer_time <= 0 {mc.jump_buffered = false}
	} else {mc.jump_buffered = false}
	return datatypes.Vector3{mc.desired_velocity.x, 0, mc.desired_velocity.z}, jump
}

move_toward :: proc(current, target, max_delta: f32) -> f32 {
	if current < target {return min(current + max_delta, target)}
	if current > target {return max(current - max_delta, target)}
	return current
}

movement_controller_clone :: proc(source, destination: ^Object) {
	src := cast(^MovementController)source
	dst := cast(^MovementController)destination
	dst.acceleration = src.acceleration
	dst.use_automatic_acceleration = src.use_automatic_acceleration
	dst.deceleration_multiplier = src.deceleration_multiplier
	dst.air_control = src.air_control
	dst.speed_multiplier = src.speed_multiplier
	dst.jump_buffer_duration = src.jump_buffer_duration
	dst.analog_input = src.analog_input
}
movement_controller_get :: proc(
	L: ^vm.State,
	object: ^Object,
	_: ^datatypes.Registry,
	_: ^enums.Registry,
	key: string,
) -> bool {
	obj := cast(^MovementController)object
	switch key {
	case "Acceleration":
		vm.PushNumber(L, f64(obj.acceleration))
	case "UseAutomaticAcceleration":
		vm.PushBoolean(L, obj.use_automatic_acceleration)
	case "DecelerationMultiplier":
		vm.PushNumber(L, f64(obj.deceleration_multiplier))
	case "AirControl":
		vm.PushNumber(L, f64(obj.air_control))
	case "SpeedMultiplier":
		vm.PushNumber(L, f64(obj.speed_multiplier))
	case "JumpBufferTime":
		vm.PushNumber(L, f64(obj.jump_buffer_duration))
	case "AnalogInput":
		vm.PushBoolean(L, obj.analog_input)
	case:
		return false
	}
	return true
}
movement_controller_set :: proc(
	L: ^vm.State,
	object: ^Object,
	_: ^datatypes.Registry,
	_: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	obj := cast(^MovementController)object
	switch key {
	case "Acceleration":
		obj.acceleration = f32(
			character_tuning_number(L, value_index, 0, 10000, f64(obj.acceleration)),
		)
	case "UseAutomaticAcceleration":
		obj.use_automatic_acceleration = vm.ArgBoolean(L, value_index)
	case "DecelerationMultiplier":
		obj.deceleration_multiplier = f32(
			character_tuning_number(L, value_index, 0, 100, f64(obj.deceleration_multiplier)),
		)
	case "AirControl":
		obj.air_control = f32(character_tuning_number(L, value_index, 0, 1, f64(obj.air_control)))
	case "SpeedMultiplier":
		obj.speed_multiplier = f32(
			character_tuning_number(L, value_index, 0, 100, f64(obj.speed_multiplier)),
		)
	case "JumpBufferTime":
		obj.jump_buffer_duration = f32(
			character_tuning_number(L, value_index, 0, 5, f64(obj.jump_buffer_duration)),
		)
	case "AnalogInput":
		obj.analog_input = vm.ArgBoolean(L, value_index)
	case:
		return false
	}
	return true
}
Register_MovementController :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&MovementController_Class,
		movement_controller_construct,
		movement_controller_destroy,
		clone = movement_controller_clone,
		get = movement_controller_get,
		set = movement_controller_set,
		properties = []string {
			"Acceleration",
			"UseAutomaticAcceleration",
			"DecelerationMultiplier",
			"AirControl",
			"SpeedMultiplier",
			"JumpBufferTime",
			"AnalogInput",
		},
	)
}
