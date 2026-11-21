package classes
import enums "../enum"
import vm "../vm"

import datatypes "../datatypes"
import "core:math"

RotationController_Class := Class_Info {
	name   = "RotationController",
	parent = &Instance_Class,
}

RotationController :: struct {
	using object:      Object,
	yaw:               f32,
	target_yaw:        f32,
	turn_rate:         f32,
	face_movement:     bool,
	manual_target_yaw: f32,
}

rotation_controller_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	rc := new(RotationController)
	rc.object = Object_Init(&RotationController_Class, "RotationController")
	rc.turn_rate = 720
	rc.face_movement = true
	return &rc.object
}

rotation_controller_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^RotationController)object)
}

RotationController_Set_Target :: proc(rc: ^RotationController, direction: datatypes.Vector3) {
	if rc == nil {return}
	target := math.atan2(direction.x, direction.z) * 180 / math.PI
	rc.target_yaw = f32(target)
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
	if value < -180 {value += 360}
	return value
}

rotation_controller_clone :: proc(source, destination: ^Object) {
	src := cast(^RotationController)source
	dst := cast(^RotationController)destination
	dst.turn_rate = src.turn_rate
	dst.face_movement = src.face_movement
	dst.manual_target_yaw = src.manual_target_yaw
}

rotation_controller_get :: proc(
	L: ^vm.State,
	object: ^Object,
	_: ^datatypes.Registry,
	_: ^enums.Registry,
	key: string,
) -> bool {
	obj := cast(^RotationController)object
	switch key {
	case "TurnRate":
		vm.PushNumber(L, f64(obj.turn_rate))
	case "FaceMovement":
		vm.PushBoolean(L, obj.face_movement)
	case "TargetYaw":
		vm.PushNumber(L, f64(obj.manual_target_yaw))
	case "Yaw":
		vm.PushNumber(L, f64(obj.yaw))
	case:
		return false
	}
	return true
}

rotation_controller_set :: proc(
	L: ^vm.State,
	object: ^Object,
	_: ^datatypes.Registry,
	_: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	obj := cast(^RotationController)object
	switch key {
	case "TurnRate":
		obj.turn_rate = f32(character_tuning_number(L, value_index, 0, 100000, f64(obj.turn_rate)))
	case "FaceMovement":
		obj.face_movement = vm.ArgBoolean(L, value_index)
	case "TargetYaw":
		obj.manual_target_yaw = f32(
			character_tuning_number(L, value_index, -360, 360, f64(obj.manual_target_yaw)),
		)
	case:
		return false
	}
	return true
}

Register_RotationController :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&RotationController_Class,
		rotation_controller_construct,
		rotation_controller_destroy,
		clone = rotation_controller_clone,
		get = rotation_controller_get,
		set = rotation_controller_set,
		properties = []string{"TurnRate", "FaceMovement", "TargetYaw", "Yaw"},
	)
}
