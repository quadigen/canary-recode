package classes

// Shared execution state for the three Roblox-style script classes.
//
// `Script`, `LocalScript` and `ModuleScript` all embed `Script_Common` directly
// after `Object`, so the runtime can read a script's source, module cache and
// execution state without knowing the concrete class. Keeping the layout
// identical across the three classes means a single code path drives script
// execution and `require()` while the class hierarchy still distinguishes the
// Roblox-visible behavior (server script / client script / module).
//
// Isolation note: every runtime (server process, each connected client, or an
// in-process test runtime) owns its own VM and its own script instances, so the
// per-instance module cache below is automatically per-runtime. There is no
// global cache shared between runtimes.

import "core:fmt"
import "core:strings"

import vm "../vm"

Script_Execution_State :: enum {
	NotStarted,
	Started,
	Stopped,
	Errored,
}

Script_Module_State :: enum {
	Unloaded,
	Loading,
	Loaded,
}

Script_Common :: struct {
	source:          string,
	module_state:    Script_Module_State,
	module_ref:      i32,
	execution_state: Script_Execution_State,
	enabled:         bool,
	thread:          ^vm.State,
	thread_ref:      i32,
}

Script_Kind :: enum {
	Script,
	LocalScript,
	ModuleScript,
}

Script_Kind_Of :: proc(object: ^Object) -> (Script_Kind, bool) {
	if object == nil {
		return {}, false
	}
	switch {
	case Is_A(object, "Script"):
		return .Script, true
	case Is_A(object, "LocalScript"):
		return .LocalScript, true
	case Is_A(object, "ModuleScript"):
		return .ModuleScript, true
	}
	return {}, false
}

Script_Is_Script :: proc(object: ^Object) -> bool {
	_, ok := Script_Kind_Of(object)
	return ok
}

Script_Common_Of :: proc(object: ^Object) -> ^Script_Common {
	if object == nil {
		return nil
	}
	switch {
	case Is_A(object, "Script"):
		return &(cast(^Script)object).common
	case Is_A(object, "LocalScript"):
		return &(cast(^LocalScript)object).common
	case Is_A(object, "ModuleScript"):
		return &(cast(^ModuleScript)object).common
	}
	return nil
}

Script_Describe :: proc(object: ^Object) -> string {
	if object == nil {
		return "Script"
	}
	return fmt.aprintf("%s (%s)", Get_Class_Name(object), Get_Full_Name(object))
}

script_vm_state :: proc(registry: ^Registry) -> ^vm.State {
	if registry == nil || registry.vm_state == nil {
		return nil
	}
	return registry.vm_state.L
}

Script_Release_Module :: proc(L: ^vm.State, common: ^Script_Common) {
	if common == nil {
		return
	}
	if L != nil {
		vm.ReleaseValue(L, common.module_ref)
	}
	common.module_ref = -1
	common.module_state = .Unloaded
}

Script_Release_Thread :: proc(L: ^vm.State, common: ^Script_Common) {
	if common == nil {
		return
	}
	if L != nil {
		vm.ReleaseValue(L, common.thread_ref)
	}
	common.thread = nil
	common.thread_ref = -1
}

Script_Reset :: proc(L: ^vm.State, common: ^Script_Common) {
	if common == nil {
		return
	}
	Script_Release_Module(L, common)
	Script_Release_Thread(L, common)
	common.execution_state = .NotStarted
}

Script_Common_Set_Source :: proc(L: ^vm.State, common: ^Script_Common, source: string) {
	if common == nil {
		return
	}
	Script_Reset(L, common)
	delete(common.source)
	common.source = strings.clone(source)
}

Script_Apply_Environment :: proc(L: ^vm.State, object: ^Object) -> bool {
	if L == nil || object == nil {
		return false
	}

	vm.NewTable(L, 0, 2)

	Push_Object(L, object)
	vm.SetField(L, -2, "script")

	vm.NewTable(L, 0, 1)
	vm.PushGlobals(L)
	vm.SetField(L, -2, "__index")

	if !vm.SetMetatable(L, -2) {
		vm.Pop(L)
		return false
	}

	return vm.SetFunctionEnvironment(L, -2)
}
