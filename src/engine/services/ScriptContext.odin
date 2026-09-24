package services

// wire:service

import "core:fmt"

import classes "../classes"
import profiling "../profiling"
import target "../target"
import tracy "../util/odin-tracy"
import vm "../vm"

ScriptContext_Class := classes.Class_Info {
	name   = "ScriptContext",
	parent = &Service_Class,
}

// Script_Thread tracks a live script thread so the context can reap it when it
// finishes and report scheduler-resumed failures with script context.
Script_Thread :: struct {
	object:      ^classes.Object,
	thread:      ^vm.State,
	description: string,
}

ScriptContext :: struct {
	using service:   Service,
	vm_state:        ^vm.VM,
	object_registry: ^classes.Registry,
	threads:         [dynamic]Script_Thread,
}

ScriptContext_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	script_context := new(ScriptContext)

	script_context.service = Service_Init(&ScriptContext_Class, "ScriptContext", data_model)

	model := cast(^DataModel)data_model

	if model != nil && model.registry != nil {
		script_context.vm_state = model.registry.vm_state
		script_context.object_registry = model.registry.classes
	}

	return &script_context.object
}

ScriptContext_Get_VM :: proc(script_context: ^ScriptContext) -> ^vm.VM {
	if script_context == nil {
		return nil
	}

	return script_context.vm_state
}

// ScriptContext_Mode reports the role of the runtime this context belongs to.
//
// The role is per Environment (and therefore per VM), not per process: a server
// process runs Scripts, a client process runs LocalScripts, and an editor
// runtime may host either side so in-editor playtesting works. Harnesses that
// build a server and a client Environment in one process set each role
// explicitly through Environment_Set_Mode.
ScriptContext_Mode :: proc(script_context: ^ScriptContext) -> target.Mode {
	if script_context == nil ||
	   script_context.service.data_model == nil ||
	   script_context.service.data_model.registry == nil {
		return target.current_mode
	}
	return script_context.service.data_model.registry.mode
}

script_context_forget_thread :: proc(script_context: ^ScriptContext, object: ^classes.Object) {
	if script_context == nil {
		return
	}
	for index := len(script_context.threads) - 1; index >= 0; index -= 1 {
		if script_context.threads[index].object == object {
			delete(script_context.threads[index].description)
			ordered_remove(&script_context.threads, index)
		}
	}
}

script_context_remember_thread :: proc(
	script_context: ^ScriptContext,
	object: ^classes.Object,
	thread: ^vm.State,
) {
	if script_context == nil {
		return
	}
	script_context_forget_thread(script_context, object)
	append(&script_context.threads, Script_Thread{
		object      = object,
		thread      = thread,
		description = classes.Script_Describe(object),
	})
}

// ScriptContext_Describe_Thread names the script that owns a script thread, or
// returns "" when the thread is not a script thread. The returned string is
// owned by the context and must not be freed by the caller.
ScriptContext_Describe_Thread :: proc(
	script_context: ^ScriptContext,
	thread: ^vm.State,
) -> string {
	if script_context == nil || thread == nil {
		return ""
	}
	for entry in script_context.threads {
		if entry.thread == thread {
			return entry.description
		}
	}
	return ""
}

script_context_task_scheduler :: proc(script_context: ^ScriptContext) -> ^TaskScheduler {
	if script_context == nil {
		return nil
	}
	object := Service_Get_Service(&script_context.service, "TaskScheduler")
	if object == nil || object.destroyed {
		return nil
	}
	return cast(^TaskScheduler)object
}

script_context_thread_is_scheduled :: proc(
	script_context: ^ScriptContext,
	thread: ^vm.State,
) -> bool {
	scheduler := script_context_task_scheduler(script_context)
	if scheduler == nil {
		return false
	}
	return TaskScheduler_Owns_Thread(scheduler, thread)
}

// script_context_report_error prints a script error with full identity and a
// Luau traceback. Errors are reported, never fatal: an error in one script must
// not take down unrelated scripts or the runtime.
script_context_report_error :: proc(
	script_context: ^ScriptContext,
	object: ^classes.Object,
	message: string,
	traceback: string,
) {
	_ = script_context
	name := classes.Get_Full_Name(object)
	if len(traceback) > 0 {
		fmt.eprintf("Script error in %s:\n%s\n", name, traceback)
	} else {
		fmt.eprintf("Script error in %s:\n%s\n", name, message)
	}
}

// script_context_is_active reports whether a script is reachable from the
// DataModel root. Roblox scripts only start once they are part of the game
// hierarchy, so an unparented Instance.new("Script") never runs.
script_context_is_active :: proc(object: ^classes.Object) -> bool {
	if object == nil || object.destroyed {
		return false
	}
	ancestor := object.parent
	for ancestor != nil {
		if classes.Is_A(ancestor, "DataModel") {
			return true
		}
		if ancestor.destroyed {
			return false
		}
		ancestor = ancestor.parent
	}
	return false
}

// script_context_should_run enforces the server/client boundary for the runtime
// this context belongs to. A Script never executes on a client and a LocalScript
// never executes on a server; editor runtimes host either side.
script_context_should_run :: proc(mode: target.Mode, object: ^classes.Object) -> bool {
	kind, ok := classes.Script_Kind_Of(object)
	if !ok || kind == .ModuleScript {
		return false
	}
	switch mode {
	case .Server:
		return kind == .Script
	case .Client:
		return kind == .LocalScript
	case .Editor:
		return true
	}
	return false
}

script_context_fail_script :: proc(
	script_context: ^ScriptContext,
	object: ^classes.Object,
	common: ^classes.Script_Common,
) {
	L := script_context.vm_state.L
	common.execution_state = .Errored
	classes.Script_Release_Thread(L, common)
	script_context_forget_thread(script_context, object)
}

script_context_finish_script :: proc(
	script_context: ^ScriptContext,
	object: ^classes.Object,
	common: ^classes.Script_Common,
) {
	L := script_context.vm_state.L
	// Parked in Stopped: the script ran (or was stopped) and must not restart.
	common.execution_state = .Stopped
	classes.Script_Release_Thread(L, common)
	script_context_forget_thread(script_context, object)
}

// script_context_stop_script cancels a running script, dropping any pending
// scheduler resume so a disabled script never wakes up again.
script_context_stop_script :: proc(
	script_context: ^ScriptContext,
	object: ^classes.Object,
	common: ^classes.Script_Common,
) {
	scheduler := script_context_task_scheduler(script_context)
	if scheduler != nil {
		TaskScheduler_Cancel_Thread(scheduler, common.thread)
	}
	script_context_finish_script(script_context, object, common)
}

// script_context_start creates the script's thread, installs its environment and
// runs it for the first time. A script that yields keeps its thread (retained in
// Script_Common) so it can be resumed later without leaking the VM thread.
script_context_start :: proc(
	script_context: ^ScriptContext,
	object: ^classes.Object,
	common: ^classes.Script_Common,
) -> bool {
	tracy.ZoneNC("Script Run", 0x98C379)
	z := profiling.Begin("Script Run", 0x98C379)

	main_thread := script_context.vm_state.L

	// Mark started before running so a re-entrant step, or a reparent during
	// execution, can never start the same script twice.
	common.execution_state = .Started

	thread := vm.NewThread(main_thread)
	thread_ref := vm.RetainValue(main_thread)
	vm.Pop(main_thread)

	common.thread = thread
	common.thread_ref = thread_ref
	script_context_remember_thread(script_context, object, thread)

	chunk_name := fmt.aprintf("@%s", classes.Get_Full_Name(object))
	defer delete(chunk_name)

	ok, load_error := vm.LoadSource(script_context.vm_state, thread, common.source, chunk_name)
	if !ok {
		if len(load_error) > 0 {
			script_context_report_error(script_context, object, load_error, "")
			delete(load_error)
		}
		script_context_fail_script(script_context, object, common)
		return false
	}

	if !classes.Script_Apply_Environment(thread, object) {
		script_context_report_error(
			script_context,
			object,
			"failed to create the script environment",
			"",
		)
		script_context_fail_script(script_context, object, common)
		return false
	}

	finished, yielded, resume_error, traceback := vm.ResumeThreadTraceback(thread, main_thread, 0)
	if resume_error != "" {
		script_context_report_error(script_context, object, resume_error, traceback)
		delete(resume_error)
		delete(traceback)
		script_context_fail_script(script_context, object, common)
		return false
	}

	_ = yielded

	if finished {
		script_context_finish_script(script_context, object, common)
	}

	return true
}

// ScriptContext_Run_Script starts one Script/LocalScript during the startup
// pass. It is idempotent: scripts that already ran, are disabled, have no
// source, or do not belong to this runtime are left untouched.
ScriptContext_Run_Script :: proc(script_context: ^ScriptContext, script: ^classes.Script) -> bool {
	if script_context == nil ||
	   script_context.vm_state == nil ||
	   script_context.vm_state.L == nil ||
	   script == nil ||
	   script.destroyed {
		return false
	}

	object := &script.object
	common := classes.Script_Common_Of(object)
	if common == nil || classes.Is_A(object, "ModuleScript") {
		return false
	}
	if !common.enabled || common.execution_state != .NotStarted {
		return false
	}
	if len(common.source) == 0 {
		return false
	}
	if !script_context_should_run(ScriptContext_Mode(script_context), object) {
		return false
	}

	return script_context_start(script_context, object, common)
}


// script_context_resume_script observes a live script thread.
//
//   * Finished/Error - the thread completed (possibly after a scheduler resume):
//     release it so the VM thread is never leaked.
//   * Suspended      - a script that yielded to something other than the task
//     scheduler has no resumer, so it is driven here. Threads awaiting
//     task.wait()/task.delay() are owned by the scheduler and must not be
//     resumed twice.
script_context_resume_script :: proc(
	script_context: ^ScriptContext,
	object: ^classes.Object,
	common: ^classes.Script_Common,
) {
	L := script_context.vm_state.L
	if common.thread == nil {
		return
	}

	switch vm.ThreadStatus(L, common.thread) {
	case .Finished:
		script_context_finish_script(script_context, object, common)
	case .Error:
		script_context_fail_script(script_context, object, common)
	case .Suspended:
		if script_context_thread_is_scheduled(script_context, common.thread) {
			return
		}
		_, _, resume_error, traceback := vm.ResumeThreadTraceback(common.thread, L, 0)
		if resume_error != "" {
			script_context_report_error(script_context, object, resume_error, traceback)
			delete(resume_error)
			delete(traceback)
			script_context_fail_script(script_context, object, common)
		}
	case .Running, .Normal:
		// Actively executing; leave it alone.
	}
}

ScriptContext_step :: proc(object: ^classes.Object, ctx: ^classes.Class_Step_Context) {
	tracy.ZoneNC("Scripts Start", 0x98C379)
	z := profiling.Begin("Scripts Start", 0x98C379)
	script_context := cast(^ScriptContext)object

	if script_context == nil ||
	   script_context.vm_state == nil ||
	   script_context.object_registry == nil {
		return
	}

	mode := ScriptContext_Mode(script_context)

	for descriptor in script_context.object_registry.classes {
		if descriptor == nil {
			continue
		}

		for instance in descriptor.instances {
			if instance == nil || instance.destroyed {
				continue
			}

			common := classes.Script_Common_Of(instance)
			if common == nil {
				continue
			}

			// ModuleScripts never execute on their own; require() drives them.
			kind, _ := classes.Script_Kind_Of(instance)
			if kind == .ModuleScript {
				continue
			}

			if !script_context_should_run(mode, instance) {
				continue
			}

			if !common.enabled {
				// Enabled = false prevents execution and stops a running script.
				if common.execution_state == .Started {
					script_context_stop_script(script_context, instance, common)
				}
				continue
			}

			switch common.execution_state {
			case .NotStarted:
				if len(common.source) == 0 || !script_context_is_active(instance) {
					continue
				}
				script_context_start(script_context, instance, common)
			case .Started:
				script_context_resume_script(script_context, instance, common)
			case .Stopped, .Errored:
				// A script executes at most once, matching Roblox: reparenting
				// or re-enabling does not run it again.
			}
		}
	}
}

ScriptContext_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	script_context := cast(^ScriptContext)object

	if script_context != nil {
		for entry in script_context.threads {
			delete(entry.description)
		}
		// Thread references themselves are owned by the script Instances and are
		// released when those Instances are destroyed.
		delete(script_context.threads)
		script_context.threads = nil
	}

	script_context.vm_state = nil
	script_context.object_registry = nil

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
		_step = ScriptContext_step,
		_step_phase = .Update,
	)
}
