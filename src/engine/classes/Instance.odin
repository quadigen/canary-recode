package classes

Instance_Class := Class_Info{
	name   = "Instance",
	parent = &Object_Class,
}

Instance :: struct {
	using object: Object,
}

Instance_Init :: proc() -> Instance {
	return Instance{
		object = Object_Init(&Instance_Class, "Instance"),
	}
}

instance_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	instance := new(Instance)
	instance^ = Instance_Init()
	return &instance.object
}

instance_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	Object_Destroy(object)
	free(cast(^Instance)object)
}

instance_clone :: proc(source: ^Object, destination: ^Object) {
	// No extra properties
}

Register_Instance :: proc(registry: ^Registry) {
	Register_Class(registry, &Instance_Class, instance_construct, instance_destroy, clone = instance_clone)
}

