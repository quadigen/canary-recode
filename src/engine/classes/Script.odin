package classes

import "core:strings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

Script_Class := Class_Info{
	name   = "Script",
	parent = &Instance_Class,
}

ModuleScript_Class := Class_Info{
	name   = "ModuleScript",
	parent = &Script_Class,
}

Script_Module_State :: enum {
	Unloaded,
	Loading,
	Loaded,
}

Script :: struct {
	using object: Object,
	source:       string,
	module_state: Script_Module_State,
	module_ref:   i32,
}

Script_Init :: proc(class: ^Class_Info = nil, name: string = "Script") -> Script {
	resolved_class := class
	if resolved_class == nil { resolved_class = &Script_Class }
	return Script{
		object     = Object_Init(resolved_class, name),
		module_ref = -1,
	}
}

script_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	script := new(Script)
	script^ = Script_Init()
	return &script.object
}

module_script_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	script := new(Script)
	script^ = Script_Init(&ModuleScript_Class, "ModuleScript")
	return &script.object
}

script_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	script := cast(^Script)object
	switch key {
	case "Source": vm.PushString(L, script.source)
	case: return false
	}
	return true
}

script_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	if key != "Source" { return false }
	script := cast(^Script)object
	if script.module_ref > 0 {
		vm.ReleaseValue(L, script.module_ref)
		script.module_ref = -1
	}
	script.module_state = .Unloaded
	delete(script.source)
	script.source = strings.clone(vm.ArgString(L, value_index))
	return true
}

script_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	script := cast(^Script)object
	delete(script.source)
	Object_Destroy(object)
	free(script)
}

Register_Script :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Script_Class,
		script_construct,
		script_destroy,
		get = script_get,
		set = script_set,
	)
}

Register_ModuleScript :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&ModuleScript_Class,
		module_script_construct,
		script_destroy,
		get = script_get,
		set = script_set,
	)
}

