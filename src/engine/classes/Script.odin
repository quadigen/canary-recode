package classes

import "core:strings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

Script_Class := Class_Info{
	name   = "Script",
	parent = &Instance_Class,
}

Script :: struct {
	using object: Object,
	using common: Script_Common,
}

Script_Init :: proc(class: ^Class_Info = nil, name: string = "Script") -> Script {
	resolved_class := class
	if resolved_class == nil { resolved_class = &Script_Class }
	return Script{
		object = Object_Init(resolved_class, name),
		common = Script_Common{
			enabled         = true,
			module_state    = .Unloaded,
			module_ref      = -1,
			execution_state = .NotStarted,
			thread_ref      = -1,
		},
	}
}

// Script_Set_Source replaces a Script's source text, invalidating its module
// cache and any running thread.
Script_Set_Source :: proc(script: ^Script, source: string) {
	if script == nil {
		return
	}
	L := script_vm_state(script.signal_registry)
	Script_Common_Set_Source(L, &script.common, source)
}

Script_Set_Enabled :: proc(script: ^Script, enabled: bool) {
	if script == nil {
		return
	}
	Script_Common_Set_Enabled(&script.common, enabled)
}

Script_Get_Enabled :: proc(script: ^Script) -> bool {
	if script == nil {
		return false
	}
	return script.enabled
}

script_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	script := new(Script)
	script^ = Script_Init()
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
	case "Source":
		vm.PushString(L, script.source)
	case "Enabled":
		vm.PushBoolean(L, script.enabled)
	case:
		return false
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
	script := cast(^Script)object
	switch key {
	case "Source":
		Script_Set_Source(script, vm.ArgString(L, value_index))
	case "Enabled":
		Script_Set_Enabled(script, vm.ArgBoolean(L, value_index))
	case:
		return false
	}
	return true
}

script_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	script := cast(^Script)object
	L := script_vm_state(object.signal_registry)
	Script_Release_Module(L, &script.common)
	Script_Release_Thread(L, &script.common)
	delete(script.source)
	script.source = ""
	Object_Destroy(object)
	free(script)
}

script_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^Script)source
	dst := cast(^Script)destination

	L := script_vm_state(dst.signal_registry)
	Script_Release_Module(L, &dst.common)
	Script_Release_Thread(L, &dst.common)

	delete(dst.source)
	dst.source          = strings.clone(src.source)
	dst.enabled         = src.enabled
	dst.module_state      = .Unloaded
	dst.module_ref        = -1
	dst.thread            = nil
	dst.thread_ref        = -1
	dst.execution_state   = .NotStarted
	dst.restart_requested = false
}

Register_Script :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&Script_Class,
		script_construct,
		script_destroy,
		get = script_get,
		set = script_set,
		clone = script_clone,
		properties = []string{"Source", "Enabled"},
	)
}
