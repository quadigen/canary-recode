package classes

import "core:strings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

Script_Execution_State :: enum {
	NotStarted,
	Started,
	Errored,
}

Script_Class := Class_Info{
	name   = "Script",
	parent = &Instance_Class,
}

Script_Module_State :: enum {
	Unloaded,
	Loading,
	Loaded,
}

Script :: struct {
	using object: Object,

	source:          string,
	execution_state: Script_Execution_State,

	module_state: Script_Module_State,
	module_ref:   i32,
}

Script_Apply_Environment :: proc(
	L: ^vm.State,
	object: ^Object,
) -> bool {
	if L == nil || object == nil {
		return false
	}

	vm.NewTable(L, 0, 2)

	// script = <this Script/ModuleScript>
	Push_Object(L, object)
	vm.SetField(L, -2, "script")

	// metatable = {
	//     __index = shared engine globals
	// }
	vm.NewTable(L, 0, 1)

	vm.PushGlobals(L)
	vm.SetField(L, -2, "__index")

	// [chunk, environment, metatable]
	if !vm.SetMetatable(L, -2) {
		vm.Pop(L)
		return false
	}

	// [chunk, environment]
	//
	// lua_setfenv consumes the environment
	return vm.SetFunctionEnvironment(L, -2)
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

script_member_security :: proc() -> [2]Member_Security {
	return [2]Member_Security{
		Property_Read_Security(
			"Source",
			vm.SecurityRequirementFromValue(datatypes.SECURITY_CAPABILITY_INTERNAL_SCRIPT_SOURCE_READ),
		),
		Property_Write_Security(
			"Source",
			vm.SecurityRequirementFromValue(datatypes.SECURITY_CAPABILITY_INTERNAL_SCRIPT_SOURCE_WRITE),
		),
	}
}

script_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^Script)source
	dst := cast(^Script)destination

	delete(dst.source)

	dst.source       = strings.clone(src.source)
	dst.module_state = .Unloaded
	dst.module_ref   = -1
	dst.execution_state = .NotStarted
}

Register_Script :: proc(registry: ^Registry) {
	rules := script_member_security()
	Register_Class(
		registry,
		&Script_Class,
		script_construct,
		script_destroy,
		get = script_get,
		set = script_set,
		clone = script_clone,
		member_security = rules[:],
		properties = []string{"Source"},
	)
}