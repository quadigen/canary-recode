package classes

import "core:strings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

// ModuleScript is a reusable chunk of Luau that never executes on its own.
//
// It runs the first time `require()` is called on it and its return value (any
// Luau value, including nil) is cached on the Instance. Subsequent require calls
// within the same runtime return the cached value without re-running the module.
// Because each runtime owns its own Instances and VM, the cache is naturally
// isolated per runtime: a module required by the server never shares its value
// with a client.
ModuleScript_Class := Class_Info{
	name   = "ModuleScript",
	parent = &Instance_Class,
}

// ModuleScript_Module_State is kept as an alias so the require lifecycle enum
// has a discoverable name for module-specific code.
ModuleScript_Module_State :: Script_Module_State

ModuleScript :: struct {
	using object: Object,
	using common: Script_Common,
}

ModuleScript_Init :: proc(class: ^Class_Info = nil, name: string = "ModuleScript") -> ModuleScript {
	resolved_class := class
	if resolved_class == nil { resolved_class = &ModuleScript_Class }
	return ModuleScript{
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

// ModuleScript_Set_Source replaces the module source. Any previously cached
// require() result is dropped so the next require executes the new source,
// matching Roblox editing behavior.
ModuleScript_Set_Source :: proc(module: ^ModuleScript, source: string) {
	if module == nil {
		return
	}
	L := script_vm_state(module.signal_registry)
	Script_Common_Set_Source(L, &module.common, source)
}

ModuleScript_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	module := new(ModuleScript)
	module^ = ModuleScript_Init()
	return &module.object
}

ModuleScript_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	module := cast(^ModuleScript)object
	switch key {
	case "Source":
		vm.PushString(L, module.source)
	case:
		return false
	}
	return true
}

ModuleScript_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	module := cast(^ModuleScript)object
	switch key {
	case "Source":
		ModuleScript_Set_Source(module, vm.ArgString(L, value_index))
	case:
		return false
	}
	return true
}

ModuleScript_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	module := cast(^ModuleScript)object
	L := script_vm_state(object.signal_registry)
	Script_Release_Module(L, &module.common)
	Script_Release_Thread(L, &module.common)
	delete(module.source)
	module.source = ""
	Object_Destroy(object)
	free(module)
}

ModuleScript_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^ModuleScript)source
	dst := cast(^ModuleScript)destination

	L := script_vm_state(dst.signal_registry)
	Script_Release_Module(L, &dst.common)
	Script_Release_Thread(L, &dst.common)

	delete(dst.source)
	dst.source          = strings.clone(src.source)
	dst.module_state    = .Unloaded
	dst.module_ref      = -1
	dst.thread          = nil
	dst.thread_ref      = -1
	dst.execution_state = .NotStarted
}

Register_ModuleScript :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&ModuleScript_Class,
		ModuleScript_construct,
		ModuleScript_destroy,
		get = ModuleScript_get,
		set = ModuleScript_set,
		clone = ModuleScript_clone,
		properties = []string{"Source"},
	)
}

