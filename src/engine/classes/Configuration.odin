package classes

Configuration_Class := Class_Info{name = "Configuration", parent = &Instance_Class}

configuration_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	object := new(Object)
	object^ = Object_Init(&Configuration_Class, "Configuration")
	return object
}

configuration_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(object)
}

Register_Configuration :: proc(registry: ^Registry) {
	Register_Class(registry, &Configuration_Class, configuration_construct, configuration_destroy)
}
