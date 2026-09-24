package classes

import "core:strings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

// LocalScript is a client side script. It only executes in a client runtime and
// never on the server, mirroring Roblox's LocalScript class.
//
// Each client is an independent runtime (its own VM and its own script
// instances), so LocalScript state is never shared between clients. Inside the
// script, `script` refers to this Instance and the player context is reachable
// through `game:GetService("Players").LocalPlayer`.
LocalScript_Class := Class_Info{
	name   = "LocalScript",
	parent = &Instance_Class,
}

LocalScript :: struct {
	using object: Object,
	using common: Script_Common,
}

LocalScript_Init :: proc(class: ^Class_Info = nil, name: string = "LocalScript") -> LocalScript {
	resolved_class := class
	if resolved_class == nil { resolved_class = &LocalScript_Class }
	return LocalScript{
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

LocalScript_Set_Source :: proc(script: ^LocalScript, source: string) {
	if script == nil {
		return
	}
	L := script_vm_state(script.signal_registry)
	Script_Common_Set_Source(L, &script.common, source)
}

LocalScript_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	script := new(LocalScript)
	script^ = LocalScript_Init()
	return &script.object
}

LocalScript_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	script := cast(^LocalScript)object
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

LocalScript_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	script := cast(^LocalScript)object
	switch key {
	case "Source":
		LocalScript_Set_Source(script, vm.ArgString(L, value_index))
	case "Enabled":
		script.enabled = vm.ArgBoolean(L, value_index)
	case:
		return false
	}
	return true
}

LocalScript_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	script := cast(^LocalScript)object
	L := script_vm_state(object.signal_registry)
	Script_Release_Module(L, &script.common)
	Script_Release_Thread(L, &script.common)
	delete(script.source)
	script.source = ""
	Object_Destroy(object)
	free(script)
}

LocalScript_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^LocalScript)source
	dst := cast(^LocalScript)destination

	L := script_vm_state(dst.signal_registry)
	Script_Release_Module(L, &dst.common)
	Script_Release_Thread(L, &dst.common)

	delete(dst.source)
	dst.source          = strings.clone(src.source)
	dst.enabled         = src.enabled
	dst.module_state    = .Unloaded
	dst.module_ref      = -1
	dst.thread          = nil
	dst.thread_ref      = -1
	dst.execution_state = .NotStarted
}

Register_LocalScript :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&LocalScript_Class,
		LocalScript_construct,
		LocalScript_destroy,
		get = LocalScript_get,
		set = LocalScript_set,
		clone = LocalScript_clone,
		properties = []string{"Source", "Enabled"},
	)
}
