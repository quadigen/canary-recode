package main

import classes "../src/engine/classes"
import runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:time"

main :: proc() {
	v := vm.New()
	env: runtime.Environment
	runtime.Environment_Init(&env, &v, nil, .Server)
	defer {runtime.Environment_Destroy(&env); vm.Close(&v)}
	sc := services.ScriptContext_From_Registry(&env.services)
	parent := services.Ensure_Service(&env.services, "ServerScriptService")
	top := vm.StackTop(v.L)
	objects := make([]^classes.Object, 1024)
	defer delete(objects)
	for i in 0 ..< len(objects) {
		obj, ok := classes.Push_New(&env.classes, &v, "Script")
		assert(ok && obj != nil)
		vm.Pop(v.L)
		name := fmt.aprintf("Lookup%d", i)
		classes.Set_Name(obj, name)
		delete(name)
		classes.Set_Parent(obj, parent)
		common := classes.Script_Common_Of(obj)
		classes.Script_Common_Set_Source(v.L, common, "coroutine.yield()")
		assert(services.ScriptContext_Run_Script(sc, obj))
		objects[i] = obj
	}
	assert(len(sc.threads) == len(objects))
	unknown := vm.NewThread(v.L)
	defer vm.Pop(v.L)
	assert(services.ScriptContext_Describe_Thread(sc, unknown) == "")
	checksum: int
	for sample in 0 ..< 5 {
		start := time.tick_now()
		for i in 0 ..< 1000000 {
			entry := sc.threads[i % len(sc.threads)]
			checksum += len(services.ScriptContext_Describe_Thread(sc, entry.thread))
			checksum += len(services.ScriptContext_Describe_Thread(sc, unknown))
		}
		fmt.println("SCRIPT_LOOKUP_MS", sample, time.duration_milliseconds(time.tick_since(start)))
	}
	assert(checksum > 0)
	removed := objects[500]
	old_thread := classes.Script_Common_Of(removed).thread
	vm.PushCurrentThread(old_thread)
	held := vm.RetainValue(old_thread)
	vm.Pop(old_thread)
	defer vm.ReleaseValue(v.L, held)
	services.ScriptContext_Forget_Script(sc, removed)
	assert(services.ScriptContext_Describe_Thread(sc, old_thread) == "")
	assert(len(sc.threads) == 1023)
	assert(sc.threads[500].object == objects[501])
	common := classes.Script_Common_Of(removed)
	common.execution_state = .NotStarted
	assert(services.ScriptContext_Run_Script(sc, removed))
	assert(len(sc.threads) == 1024 && sc.threads[1023].object == removed)
	for entry in sc.threads {assert(services.ScriptContext_Describe_Thread(sc, entry.thread) == entry.description)}
	services.ScriptContext_Stop_All(sc)
	assert(len(sc.threads) == 0)
	assert(
		services.ScriptContext_Describe_Thread(sc, classes.Script_Common_Of(objects[0]).thread) ==
		"",
	)
	assert(services.ScriptContext_Describe_Thread(sc, old_thread) == "")
	assert(vm.StackTop(v.L) == top + 1)
	fmt.println("SCRIPT_CONTEXT_LOOKUP_PERF_SMOKE_PASSED", checksum)
}
