package classes
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

CharacterMotor_Class := Class_Info {
	name   = "CharacterMotor",
	parent = &Instance_Class,
}

CharacterMotor :: struct {
	using object:     Object,
	steps_per_second: f32,
	accumulator:      f32,
	max_step:         f32,
}

character_motor_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	motor := new(CharacterMotor)
	motor.object = Object_Init(&CharacterMotor_Class, "CharacterMotor")
	motor.steps_per_second = 120
	motor.max_step = 0.25
	return &motor.object
}

character_motor_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^CharacterMotor)object)
}

character_motor_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^CharacterMotor)source
	dst := cast(^CharacterMotor)destination
	dst.steps_per_second = src.steps_per_second
	dst.accumulator = 0
	dst.max_step = src.max_step
}

character_motor_get :: proc(
	L: ^vm.State,
	object: ^Object,
	_: ^datatypes.Registry,
	_: ^enums.Registry,
	key: string,
) -> bool {
	obj := cast(^CharacterMotor)object
	switch key {
	case "StepsPerSecond":
		vm.PushNumber(L, f64(obj.steps_per_second))
	case "MaxFrameTime":
		vm.PushNumber(L, f64(obj.max_step))
	case:
		return false
	}
	return true
}

character_motor_set :: proc(
	L: ^vm.State,
	object: ^Object,
	_: ^datatypes.Registry,
	_: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	obj := cast(^CharacterMotor)object
	switch key {
	case "StepsPerSecond":
		obj.steps_per_second = f32(
			character_tuning_number(L, value_index, 15, 480, f64(obj.steps_per_second)),
		)
	case "MaxFrameTime":
		obj.max_step = f32(character_tuning_number(L, value_index, 0.001, 0.25, f64(obj.max_step)))
	case:
		return false
	}
	return true
}

Register_CharacterMotor :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&CharacterMotor_Class,
		character_motor_construct,
		character_motor_destroy,
		clone = character_motor_clone,
		get = character_motor_get,
		set = character_motor_set,
		properties = []string{"StepsPerSecond", "MaxFrameTime"},
	)
}
