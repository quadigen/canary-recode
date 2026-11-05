package classes

BaseScript_Class := Class_Info {
	name   = "BaseScript",
	parent = &Instance_Class,
}

base_script_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	object := new(Object)
	object^ = Object_Init(&BaseScript_Class, "BaseScript")
	return object
}

base_script_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(object)
}

Register_BaseScript :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&BaseScript_Class,
		base_script_construct,
		base_script_destroy,
		creatable = false,
	)
}
