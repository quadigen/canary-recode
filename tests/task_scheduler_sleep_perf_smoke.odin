package main

import runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:time"

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.RunInternal(v, source, "scheduler_sleep_perf")
	assert(ok, err)
}

main :: proc() {
	v := vm.New()
	env: runtime.Environment
	runtime.Environment_Init(&env, &v)
	defer {runtime.Environment_Destroy(&env); vm.Close(&v)}
	scheduler := cast(^services.TaskScheduler)services.Ensure_Service(
		&env.services,
		"TaskScheduler",
	)
	top := vm.StackTop(v.L)
	run(&v, `
local function noop() end
for i=1,12000 do task.delay(3600, noop) end
`)
	assert(len(scheduler.tasks) == 12000)
	for sample in 0 ..< 5 {
		start := time.tick_now()
		for _ in 0 ..< 10000 {services.Task_Scheduler_Step(scheduler, 0.001)}
		fmt.println(
			"SCHEDULER_SLEEP_MS",
			sample,
			time.duration_milliseconds(time.tick_since(start)),
		)
	}
	assert(len(scheduler.tasks) == 12000)
	run(
		&v,
		`
order={}
local function push(v) table.insert(order,v) end
task.delay(0.125,function() push("delay") end)
task.defer(function() push("defer"); task.defer(function() push("nested") end) end)
task.spawn(function() local elapsed=task.wait(0.125); assert(elapsed>=0.125); push("wait") end)
local c=task.delay(0.125,function() error("cancelled task ran") end)
task.cancel(c)
`,
	)
	assert(len(scheduler.tasks) == 12003)
	services.Task_Scheduler_Step(scheduler, 0.0625)
	run(&v, `assert(#order==0)`)
	services.Task_Scheduler_Step(scheduler, 0.0625)
	run(&v, `assert(table.concat(order,",")=="delay,defer,wait",table.concat(order,","))`)
	services.Task_Scheduler_Step(scheduler, 0.0625)
	services.Task_Scheduler_Step(scheduler, 0.0625)
	run(
		&v,
		`assert(table.concat(order,",")=="delay,defer,wait,nested"); game:GetService("TaskScheduler"):CancelAll()`,
	)
	assert(len(scheduler.tasks) == 0)
	run(&v, `task.delay(0,function() table.insert(order,"reset") end)`)
	services.Task_Scheduler_Step(scheduler, 0)
	run(&v, `assert(order[5]=="reset")`)
	assert(len(scheduler.tasks) == 0)
	assert(vm.StackTop(v.L) == top)
	fmt.println("TASK_SCHEDULER_SLEEP_PERF_SMOKE_PASSED")
}
