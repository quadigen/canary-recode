package classes

import "core:strings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

ModuleScript_Class := Class_Info{
	name   = "ModuleScript",
	parent = &Instance_Class,
}

ModuleScript_Module_State :: enum {
	Unloaded,
	Loading,
	Loaded,
}

ModuleScript :: struct {
	using object: Object,
	source:       string,
	module_state: ModuleScript_Module_State,
	module_ref:   i32,
}

ModuleScript_Init :: proc(class: ^Class_Info = nil, name: string = "ModuleScript") -> ModuleScript {
	resolved_class := class
	if resolved_class == nil { resolved_class = &ModuleScript_Class }
	return ModuleScript{
		object     = Object_Init(resolved_class, name),
		module_ref = -1,
	}
}

ModuleScript_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	ModuleScript := new(ModuleScript)
	ModuleScript^ = ModuleScript_Init()
	return &ModuleScript.object
}

module_ModuleScript_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	ModuleScript := new(ModuleScript)
	ModuleScript^ = ModuleScript_Init(&ModuleScript_Class, "ModuleModuleScript")
	return &ModuleScript.object
}

ModuleScript_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	ModuleScript := cast(^ModuleScript)object
	switch key {
	case "Source": vm.PushString(L, ModuleScript.source)
	case: return false
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
	if key != "Source" { return false }
	ModuleScript := cast(^ModuleScript)object
	if ModuleScript.module_ref > 0 {
		vm.ReleaseValue(L, ModuleScript.module_ref)
		ModuleScript.module_ref = -1
	}
	ModuleScript.module_state = .Unloaded
	delete(ModuleScript.source)
	ModuleScript.source = strings.clone(vm.ArgString(L, value_index))
	return true
}

ModuleScript_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	ModuleScript := cast(^ModuleScript)object
	delete(ModuleScript.source)
	Object_Destroy(object)
	free(ModuleScript)
}

ModuleScript_member_security :: proc() -> [2]Member_Security {
	return [2]Member_Security{
		Property_Read_Security(
			"Source",
			vm.SecurityRequirementFromValue(datatypes.SECURITY_CAPABILITY_INTERNAL_SCRIPT_SOURCE_READ),
		),
		Property_Write_Security(
			"Source",
			vm.SecurityRequirementFromValue(datatypes.SECURITY_CAPABILITY_INTERNAL_SCRIPT_SOURCE_READ),
		),
	}
}

ModuleScript_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^ModuleScript)source
	dst := cast(^ModuleScript)destination

	delete(dst.source)

	dst.source       = strings.clone(src.source)
	dst.module_state = .Unloaded
	dst.module_ref   = -1
}

Register_ModuleScript :: proc(registry: ^Registry) {
	rules := ModuleScript_member_security()
	Register_Class(
		registry,
		&ModuleScript_Class,
		ModuleScript_construct,
		ModuleScript_destroy,
		get = ModuleScript_get,
		set = ModuleScript_set,
		clone = ModuleScript_clone,
		member_security = rules[:],
		properties = []string{"Source"},
	)
}

Register_ModuleModuleScript :: proc(registry: ^Registry) {
	rules := ModuleScript_member_security()
	Register_Class(
		registry,
		&ModuleScript_Class,
		module_ModuleScript_construct,
		ModuleScript_destroy,
		get = ModuleScript_get,
		set = ModuleScript_set,
		clone = ModuleScript_clone,
		member_security = rules[:],
		properties = []string{"Source"},
	)
}
