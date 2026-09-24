package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import renderer "../src/engine/renderer"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("task_wait_os_library_test failed: " + name)
	}
}

main :: proc() {
	script_vm := vm.New()
	renderer_object: renderer.RendererObject
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm, &renderer_object)

	// Test 1: Verify task.wait works from main thread (outside task.spawn)
	// The key test: task.wait should work without needing task.spawn
	run_script(&script_vm, `
		-- task.wait should work from main thread without task.spawn
		-- It should return the elapsed time since the wait started
		local elapsed = task.wait(0.05)
		
		-- Verify we got a number back (the elapsed time)
		assert(type(elapsed) == "number", "task.wait should return a number")
		assert(elapsed >= 0, "task.wait elapsed should be >= 0")
		
		-- Mark success
		task_wait_from_main_thread_worked = true
	`, "task_wait_from_main_thread_test")

	// Step the environment with 0.1 seconds to let the 0.05s wait complete
	engine_runtime.Environment_Render_Step(&environment, &script_vm, 0.1)

	// Test 2: Verify os library is blocked
	run_script(&script_vm, `
		-- os should be nil (blocked by sandbox for security)
		assert(os == nil, "os library should be nil - use DateTime instead")
		
		-- Verify os functions are not accessible
		local ok, err = pcall(function() os.time() end)
		assert(not ok, "os.time() should not be accessible")
		
		ok, err = pcall(function() os.date("*t") end)
		assert(not ok, "os.date() should not be accessible")
		
		ok, err = pcall(function() os.clock() end)
		assert(not ok, "os.clock() should not be accessible")
		
		ok, err = pcall(function() os.getenv("PATH") end)
		assert(not ok, "os.getenv() should not be accessible")
		
		-- DateTime should be available as the engine-provided alternative
		local dt = DateTime.now()
		assert(typeof(dt) == "DateTime", "DateTime should be available")
		
		local ts = DateTime.now().UnixTimestamp
		assert(type(ts) == "number", "DateTime.UnixTimestamp should be a number")
	`, "os_library_blocked_test")

	// Test 3: Verify task.wait still works in spawned coroutines
	run_script(&script_vm, `
		spawn_executed = false
		spawn_elapsed = nil
		
		task.spawn(function()
			spawn_executed = true
			spawn_elapsed = task.wait(0.05)
		end)
		
		-- Spawned task runs async, so spawn_executed should still be false here
		assert(spawn_executed == false, "spawn should be async")
	`, "task_spawn_still_works_test")
	
	engine_runtime.Environment_Render_Step(&environment, &script_vm, 0.1)

	// Test 4: Verify task.delay still works
	run_script(&script_vm, `
		delayed_executed = false
		
		task.delay(0.02, function()
			delayed_executed = true
		end)
		
		assert(delayed_executed == false, "delay should not have executed yet")
	`, "task_delay_test")
	
	engine_runtime.Environment_Render_Step(&environment, &script_vm, 0.1)

	// Test 5: Verify task.defer still works
	run_script(&script_vm, `
		deferred_executed = false
		
		task.defer(function()
			deferred_executed = true
		end)
		
		assert(deferred_executed == false, "defer should not have executed yet")
	`, "task_defer_test")
	
	engine_runtime.Environment_Render_Step(&environment, &script_vm, 0.016) -- ~1 frame

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("TASK_WAIT_OS_LIBRARY_TESTS_PASSED")
}
