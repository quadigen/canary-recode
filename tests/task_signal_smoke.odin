package main

import "core:fmt"
import platform "../src/engine/platform"
import engine_runtime "../src/engine/runtime"
import renderer "../src/engine/renderer"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.RunInternal(script_vm, source, name)
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
assert(typeof(Signal.new()) == "KinemiumSignal")
assert(game:GetService("TaskScheduler").PendingTaskCount == 0)
assert(type(settings()) == "table")
assert(type(game.PrivateServerId) == "string")
assert(workspace.Terrain == game:GetService("Terrain"))
assert(typeof(BrickColor.random().Color) == "Color3")

local part = Instance.new("Part")
local raycast = RaycastParams.new()
raycast.FilterDescendantsInstances = {part, {{part}}, {}}
assert(#raycast.FilterDescendantsInstances == 2)
assert(not pcall(function() raycast.FilterDescendantsInstances = {part, {"bad"}} end))
assert(#raycast.FilterDescendantsInstances == 2)
part:Destroy()

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
assert(spawned, "task.spawn must run immediately")

local newThread = coroutine.create(function(value)
    assert(value == "first resume")
    coroutine.yield()
    assert(coroutine.yield() == "third resume")
end)
task.spawn(newThread, "first resume")
task.spawn(newThread, "second resume")
task.spawn(newThread, "third resume")
assert(coroutine.status(newThread) == "dead")

local reusable
local calls = {}
reusable = coroutine.create(function()
    while true do
        local fn, argument = coroutine.yield()
        fn(argument)
    end
end)
assert(coroutine.resume(reusable))
task.spawn(reusable, function(value) table.insert(calls, value) end, "first")
task.spawn(reusable, function(value) table.insert(calls, value) end, "second")
assert(table.concat(calls, ",") == "first,second")

local parent = Instance.new("Configuration", game:GetService("ReplicatedStorage"))
local dependency = Instance.new("ModuleScript", parent)
dependency.Name = "Dependency"
dependency.Source = "return { token = true }"
local module = Instance.new("ModuleScript", parent)
module.Source = [[
    task.wait(0.2)
    return require("./Dependency")
]]
required = 0
task.spawn(function()
    firstResult = require(module)
    required += 1
end)
task.spawn(function()
    secondResult = require(module)
    required += 1
end)
assert(required == 0)

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
assert(not delayed and waited and not cancelledRan)
`, "task_signal_second_frame")

	engine_runtime.Environment_Render_Step(&environment, &script_vm, 0.1)
	run_script(&script_vm, `
assert(delayed and waited and not cancelledRan)
assert(required == 2 and firstResult == secondResult and firstResult.token)
assert(game:GetService("TaskScheduler").PendingTaskCount == 0)
`, "task_signal_third_frame")

	run_script(&script_vm, `
local gui = game:GetService("GuiService")
local topLeft, bottomRight = gui:GetGuiInset()
assert(topLeft == Vector2.zero and bottomRight == Vector2.zero)
assert(not gui:IsTenFootInterface())

local actions = game:GetService("ContextActionService")
actionOrder = {}
actions:BindAction("keyboard", function(name, state, event)
    assert(name == "keyboard" and event.KeyCode == Enum.KeyCode.A)
    table.insert(actionOrder, "normal")
    return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.A)
actions:BindActionAtPriority("first", function(name, state, event)
    assert(state == Enum.UserInputState.Begin and event.UserInputState == state)
    table.insert(actionOrder, "high")
    actions:UnbindAction(name)
    return Enum.ContextActionResult.Pass
end, false, 3000, Enum.PlayerActions.CharacterLeft)
`, "context_action_setup")

	key_down: platform.Event
	key_down.type = .KEY_DOWN
	key_down.key.scancode = .A
	engine_runtime.Environment_SetEvent(&environment, &script_vm, key_down)
	engine_runtime.Environment_SetEvent(&environment, &script_vm, key_down)
	run_script(&script_vm, `
assert(table.concat(actionOrder, ",") == "high,normal,normal")
`, "context_action_dispatch")

	run_script(&script_vm, `
local storage = game:GetService("ReplicatedStorage")
local legacy = Instance.new("Script", game:GetService("ServerStorage"))
legacy.Source = "_G.hiddenScriptRan = true"
local client = Instance.new("Script", storage)
client.RunContext = Enum.RunContext.Client
client.Source = "_G.clientContextRan = true"
local server = Instance.new("Script", storage)
server.RunContext = Enum.RunContext.Server
server.Source = "_G.serverContextRan = true"
`, "run_context_setup")
	engine_runtime.Environment_Set_Mode(&environment, .Server)
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 0.1)
	run_script(&script_vm, `
assert(_G.serverContextRan and not _G.clientContextRan and not _G.hiddenScriptRan)
`, "server_run_context")
	engine_runtime.Environment_Set_Mode(&environment, .Client)
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 0.1)
	run_script(&script_vm, `
assert(_G.clientContextRan and not _G.hiddenScriptRan)
`, "client_run_context")

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("TASK_SIGNAL_SMOKE_PASSED")
}
