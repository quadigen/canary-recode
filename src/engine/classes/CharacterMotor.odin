package classes

CharacterMotor_Class := Class_Info {
	name   = "CharacterMotor",
	parent = &Instance_Class,
}

CharacterMotor :: struct {
	using object: Object,

	steps_per_second: f32,
	accumulator: f32,
	max_step: f32,
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

Register_CharacterMotor :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&CharacterMotor_Class,
		character_motor_construct,
		character_motor_destroy,
		clone = character_motor_clone,
	)
}