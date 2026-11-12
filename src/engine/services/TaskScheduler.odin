package services
// wire:service

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import profiling "../profiling"
import target "../target"
import tracy "../util/odin-tracy"
import vm "../vm"
import "core:fmt"

TaskScheduler_Class := classes.Class_Info {
	name   = "TaskScheduler",
	parent = &Service_Class,
}

Scheduled_Task :: struct {
	thread:              ^vm.State,
	thread_ref:          i32,
	argument_count:      i32,
	wake_time:           f64,
	wake_frame:          u64,
	wait_started_at:     f64,
	resume_with_elapsed: bool,
}

TaskScheduler :: struct {
	using service: Service,
	L:             ^vm.State,
	tasks:         [dynamic]Scheduled_Task,
	elapsed:       f64,
	frame:         u64,
}

Task_Library_Entry :: struct {
	name:     string,
	callback: vm.CFunction,
}

task_scheduler_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	scheduler := new(TaskScheduler)
	scheduler.service = Service_Init(&TaskScheduler_Class, "TaskScheduler", data_model)
	return &scheduler.object
}

task_scheduler_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	scheduler := cast(^TaskScheduler)object
	switch key {
	case "PendingTaskCount":
		vm.PushNumber(L, f64(len(scheduler.tasks)))
	case "CancelAll":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

cancel_all_tasks :: proc(scheduler: ^TaskScheduler) {
	if scheduler == nil {return}
	if scheduler.L != nil {
		for task in scheduler.tasks {
			classes.Require_Forget_Thread(scheduler.signal_registry, task.thread)
			vm.ReleaseValue(scheduler.L, task.thread_ref)
		}
	}
	clear(&scheduler.tasks)
}

TaskScheduler_Owns_Thread :: proc(scheduler: ^TaskScheduler, thread: ^vm.State) -> bool {
	if scheduler == nil || thread == nil {
		return false
	}
	for task in scheduler.tasks {
		if task.thread == thread {
			return true
		}
	}
	return false
}


TaskScheduler_Cancel_Thread :: proc(scheduler: ^TaskScheduler, thread: ^vm.State) -> bool {
	if scheduler == nil || thread == nil {
		return false
	}
	cancelled := false
	for index := len(scheduler.tasks) - 1; index >= 0; index -= 1 {
		if scheduler.tasks[index].thread == thread {
			vm.ReleaseValue(scheduler.L, scheduler.tasks[index].thread_ref)
			ordered_remove(&scheduler.tasks, index)
			cancelled = true
		}
	}
	if cancelled {classes.Require_Forget_Thread(scheduler.signal_registry, thread)}
	return cancelled
}


task_scheduler_describe_thread :: proc(scheduler: ^TaskScheduler, thread: ^vm.State) -> string {
	script_context := cast(^ScriptContext)Service_Get_Service(&scheduler.service, "ScriptContext")
	if script_context == nil {
		return ""
	}
	return ScriptContext_Describe_Thread(script_context, thread)
}

task_scheduler_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	if method != "CancelAll" {return 0, false}
	cancel_all_tasks(cast(^TaskScheduler)object)
	return 0, true
}

task_scheduler_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	scheduler := cast(^TaskScheduler)object
	cancel_all_tasks(scheduler)
	if registry := object.signal_registry; registry != nil && registry.require_retry_ctx == scheduler {
		registry.require_schedule_retry = nil
		registry.require_retry_ctx = nil
	}
	delete(scheduler.tasks)
	classes.Object_Destroy(object)
	free(scheduler)
}

queue_function :: proc(
	scheduler: ^TaskScheduler,
	L: ^vm.State,
	function_index, first_argument: int,
	delay: f64,
	defer_frame: bool,
	label: string = "task.spawn",
	immediate := false,
) -> i32 {
	if scheduler == nil || scheduler.destroyed {
		return vm.RaiseError(L, "TaskScheduler is unavailable")
	}

	is_function := vm.IsFunction(L, function_index)
	is_thread := vm.IsThread(L, function_index)

	if !is_function && !is_thread {
		return vm.RaiseError(L, "task callback must be a function or thread")
	}

	source_top := vm.StackTop(L)

	thread: ^vm.State
	thread_ref: i32

	if is_function {
		thread = vm.NewThread(L)

		thread_name := label
		describe := task_scheduler_describe_thread(scheduler, L)

		if describe != "" {
			thread_name = fmt.tprintf("%s @ %s", label, describe)
		}

		profiling.set_thread_name(thread, thread_name, describe)

		vm.CopyValueToThread(L, thread, function_index)

		thread_ref = vm.RetainValue(L)
	} else {
		thread = vm.ThreadFromArgument(L, function_index)

		if thread == nil || vm.ThreadStatus(L, thread) != .Suspended {
			return vm.RaiseError(L, "task expects a suspended thread")
		}


		vm.PushValue(L, function_index)
		thread_ref = vm.RetainValue(L)
	}

	argument_count := 0

	for index := first_argument; index <= source_top; index += 1 {
		vm.CopyValueToThread(L, thread, index)
		argument_count += 1
	}

	wake_frame := scheduler.frame
	if defer_frame {
		wake_frame += 1
	}

	task := Scheduled_Task {
		thread = thread,
		thread_ref = thread_ref,
		argument_count = i32(argument_count),
		wake_time = scheduler.elapsed + max(delay, 0),
		wake_frame = wake_frame,
	}
	if immediate {
		task_resume(scheduler, task, L)
	} else {
		append(&scheduler.tasks, task)
	}

	return 1
}

task_spawn :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	return queue_function(cast(^TaskScheduler)vm.UpvaluePointer(L), L, 1, 2, 0, false, immediate = true)
}

task_defer :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	return queue_function(cast(^TaskScheduler)vm.UpvaluePointer(L), L, 1, 2, 0, true, "task.defer")
}

task_delay :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	delay := vm.ArgNumber(L, 1)
	return queue_function(
		cast(^TaskScheduler)vm.UpvaluePointer(L),
		L,
		2,
		3,
		delay,
		false,
		"task.delay",
	)
}

task_wait :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	scheduler := cast(^TaskScheduler)vm.UpvaluePointer(L)
	if scheduler == nil ||
	   scheduler.destroyed {return vm.RaiseError(L, "TaskScheduler is unavailable")}


	delay := max(vm.ArgOptionalNumber(L, 1, 0), 0)
	vm.PushCurrentThread(L)
	thread_ref := vm.RetainValue(L)
	vm.Pop(L)
	append(
		&scheduler.tasks,
		Scheduled_Task {
			thread = L,
			thread_ref = thread_ref,
			wake_time = scheduler.elapsed + delay,
			wake_frame = scheduler.frame,
			wait_started_at = scheduler.elapsed,
			resume_with_elapsed = true,
		},
	)
	return vm.YieldThread(L)
}

task_cancel :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	scheduler := cast(^TaskScheduler)vm.UpvaluePointer(L)
	thread := vm.ThreadFromArgument(L, 1)
	if thread == nil {return vm.RaiseError(L, "task.cancel expects a thread")}
	_ = TaskScheduler_Cancel_Thread(scheduler, thread)
	return 0
}

schedule_require_retry :: proc(ctx: rawptr, L: ^vm.State) {
	scheduler := cast(^TaskScheduler)ctx
	vm.PushCurrentThread(L)
	thread_ref := vm.RetainValue(L)
	vm.Pop(L)
	append(&scheduler.tasks, Scheduled_Task {
		thread = L,
		thread_ref = thread_ref,
		wake_frame = scheduler.frame,
	})
}

Install_Task_Library :: proc(scheduler: ^TaskScheduler, vm_state: ^vm.VM) {
	scheduler.L = vm_state.L
	scheduler.signal_registry.require_schedule_retry = schedule_require_retry
	scheduler.signal_registry.require_retry_ctx = scheduler
	vm.NewTable(vm_state.L, 0, 5)
	entries := [?]Task_Library_Entry {
		Task_Library_Entry{name = "spawn", callback = task_spawn},
		Task_Library_Entry{name = "defer", callback = task_defer},
		Task_Library_Entry{name = "delay", callback = task_delay},
		Task_Library_Entry{name = "wait", callback = task_wait},
		Task_Library_Entry{name = "cancel", callback = task_cancel},
	}
	for entry in entries {
		vm.PushLightUserdata(vm_state.L, scheduler)
		vm.PushFunction(vm_state.L, entry.name, entry.callback, 1)
		vm.SetField(vm_state.L, -2, entry.name)
	}
	vm.SetReadOnly(vm_state.L, -1)
	vm.SetGlobalFromStack(vm_state, "task")
}

Task_Scheduler_Step :: proc(scheduler: ^TaskScheduler, delta_time: f32) {
	if scheduler == nil || scheduler.destroyed || scheduler.L == nil {return}
	scheduler.elapsed += f64(max(delta_time, 0))
	current_frame := scheduler.frame
	scheduler.frame += 1
	if len(scheduler.tasks) == 0 {
		return
	}

	ready: [dynamic]Scheduled_Task
	pending: [dynamic]Scheduled_Task
	for task in scheduler.tasks {
		if task.wake_time <= scheduler.elapsed && task.wake_frame <= current_frame {
			append(&ready, task)
		} else {
			append(&pending, task)
		}
	}
	delete(scheduler.tasks)
	scheduler.tasks = pending

	for task in ready {
		task_resume(scheduler, task, scheduler.L)
	}
	delete(ready)
}

task_resume :: proc(scheduler: ^TaskScheduler, task: Scheduled_Task, from: ^vm.State) {
	tracy.ZoneNC("Scheduled Task Resume", 0xD19A66)
	argument_count := int(task.argument_count)
	if task.resume_with_elapsed {
		vm.PushNumber(task.thread, scheduler.elapsed - task.wait_started_at)
		argument_count = 1
	}
	finished, _, err, traceback := vm.ResumeThreadTraceback(task.thread, from, argument_count)
	defer vm.ReleaseValue(scheduler.L, task.thread_ref)
	if finished || err != "" {
		classes.Require_Forget_Thread(scheduler.signal_registry, task.thread)
	}
	if err != "" {
		describe := task_scheduler_describe_thread(scheduler, task.thread)
		detail := err
		if len(traceback) > 0 {
			detail = traceback
		}
		if target.is_playtest() {
			if len(describe) > 0 {
				log_service_emit_tagged(
					"ERROR",
					fmt.tprintf("Script error in %s:\n%s", describe, detail),
				)
			} else {
				log_service_emit_tagged("ERROR", fmt.tprintf("Scheduled task failed: %s", err))
			}
		} else if len(describe) > 0 {
			fmt.eprintf("Script error in %s:\n%s\n", describe, detail)
		} else {
			fmt.eprintf("Scheduled task failed: %s\n", err)
		}
		delete(err)
		delete(traceback)
	}
}

Register_TaskScheduler_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&TaskScheduler_Class,
		task_scheduler_construct,
		task_scheduler_destroy,
		creatable = false,
		get = task_scheduler_get,
		namecall = task_scheduler_namecall,
	)
}
