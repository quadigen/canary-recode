package services

import "base:runtime"
import "core:fmt"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

TaskScheduler_Class := classes.Class_Info{name = "TaskScheduler", parent = &Service_Class}

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
	L:            ^vm.State,
	tasks:        [dynamic]Scheduled_Task,
	elapsed:      f64,
	frame:        u64,
}

Task_Library_Entry :: struct {
	name:     string,
	callback: vm.CFunction,
}

task_scheduler_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	scheduler := new(TaskScheduler)
	scheduler.service = Service_Init(&TaskScheduler_Class, "TaskScheduler", data_model)
	return &scheduler.object
}

task_scheduler_get :: proc(L: ^vm.State, object: ^classes.Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, key: string) -> bool {
	scheduler := cast(^TaskScheduler)object
	switch key {
	case "PendingTaskCount": vm.PushNumber(L, f64(len(scheduler.tasks)))
	case "CancelAll": vm.PushUserdataMethod(L, key)
	case: return false
	}
	return true
}

cancel_all_tasks :: proc(scheduler: ^TaskScheduler) {
	if scheduler == nil { return }
	if scheduler.L != nil {
		for task in scheduler.tasks { vm.ReleaseValue(scheduler.L, task.thread_ref) }
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

// TaskScheduler_Cancel_Thread drops every pending resume for a thread and
// releases the retained references. Script contexts use it to stop a disabled or
// destroyed script without leaking the suspended thread.
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
	return cancelled
}

// task_scheduler_describe_thread names the script owning a thread so scheduled
// failures can be reported with script context.
task_scheduler_describe_thread :: proc(scheduler: ^TaskScheduler, thread: ^vm.State) -> string {
	script_context := cast(^ScriptContext)Service_Get_Service(&scheduler.service, "ScriptContext")
	if script_context == nil {
		return ""
	}
	return ScriptContext_Describe_Thread(script_context, thread)
}

task_scheduler_namecall :: proc(L: ^vm.State, object: ^classes.Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, method: string) -> (i32, bool) {
	if method != "CancelAll" { return 0, false }
	cancel_all_tasks(cast(^TaskScheduler)object)
	return 0, true
}

task_scheduler_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	scheduler := cast(^TaskScheduler)object
	delete(scheduler.tasks)
	classes.Object_Destroy(object)
	free(scheduler)
}

queue_function :: proc(scheduler: ^TaskScheduler, L: ^vm.State, function_index, first_argument: int, delay: f64, defer_frame: bool) -> i32 {
	if scheduler == nil || scheduler.destroyed { return vm.RaiseError(L, "TaskScheduler is unavailable") }
	if !vm.IsFunction(L, function_index) { return vm.RaiseError(L, "task callback must be a function") }

	source_top := vm.StackTop(L)
	thread := vm.NewThread(L)
	vm.CopyValueToThread(L, thread, function_index)
	argument_count := 0
	for index := first_argument; index <= source_top; index += 1 {
		vm.CopyValueToThread(L, thread, index)
		argument_count += 1
	}
	thread_ref := vm.RetainValue(L)
	wake_frame := scheduler.frame
	if defer_frame { wake_frame += 1 }
	append(&scheduler.tasks, Scheduled_Task{
		thread = thread,
		thread_ref = thread_ref,
		argument_count = i32(argument_count),
		wake_time = scheduler.elapsed+max(delay, 0),
		wake_frame = wake_frame,
	})
	return 1
}

task_spawn :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	return queue_function(cast(^TaskScheduler)vm.UpvaluePointer(L), L, 1, 2, 0, false)
}

task_defer :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	return queue_function(cast(^TaskScheduler)vm.UpvaluePointer(L), L, 1, 2, 0, true)
}

task_delay :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	delay := vm.ArgNumber(L, 1)
	return queue_function(cast(^TaskScheduler)vm.UpvaluePointer(L), L, 2, 3, delay, false)
}

task_wait :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	scheduler := cast(^TaskScheduler)vm.UpvaluePointer(L)
	if scheduler == nil || scheduler.destroyed { return vm.RaiseError(L, "TaskScheduler is unavailable") }
	// Remove the IsYieldable check - task.wait should work from any thread,
	// including the main script thread, not just spawned coroutines
	delay := max(vm.ArgOptionalNumber(L, 1, 0), 0)
	vm.PushCurrentThread(L)
	thread_ref := vm.RetainValue(L)
	vm.Pop(L)
	append(&scheduler.tasks, Scheduled_Task{
		thread = L,
		thread_ref = thread_ref,
		wake_time = scheduler.elapsed+delay,
		wake_frame = scheduler.frame,
		wait_started_at = scheduler.elapsed,
		resume_with_elapsed = true,
	})
	return vm.YieldThread(L)
}

task_cancel :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	scheduler := cast(^TaskScheduler)vm.UpvaluePointer(L)
	thread := vm.ThreadFromArgument(L, 1)
	if thread == nil { return vm.RaiseError(L, "task.cancel expects a thread") }
	for task, index in scheduler.tasks {
		if task.thread == thread {
			vm.ReleaseValue(scheduler.L, task.thread_ref)
			ordered_remove(&scheduler.tasks, index)
			break
		}
	}
	return 0
}

Install_Task_Library :: proc(scheduler: ^TaskScheduler, vm_state: ^vm.VM) {
	scheduler.L = vm_state.L
	vm.NewTable(vm_state.L, 0, 5)
	entries := [?]Task_Library_Entry{
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
	if scheduler == nil || scheduler.destroyed || scheduler.L == nil { return }
	scheduler.elapsed += f64(max(delta_time, 0))
	current_frame := scheduler.frame
	scheduler.frame += 1

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
		argument_count := int(task.argument_count)
		if task.resume_with_elapsed {
			vm.PushNumber(task.thread, scheduler.elapsed-task.wait_started_at)
			argument_count = 1
		}
		_, _, err, traceback := vm.ResumeThreadTraceback(task.thread, scheduler.L, argument_count)
		vm.ReleaseValue(scheduler.L, task.thread_ref)
		if err != "" {
			describe := task_scheduler_describe_thread(scheduler, task.thread)
			if len(describe) > 0 {
				if len(traceback) > 0 {
					fmt.eprintf("Script error in %s:\n%s\n", describe, traceback)
				} else {
					fmt.eprintf("Script error in %s:\n%s\n", describe, err)
				}
			} else {
				fmt.eprintf("Scheduled task failed: %s\n", err)
			}
			delete(err)
			delete(traceback)
		}
	}
	delete(ready)
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

