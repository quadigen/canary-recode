package main

import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

must :: proc(script_vm: ^vm.VM, source: string) {
	ok, err := vm.RunInternal(script_vm, source, "debugger_scheduler_test")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("debugger scheduler test failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm)
	defer {
		engine_runtime.Environment_Destroy(&env)
		vm.Close(&script_vm)
	}
	scheduler_record := services.Find_Service(&env.services, "TaskScheduler")
	assert(scheduler_record != nil && scheduler_record.object != nil)
	scheduler := cast(^services.TaskScheduler)scheduler_record.object

	must(
		&script_vm,
		`
local sc = game:GetService("ScriptContext")
assert(sc:DebugEnable(true))
assert(sc:DebugSetBreakpoint("=TaskScript", 4, true))
workspace:SetAttribute("DebugSchedulerFinished", false)
`,
	)

	thread := vm.NewThread(script_vm.L)
	ref := vm.RetainValue(script_vm.L)
	vm.Pop(script_vm.L)
	defer vm.ReleaseValue(script_vm.L, ref)
	source := `task.defer(function()
    local value = 41
    value += 1
    workspace:SetAttribute("DebugSchedulerFinished", value)
end)`
	ok, err := vm.LoadSource(&script_vm, thread, source, "=TaskScript")
	if !ok {fmt.eprintln(err); delete(err); panic("load failed")}
	finished, yielded, message, trace := vm.ResumeThreadTraceback(thread, script_vm.L)
	defer delete(message)
	defer delete(trace)
	assert(finished && !yielded && message == "")
	services.Task_Scheduler_Step(scheduler, 0.016)
	services.Task_Scheduler_Step(scheduler, 0.016)

	paused := vm.Debugger_PausedThreads(script_vm.L)
	assert(len(paused) == 1)
	pending := paused[0]
	delete(paused)
	assert(vm.Debugger_IsPaused(pending))

	services.Task_Scheduler_Step(scheduler, 0.016)
	assert(vm.Debugger_IsPaused(pending))
	assert(services.TaskScheduler_Owns_Thread(scheduler, pending))

	must(
		&script_vm,
		`
local sc = game:GetService("ScriptContext")
local paused = sc:DebugGetPausedThreads()
assert(#paused == 1)
assert(sc:DebugResume(paused[1].id, "continue"))
`,
	)
	services.Task_Scheduler_Step(scheduler, 0.016)
	assert(!vm.Debugger_IsPaused(pending))
	must(
		&script_vm,
		`
assert(workspace:GetAttribute("DebugSchedulerFinished") == 42)
local sc = game:GetService("ScriptContext")
assert(#sc:DebugGetPausedThreads() == 0)
assert(sc:DebugEnable(false))
`,
	)
	fmt.println("LUAU_DEBUGGER_SCHEDULER_SMOKE_PASSED")
}
