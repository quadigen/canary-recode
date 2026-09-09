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
		panic("task and signal smoke test failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	renderer_object: renderer.RendererObject
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm, &renderer_object)

	run_script(&script_vm, `
assert(type(task) == "table")
assert(type(task.spawn) == "function")
assert(typeof(Signal.new()) == "Signal")
assert(game:GetService("TaskScheduler").PendingTaskCount == 0)

spawned = false
deferred = false
delayed = false
waited = false
cancelledRan = false

task.spawn(function(value)
    assert(value == 42)
    spawned = true
    local elapsed = task.wait(0.2)
    assert(elapsed >= 0.2)
    waited = true
end, 42)

task.defer(function()
    deferred = true
end)

task.delay(0.25, function()
    delayed = true
end)

local cancelled = task.delay(0, function()
    cancelledRan = true
end)
task.cancel(cancelled)

signal = Signal.new()
signalTotal = 0
onceTotal = 0
waitA = nil
waitB = nil
listenerStarted = false
listenerFinished = false

connection = signal:Connect(function(a, b)
    signalTotal += a + b
    listenerStarted = true
    task.wait()
    listenerFinished = true
end)
assert(typeof(connection) == "KinemiumConnection")
assert(connection.Connected)

signal:Once(function(a)
    onceTotal += a
end)

task.spawn(function()
    waitA, waitB = signal:Wait()
end)
`, "task_signal_setup")

	engine_runtime.Environment_Render_Step(&environment, &script_vm, 0.1)
	run_script(&script_vm, `
assert(spawned)
assert(not deferred and not delayed and not waited and not cancelledRan)
signal:Fire(2, 3)
assert(signalTotal == 5 and onceTotal == 2)
assert(waitA == 2 and waitB == 3)
assert(listenerStarted and not listenerFinished)
signal:Fire(1, 1)
assert(signalTotal == 7 and onceTotal == 2)
connection:Disconnect()
assert(not connection.Connected)
signal:Fire(10, 10)
assert(signalTotal == 7)
`, "task_signal_fire")

	engine_runtime.Environment_Render_Step(&environment, &script_vm, 0.1)
	run_script(&script_vm, `
assert(deferred)
assert(listenerFinished)
assert(not delayed and not waited and not cancelledRan)
`, "task_signal_second_frame")

	engine_runtime.Environment_Render_Step(&environment, &script_vm, 0.1)
	run_script(&script_vm, `
assert(delayed and waited and not cancelledRan)
assert(game:GetService("TaskScheduler").PendingTaskCount == 0)
`, "task_signal_third_frame")

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("TASK_SIGNAL_SMOKE_PASSED")
}
