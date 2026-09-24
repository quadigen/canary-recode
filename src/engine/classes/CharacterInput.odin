package classes

CharacterInput_Class := Class_Info {
	name   = "CharacterInput",
	parent = &Instance_Class,
}

CharacterInput :: struct {
	using object: Object,
}

character_input_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	input := new(CharacterInput)
	input.object = Object_Init(&CharacterInput_Class, "CharacterInput")
	return &input.object
}

character_input_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^CharacterInput)object)
}

Register_CharacterInput :: proc(registry: ^Registry) {
	Register_Class(registry, &CharacterInput_Class, character_input_construct, character_input_destroy)
}