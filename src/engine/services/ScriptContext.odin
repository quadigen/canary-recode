package services

// wire:service global="ScriptContext"

import classes "../classes"
import enums "../enum"
import kineffi "../bindings"

ScriptContext_Class := classes.Class_Info{
	name   = "ScriptContext",
	parent = &Service_Class,
}

ScriptContext :: struct {
	using service: Service,
}

ScriptContext_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	ScriptContext := new(ScriptContext)
	ScriptContext.service = Service_Init(&ScriptContext_Class, "ScriptContext", data_model)
	return &ScriptContext.object
}

ScriptContext_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	ScriptContext := cast(^ScriptContext)object
	classes.Object_Destroy(object)
	free(ScriptContext)
}

Register_ScriptContext_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&ScriptContext_Class,
		ScriptContext_construct,
		ScriptContext_destroy,
		creatable = false,
	)
}
