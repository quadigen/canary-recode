package classes

import "core:strings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

LocalScript_Execution_State :: enum {
	NotStarted,
	Started,
	Errored,
}

LocalScript_Class := Class_Info{
	name   = "LocalScript",
	parent = &Instance_Class,
}

LocalScript_Module_State :: enum {
	Unloaded,
	Loading,
	Loaded,
}

LocalScript :: struct {
	using object: Object,

	source:          string,
	execution_state: LocalScript_Execution_State,

	module_state: LocalScript_Module_State,
	module_ref:   i32,
}

LocalScript_Set_Source :: proc(LocalScript: ^LocalScript, source: string) {
	if LocalScript == nil {
		return
	}
	LocalScript.module_state = .Unloaded
	delete(LocalScript.source)
	LocalScript.source = strings.clone(source)
	LocalScript.execution_state = .NotStarted
}

LocalScript_Apply_Environment :: proc(
	L: ^vm.State,
	object: ^Object,
) -> bool {
	if L == nil || object == nil {
		return false
	}

	vm.NewTable(L, 0, 2)

	// LocalScript = <this LocalScript/ModuleLocalScript>
	Push_Object(L, object)
	vm.SetField(L, -2, "LocalScript")

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

LocalScript_Init :: proc(class: ^Class_Info = nil, name: string = "LocalScript") -> LocalScript {
	resolved_class := class
	if resolved_class == nil { resolved_class = &LocalScript_Class }
	return LocalScript{
		object     = Object_Init(resolved_class, name),
		module_ref = -1,
	}
}

LocalScript_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	LocalScript := new(LocalScript)
	LocalScript^ = LocalScript_Init()
	return &LocalScript.object
}

LocalScript_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	LocalScript := cast(^LocalScript)object
	switch key {
	case "Source": vm.PushString(L, LocalScript.source)
	case: return false
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
	if key != "Source" { return false }
	LocalScript := cast(^LocalScript)object
	if LocalScript.module_ref > 0 {
		vm.ReleaseValue(L, LocalScript.module_ref)
		LocalScript.module_ref = -1
	}
	LocalScript.module_state = .Unloaded
	delete(LocalScript.source)
	LocalScript.source = strings.clone(vm.ArgString(L, value_index))
	return true
}

LocalScript_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	LocalScript := cast(^LocalScript)object
	delete(LocalScript.source)
	Object_Destroy(object)
	free(LocalScript)
}

LocalScript_member_security :: proc() -> [2]Member_Security {
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

LocalScript_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^LocalScript)source
	dst := cast(^LocalScript)destination

	delete(dst.source)

	dst.source       = strings.clone(src.source)
	dst.module_state = .Unloaded
	dst.module_ref   = -1
	dst.execution_state = .NotStarted
}

Register_LocalScript :: proc(registry: ^Registry) {
	rules := LocalScript_member_security()
	Register_Class(
		registry,
		&LocalScript_Class,
		LocalScript_construct,
		LocalScript_destroy,
		get = LocalScript_get,
		set = LocalScript_set,
		clone = LocalScript_clone,
		member_security = rules[:],
		properties = []string{"Source"},
	)
}