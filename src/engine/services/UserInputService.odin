package services
import classes "../classes"


UserInputService := Class_Info{
	name   = "UserInputService",
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