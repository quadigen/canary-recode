package services

// wire:service

import "core:fmt"

import classes "../classes"
import vm "../vm"
import tracy "../util/odin-tracy"
import profiling "../profiling"

ScriptContext_Class := classes.Class_Info{
	name   = "ScriptContext",
	parent = &Service_Class,
}

ScriptContext :: struct {
	using service: Service,

	vm_state:       ^vm.VM,
	object_registry: ^classes.Registry,
}

ScriptContext_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	script_context := new(ScriptContext)

	script_context.service = Service_Init(
		&ScriptContext_Class,
		"ScriptContext",
		data_model,
	)

	model := cast(^DataModel)data_model

	if model != nil && model.registry != nil {
		script_context.vm_state = model.registry.vm_state
		script_context.object_registry = model.registry.classes
	}

	return &script_context.object
}

ScriptContext_Get_VM :: proc(
	script_context: ^ScriptContext,
) -> ^vm.VM {
	if script_context == nil {
		return nil
	}

	return script_context.vm_state
}

ScriptContext_Run_Script :: proc(
	script_context: ^ScriptContext,
	script: ^classes.Script,
) -> bool {
	tracy.ZoneNC("Script Run", 0x98C379)
	z := profiling.Begin("Script Run", 0x98C379)
	if script_context == nil ||
	   script_context.vm_state == nil ||
	   script_context.vm_state.L == nil ||
	   script == nil ||
	   script.destroyed {
		return false
	}

	if classes.Is_A(&script.object, "ModuleScript") {
		return false
	}

	if script.execution_state != .NotStarted {
		return false
	}

	script.execution_state = .Started

	main_thread := script_context.vm_state.L

	thread := vm.NewThread(main_thread)

	thread_ref := vm.RetainValue(main_thread)

	vm.Pop(main_thread)

	defer vm.ReleaseValue(main_thread, thread_ref)

	chunk_name := fmt.tprintf(
		"@%s",
		classes.Get_Full_Name(&script.object),
	)
	defer delete(chunk_name)

	ok, load_error := vm.LoadSource(
		script_context.vm_state,
		thread,
		script.source,
		chunk_name,
	)

	if !ok {
		script.execution_state = .Errored

		fmt.eprintf(
			"%s: %s\n",
			chunk_name,
			load_error,
		)

		if load_error != "" {
			delete(load_error)
		}

		return false
	}

	if !classes.Script_Apply_Environment(
		thread,
		&script.object,
	) {
		script.execution_state = .Errored

		fmt.eprintf(
			"%s: failed to create script environment\n",
			chunk_name,
		)

		return false
	}

	finished, yielded, resume_error := vm.ResumeThread(
		thread,
		main_thread,
		0,
	)

	if resume_error != "" {
		script.execution_state = .Errored

		fmt.eprintf(
			"%s: %s\n",
			chunk_name,
			resume_error,
		)

		delete(resume_error)

		return false
	}

	_ = finished
	_ = yielded

	return true
}

ScriptContext_step :: proc(
	object: ^classes.Object,
	ctx: ^classes.Class_Step_Context,
) {
	tracy.ZoneNC("Scripts Start", 0x98C379)
	z := profiling.Begin("Scripts Start", 0x98C379)
	script_context := cast(^ScriptContext)object

	if script_context == nil ||
	   script_context.vm_state == nil ||
	   script_context.object_registry == nil {
		return
	}

	for descriptor in script_context.object_registry.classes {
		if descriptor == nil {
			continue
		}

		for instance in descriptor.instances {
			if instance == nil ||
			   instance.destroyed ||
			   !classes.Is_A(instance, "Script") ||
			   classes.Is_A(instance, "ModuleScript") {
				continue
			}

			script := cast(^classes.Script)instance

			if script.execution_state == .NotStarted {
				ScriptContext_Run_Script(
					script_context,
					script,
				)
			}
		}
	}
}

ScriptContext_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	script_context := cast(^ScriptContext)object

	script_context.vm_state = nil
	script_context.object_registry = nil

	classes.Object_Destroy(object)
	free(script_context)
}

Register_ScriptContext_Class :: proc(
	registry: ^classes.Registry,
) {
	classes.Register_Class(
		registry,
		&ScriptContext_Class,
		ScriptContext_construct,
		ScriptContext_destroy,
		creatable = false,
		_step = ScriptContext_step,
		_step_phase = .Update,
	)
}
