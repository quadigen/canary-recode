package classes

Instance_Class := Class_Info{
	name   = "Instance",
	parent = &Object_Class,
}

Instance :: struct {
	using object: Object
}

Instance_Init :: proc() -> Instance {
	return Instance{
		object = Object_Init(&Instance_Class),
	}
}