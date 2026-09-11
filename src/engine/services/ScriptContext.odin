package services

// wire:service

import classes "../classes"
import vm "../vm"

ScriptContext_Class := classes.Class_Info{
	name   = "ScriptContext",
	parent = &Service_Class,
}

ScriptContext :: struct {
	using service: Service,
	vm_state:      ^vm.VM,
}

ScriptContext_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	script_context := new(ScriptContext)
	script_context.service = Service_Init(&ScriptContext_Class, "ScriptContext", data_model)

	model := cast(^DataModel)data_model
	if model != nil && model.registry != nil {
		script_context.vm_state = model.registry.vm_state
	}

	return &script_context.object
}

ScriptContext_Get_VM :: proc(script_context: ^ScriptContext) -> ^vm.VM {
	if script_context == nil {
		return nil
	}
	return script_context.vm_state
}

ScriptContext_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	script_context := cast(^ScriptContext)object
	script_context.vm_state = nil
	classes.Object_Destroy(object)
	free(script_context)
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
