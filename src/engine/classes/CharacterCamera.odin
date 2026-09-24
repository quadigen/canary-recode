package classes

CharacterCamera_Class := Class_Info {
	name   = "CharacterCamera",
	parent = &Instance_Class,
}

CharacterCamera :: struct {
	using object: Object,
}

character_camera_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	cam := new(CharacterCamera)
	cam.object = Object_Init(&CharacterCamera_Class, "CharacterCamera")
	return &cam.object
}

character_camera_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^CharacterCamera)object)
}

Register_CharacterCamera :: proc(registry: ^Registry) {
	Register_Class(registry, &CharacterCamera_Class, character_camera_construct, character_camera_destroy)
}