package main

// Roblox-style script execution semantics smoke test.
//
// It builds real runtimes (a server and two clients) with explicit roles and
// drives them frame by frame. Assertions run inside Luau (see `verify`), so they
// observe exactly what script code observes. Covered scenarios:
//
//	1.  basic Script execution
//	2.  basic LocalScript execution
//	3.  basic ModuleScript require
//	4.  ModuleScript caching
//	5.  server/client module cache isolation
//	6.  multiple clients with independent module state
//	7.  `script` referencing the correct Instance
//	8.  Enabled behavior
//	9.  script destruction while running
//	10. LocalScript not running on the server
//	11. Script not running on the client
//	12. circular ModuleScript dependencies
//	13. ModuleScript errors
//	14. yielding inside Scripts
//	15. yielding inside ModuleScripts
//	16. multiple Scripts requiring the same ModuleScript
//	17. replicated LocalScripts starting on clients
//	18. server/client access boundaries

import "core:fmt"
import "core:strings"

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

STEP_DT :: f32(1.0 / 60.0)
REPLICATION_PORT :: 39431
SERVER_ADDRESS :: "127.0.0.1"

failures := 0

fail :: proc(message: string) {
	failures += 1
	fmt.eprintln("FAILED:", message)
}

check :: proc(condition: bool, message: string) {
	if !condition {
		fail(message)
	}
}

part :: proc(index: int, title: string) {
	fmt.printf("PART %d: %s\n", index, title)
}

// run executes a setup chunk; a failure is fatal because later assertions would
// be meaningless.
run :: proc(v: ^vm.VM, source, name: string) {
	ok, err := vm.RunInternal(v, source, name)
	if !ok {
		fmt.eprintln("setup chunk failed:", name, err)
		delete(err)
		panic("script_semantics_smoke: setup failed")
	}
}

// verify runs Luau assertions. `expect` collects every failure in one chunk so a
// single run reports all of them.
verify :: proc(v: ^vm.VM, body: string, name: string) {
	source := strings.concatenate(
		{
			`
local __failures = {}
local function expect(condition, message)
	if not condition then
		table.insert(__failures, message)
	end
end
`,
			body,
			`
if #__failures > 0 then
	error(table.concat(__failures, "\n  "), 0)
end
`,
		},
	)
	defer delete(source)

	ok, err := vm.RunInternal(v, source, name)
	if !ok {
		fail(err)
		delete(err)
	}
}

step :: proc(environment: ^engine_runtime.Environment, v: ^vm.VM, frames: int) {
	for _ in 0..<frames {
		engine_runtime.Environment_Update_Step(environment, v, STEP_DT)
		engine_runtime.Environment_Render_Step(environment, v, STEP_DT)
	}
}

// step_seconds advances roughly `seconds` of simulated time. Each iteration
// steps both the update and the render phase, so the scheduler (which runs in
// both) sees two deltas per iteration.
step_seconds :: proc(environment: ^engine_runtime.Environment, v: ^vm.VM, seconds: f32) {
	step(environment, v, int(seconds / (2 * STEP_DT)) + 2)
}

state_of :: proc(object: ^classes.Object) -> classes.Script_Execution_State {
	common := classes.Script_Common_Of(object)
	if common == nil {
		return .NotStarted
	}
	return common.execution_state
}

service :: proc(environment: ^engine_runtime.Environment, name: string) -> ^classes.Object {
	return services.Ensure_Service(&environment.services, name)
}

descendant :: proc(root: ^classes.Object, name: string) -> ^classes.Object {
	if root == nil {
		return nil
	}
	descendants: [dynamic]^classes.Object
	defer delete(descendants)
	classes.append_descendants(&descendants, root)
	for instance in descendants {
		if instance != nil && instance.name == name {
			return instance
		}
	}
	return nil
}

make_local_player :: proc(
	environment: ^engine_runtime.Environment,
	v: ^vm.VM,
	id: u32,
	name: string,
) -> ^services.Player {
	players := cast(^services.Players)service(environment, "Players")
	if players == nil {
		return nil
	}
	player := services.Players_Add(players, v.L, id, name)
	players.local_player = player
	return player
}

scheduled_task_count :: proc(environment: ^engine_runtime.Environment) -> int {
	scheduler := cast(^services.TaskScheduler)service(environment, "TaskScheduler")
	if scheduler == nil {
		return -1
	}
	return len(scheduler.tasks)
}

main :: proc() {
	server_vm := vm.New()
	client_a_vm := vm.New()
	client_b_vm := vm.New()

	server: engine_runtime.Environment
	client_a: engine_runtime.Environment
	client_b: engine_runtime.Environment

	engine_runtime.Environment_Init(&server, &server_vm, nil, .Server)
	engine_runtime.Environment_Init(&client_a, &client_a_vm, nil, .Client)
	engine_runtime.Environment_Init(&client_b, &client_b_vm, nil, .Client)

	defer {
		vm.Close(&client_b_vm)
		vm.Close(&client_a_vm)
		vm.Close(&server_vm)
		engine_runtime.Environment_Destroy(&client_b)
		engine_runtime.Environment_Destroy(&client_a)
		engine_runtime.Environment_Destroy(&server)
	}

	client_a_player := make_local_player(&client_a, &client_a_vm, 1, "Player1")
	client_b_player := make_local_player(&client_b, &client_b_vm, 2, "Player2")
	if client_a_player == nil || client_b_player == nil {
		panic("script_semantics_smoke: clients need a local player")
	}

	// =====================================================================
	part(1, "basic Script execution (server)")
	// =====================================================================
	run(
		&server_vm,
		`
local bootstrap = Instance.new("Script", game:GetService("ServerScriptService"))
bootstrap.Name = "Bootstrap"
bootstrap.Source = [[
	_G.server_runs = (_G.server_runs or 0) + 1
	_G.server_full_name = script:GetFullName()
	_G.server_class_name = script.ClassName
	_G.server_parent_name = script.Parent.Name
	_G.server_has_game = game ~= nil
	_G.server_has_workspace = workspace ~= nil
	_G.server_env = getfenv and "has-getfenv" or nil
	game:GetService("ServerStorage").Name = "ServerStorage"
	_G.server_saw_server_storage = game:GetService("ServerStorage").Name
	local module = require(game.ReplicatedStorage.SharedMath)
	_G.server_module_value = module.double(21)
]]
`,
		"part1_setup",
	)

	run(
		&server_vm,
		`
local shared = Instance.new("ModuleScript", game:GetService("ReplicatedStorage"))
shared.Name = "SharedMath"
shared.Source = [[
	return { double = function(value) return value * 2 end }
]]
`,
		"part1_module_setup",
	)

	step(&server, &server_vm, 5)

	verify(
		&server_vm,
		`
expect(_G.server_runs == 1, "a Script runs exactly once")	expect(_G.server_full_name == "game.ServerScriptService.Bootstrap", "script:GetFullName()")
expect(_G.server_class_name == "Script", "script.ClassName")
expect(_G.server_parent_name == "ServerScriptService", "script.Parent")
expect(_G.server_has_game, "Scripts see game")
expect(_G.server_has_workspace, "Scripts see workspace")
expect(_G.server_saw_server_storage == "ServerStorage", "Scripts reach server-only services")
expect(_G.server_module_value == 42, "Scripts can require ModuleScripts")
`,
		"part1_verify",
	)

	// =====================================================================
	part(7, "`script` refers to the executing Instance")
	// =====================================================================
	run(
		&server_vm,
		`
local identity = Instance.new("Script", game:GetService("ServerScriptService"))
identity.Name = "Identity"
identity.Source = [[
	_G.identity_matches = (script == game.ServerScriptService.Identity)
	_G.identity_name = script.Name
	_G.identity_is_a = script:IsA("Script")
	_G.identity_child_member = game.ServerScriptService.Name
]]

for index = 1, 2 do
	local worker = Instance.new("Script", game:GetService("ServerScriptService"))
	worker.Name = "Worker" .. index
	worker.Source = [[
		_G.worker_names = _G.worker_names or {}
		table.insert(_G.worker_names, script.Name)
		_G.worker_script_matches = _G.worker_script_matches or {}
		table.insert(_G.worker_script_matches, script == game.ServerScriptService[script.Name])
	]]
end

local self_mod = Instance.new("ModuleScript", game:GetService("ReplicatedStorage"))
self_mod.Name = "ReturnsSelf"
self_mod.Source = "return script"
`,
		"part7_setup",
	)

	step(&server, &server_vm, 3)

	verify(
		&server_vm,
		`
expect(_G.identity_matches, "script is the running Instance")
expect(_G.identity_name == "Identity", "script.Name")
expect(_G.identity_is_a, "script:IsA")
expect(_G.identity_child_member == "ServerScriptService", "children are members (game.ServerScriptService)")
expect(#_G.worker_names == 2, "both workers ran")
expect(table.concat(_G.worker_names, ",") == "Worker1,Worker2", "each Script has its own script global")
expect(_G.worker_script_matches[1] and _G.worker_script_matches[2], "no script global sharing between scripts")
local module = require(game.ReplicatedStorage.ReturnsSelf)
expect(module == game.ReplicatedStorage.ReturnsSelf, "script in a ModuleScript is the ModuleScript")
expect(require(game.ReplicatedStorage.ReturnsSelf) == module, "require is cached and identical")
`,
		"part7_verify",
	)

	// =====================================================================
	part(10, "LocalScript does not run on the server")
	// =====================================================================
	run(
		&server_vm,
		`
local local_script = Instance.new("LocalScript", game:GetService("ReplicatedStorage"))
local_script.Name = "ServerSidedLocal"
local_script.Source = "_G.server_ran_local_script = true"
`,
		"part10_setup",
	)

	step(&server, &server_vm, 3)

	verify(
		&server_vm,
		`
expect(_G.server_ran_local_script == nil, "a LocalScript must not run on the server")
expect(game:GetService("ReplicatedStorage"):FindFirstChild("ServerSidedLocal") ~= nil, "the LocalScript exists")
`,
		"part10_verify",
	)

	{
		local_script := descendant(service(&server, "ReplicatedStorage"), "ServerSidedLocal")
		if state_of(local_script) != .NotStarted {
			fail("a server runtime must never start a LocalScript")
		}
	}

	// =====================================================================
	part(11, "Script does not run on the client")
	// =====================================================================
	run(
		&client_a_vm,
		`
local replicated = Instance.new("Script", workspace)
replicated.Name = "ReplicatedServerScript"
replicated.Source = "_G.client_ran_server_script = true"
`,
		"part11_setup",
	)

	step(&client_a, &client_a_vm, 3)

	verify(
		&client_a_vm,
		`
expect(_G.client_ran_server_script == nil, "a Script must not run on the client")
`,
		"part11_verify",
	)

	{
		replicated := descendant(service(&client_a, "Workspace"), "ReplicatedServerScript")
		if state_of(replicated) != .NotStarted {
			fail("a client runtime must never start a Script")
		}
	}

	// =====================================================================
	part(2, "basic LocalScript execution (client, via StarterPlayerScripts)")
	// =====================================================================
	run(
		&client_a_vm,
		`
local starter_player = game:GetService("StarterPlayer")
local template = starter_player:FindFirstChild("StarterPlayerScripts")
expect_type = template ~= nil
if template == nil then
	error("StarterPlayerScripts should exist on the client", 0)
end
local local_script = Instance.new("LocalScript", template)
local_script.Name = "ClientBootstrap"
local_script.Source = [[
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	_G.client_runs = (_G.client_runs or 0) + 1
	_G.client_player_name = player and player.Name or "none"
	_G.client_script_name = script.Name
	_G.client_class_name = script.ClassName
	_G.client_parent_name = script.Parent.Name
	_G.client_has_player_scripts = player.PlayerScripts ~= nil
	_G.client_has_player_gui = player.PlayerGui ~= nil
]]
`,
		"part2_setup",
	)

	step(&client_a, &client_a_vm, 3)

	verify(
		&client_a_vm,
		`
local Players = game:GetService("Players")
local player = Players.LocalPlayer
expect(_G.client_runs == 1, "the LocalScript runs once on the client")
expect(player ~= nil, "the client has a LocalPlayer")
expect(player.Name == "Player1", "the local player is the connected player")
expect(_G.client_player_name == "Player1", "LocalPlayer is visible to the LocalScript")
expect(_G.client_script_name == "ClientBootstrap", "script.Name")
expect(_G.client_class_name == "LocalScript", "script.ClassName")
expect(_G.client_parent_name == "PlayerScripts", "the starter copy runs under PlayerScripts")
expect(player.PlayerScripts:FindFirstChild("ClientBootstrap") ~= nil, "a copy lives in PlayerScripts")
expect(player.PlayerGui ~= nil, "PlayerGui exists for the local player")
`,
		"part2_verify",
	)

	// The template itself must not have executed.
	{
		template := descendant(service(&client_a, "StarterPlayer"), "ClientBootstrap")
		if template == nil {
			fail("the StarterPlayerScripts template should exist")
		} else if state_of(template) != .NotStarted {
			fail("a LocalScript in a starter template must not run in place")
		}
	}

	// =====================================================================
	part(8, "Enabled behavior")
	// =====================================================================
	run(
		&server_vm,
		`
-- Disabled before it becomes active, then enabled: it must not run until the
-- Enabled edge, and re-enabling a finished script restarts it.
local gated = Instance.new("Script")
gated.Name = "Gated"
gated.Enabled = false
gated.Source = [[
	_G.gated_runs = (_G.gated_runs or 0) + 1
]]
gated.Parent = game:GetService("ServerScriptService")

local restarter = Instance.new("Script", game:GetService("ServerScriptService"))
restarter.Name = "Restarter"
restarter.Source = [[
	_G.restarter_runs = (_G.restarter_runs or 0) + 1
]]

-- A script that waits forever while still running.
local waiting = Instance.new("Script", game:GetService("ServerScriptService"))
waiting.Name = "Waiting"
waiting.Source = [[
	_G.waiting_started = true
	task.wait(1)
	_G.waiting_resumed = true
]]
`,
		"part8_setup",
	)

	step(&server, &server_vm, 5)

	verify(
		&server_vm,
		`
expect(_G.gated_runs == nil, "Enabled = false prevents execution")
expect(_G.restarter_runs == 1, "an enabled script runs once")
expect(_G.waiting_started == true, "the waiting script started")
expect(_G.waiting_resumed == nil, "the waiting script is suspended")
`,
		"part8_verify_a",
	)

	// Disabling a *running* script stops it; re-enabling restarts it from the top.
	run(
		&server_vm,
		`
local scripts = game:GetService("ServerScriptService")
scripts.Waiting.Enabled = false
scripts.Restarter.Enabled = false
scripts.Restarter.Enabled = true
scripts.Gated.Enabled = true
`,
		"part8_disable",
	)

	step_seconds(&server, &server_vm, 1.2)

	verify(
		&server_vm,
		`
expect(_G.waiting_resumed == nil, "a disabled script never resumes")
expect(_G.restarter_runs == 2, "re-enabling a finished script restarts it")
expect(_G.gated_runs == 1, "enabling a disabled script starts it")
`,
		"part8_verify_b",
	)

	// =====================================================================
	part(9, "script destruction while running")
	// =====================================================================
	run(
		&server_vm,
		`
local victim = Instance.new("Script", game:GetService("ServerScriptService"))
victim.Name = "Victim"
victim.Source = [[
	_G.victim_started = true
	task.wait(1)
	_G.victim_resumed = true
]]

local bystander = Instance.new("Script", game:GetService("ServerScriptService"))
bystander.Name = "Bystander"
bystander.Source = [[
	_G.bystander_runs = (_G.bystander_runs or 0) + 1
]]
`,
		"part9_setup",
	)

	step(&server, &server_vm, 3)
	verify(&server_vm, `expect(_G.victim_started == true, "the victim started")`, "part9_verify_a")

	tasks_before := scheduled_task_count(&server)

	run(
		&server_vm,
		`game:GetService("ServerScriptService"):FindFirstChild("Victim"):Destroy()`,
		"part9_destroy",
	)

	// The destroy is flushed on the next step; the pending task.wait resume must
	// be cancelled with it.
	step_seconds(&server, &server_vm, 1.5)

	verify(
		&server_vm,
		`
expect(_G.victim_resumed == nil, "a destroyed script does not resume")
expect(game:GetService("ServerScriptService"):FindFirstChild("Victim") == nil, "the victim is gone")
expect(_G.bystander_runs == 1, "a destroyed script does not disturb others")
`,
		"part9_verify_b",
	)

	tasks_after := scheduled_task_count(&server)
	if tasks_after >= tasks_before {
		fail("destroying a script must cancel its scheduled resumes")
	}

	{
		// Engine scripts (for example the profiler overlay) legitimately keep a
		// thread, so the check is that the destroyed script left nothing behind.
		script_context := cast(^services.ScriptContext)service(&server, "ScriptContext")
		for entry in script_context.threads {
			if strings.contains(entry.description, "Victim") ||
			   (entry.object != nil && entry.object.destroyed) {
				fmt.eprintf("  live script thread at part 9: %s\n", entry.description)
				fail("a destroyed script must not leave a thread in the ScriptContext")
			}
		}
	}

	// =====================================================================
	part(14, "yielding inside Scripts")
	// =====================================================================
	run(
		&server_vm,
		`
local yielder = Instance.new("Script", game:GetService("ServerScriptService"))
yielder.Name = "Yielder"
yielder.Source = [[
	_G.yield_stage = "started"
	local elapsed = task.wait(0.4)
	_G.yield_stage = "resumed"
	_G.yield_elapsed = elapsed
	task.wait(0.05)
	_G.yield_stage = "finished"
]]

local spawner = Instance.new("Script", game:GetService("ServerScriptService"))
spawner.Name = "Spawner"
spawner.Source = [[
	task.spawn(function()
		_G.spawn_stage = "spawned"
		task.wait(0.2)
		_G.spawn_stage = "spawn-finished"
	end)
	task.defer(function()
		_G.defer_ran = true
	end)
]]
`,
		"part14_setup",
	)

	step_seconds(&server, &server_vm, 0.2)
	verify(
		&server_vm,
		`
expect(_G.yield_stage == "started", "task.wait suspends a Script")
expect(_G.defer_ran == true, "task.defer runs on the next resumption")
`,
		"part14_verify_a",
	)

	step_seconds(&server, &server_vm, 0.7)
	verify(
		&server_vm,
		`
expect(_G.yield_stage == "finished", "the Script ran to completion after yielding")
expect(type(_G.yield_elapsed) == "number" and _G.yield_elapsed > 0, "task.wait returns the elapsed time")
expect(_G.spawn_stage == "spawn-finished", "task.spawn runs independently")
`,
		"part14_verify_b",
	)

	{
		yielder := descendant(service(&server, "ServerScriptService"), "Yielder")
		if state_of(yielder) != .Stopped {
			fail("a finished Script releases its thread")
		}
	}

	// =====================================================================
	part(15, "yielding inside ModuleScripts")
	// =====================================================================
	{
		tasks_before := scheduled_task_count(&server)
		run(
			&server_vm,
			`
local slow = Instance.new("ModuleScript", game:GetService("ReplicatedStorage"))
slow.Name = "SlowModule"
slow.Source = [[
	_G.slow_runs = (_G.slow_runs or 0) + 1
	_G.slow_stage = "module-started"
	task.wait(0.6)
	_G.slow_stage = "module-resumed"
	return { ready = true, stage = _G.slow_stage }
]]

local consumer = Instance.new("Script", game:GetService("ServerScriptService"))
consumer.Name = "SlowConsumer"
consumer.Source = [[
	local slow = require(game.ReplicatedStorage.SlowModule)
	_G.consumer_ready = slow.ready
	_G.consumer_stage = slow.stage
	_G.consumer_after_require = true
]]
`,
			"part15_setup",
		)

		step_seconds(&server, &server_vm, 0.1)
		verify(
			&server_vm,
			`
expect(_G.slow_stage == "module-started", "the module started and suspended")
expect(_G.consumer_after_require == nil, "the requiring Script waits for the module")
`,
			"part15_verify_a",
		)

		step_seconds(&server, &server_vm, 1.0)
		verify(
			&server_vm,
			`
expect(_G.slow_stage == "module-resumed", "the module resumed")
expect(_G.consumer_ready == true, "require returned the module value after the yield")
expect(_G.consumer_stage == "module-resumed", "the module value reflects the post-yield state")
expect(_G.consumer_after_require == true, "the requiring Script continued")
expect(_G.slow_runs == 1, "the yielding module ran once")

-- The cached value is available without re-running the module.
local again = require(game.ReplicatedStorage.SlowModule)
expect(again.ready == true and _G.slow_runs == 1, "a yielded module caches its result")
`,
			"part15_verify_b",
		)
		_ = tasks_before
	}

	// =====================================================================
	part(3, "require, 4: ModuleScript caching, 16: many requirers")
	// =====================================================================
	run(
		&server_vm,
		`
local storage = game:GetService("ReplicatedStorage")
local counter = Instance.new("ModuleScript", storage)
counter.Name = "Counter"
counter.Source = [[
	_G.counter_runs = (_G.counter_runs or 0) + 1
	return { runs = _G.counter_runs, owner = script.Name }
]]

_G.module_ran_before_require = (_G.counter_runs ~= nil)

for index = 1, 3 do
	local consumer = Instance.new("Script", game:GetService("ServerScriptService"))
	consumer.Name = "CounterConsumer" .. index
	consumer.Source = [[
		local counter = require(game.ReplicatedStorage.Counter)
		_G.counter_seen = _G.counter_seen or {}
		table.insert(_G.counter_seen, counter.runs)
		_G.counter_first = _G.counter_first or counter
		_G.counter_same_table = (_G.counter_first == counter)
	]]
end
`,
		"part3_setup",
	)

	step(&server, &server_vm, 3)

	verify(
		&server_vm,
		`
expect(_G.module_ran_before_require == false, "a ModuleScript does not run on its own")
expect(_G.counter_runs == 1, "the module body runs exactly once")
expect(#_G.counter_seen == 3, "three Scripts required the module")
expect(table.concat(_G.counter_seen, ",") == "1,1,1", "every requirer gets the cached table")
expect(_G.counter_same_table == true, "requires return the same table instance")
expect(_G.counter_first.owner == "Counter", "the cached table keeps the module identity")
`,
		"part3_verify",
	)

	// =====================================================================
	part(13, "ModuleScript errors")
	// =====================================================================
	run(
		&server_vm,
		`
local storage = game:GetService("ReplicatedStorage")
local failing = Instance.new("ModuleScript", storage)
failing.Name = "Failing"
failing.Source = [[
	_G.failing_runs = (_G.failing_runs or 0) + 1
	error("module exploded")
]]

_G.failing_first_ok, _G.failing_message = pcall(function() return require(failing) end)
_G.failing_message = tostring(_G.failing_message)
_G.failing_runs_after_error = _G.failing_runs

failing.Source = [[
	_G.failing_runs = (_G.failing_runs or 0) + 1
	return "recovered"
]]
_G.failing_second_ok, _G.failing_recovered = pcall(function() return require(failing) end)
_G.failing_runs_after_fix = _G.failing_runs

local always = Instance.new("ModuleScript", storage)
always.Name = "AlwaysErrors"
always.Source = "error('nope')"
local survivor = Instance.new("Script", game:GetService("ServerScriptService"))
survivor.Name = "ErrorSurvivor"
survivor.Source = [[
	local ok = pcall(function() return require(game.ReplicatedStorage.AlwaysErrors) end)
	_G.survivor_recovered = not ok
	local ok2 = pcall(function() return require(game.ReplicatedStorage.Counter) end)
	_G.survivor_still_works = ok2
]]
`,
		"part13_setup",
	)

	step(&server, &server_vm, 3)

	verify(
		&server_vm,
		`
expect(_G.failing_first_ok == false, "a failing module raises to the caller")
expect(string.find(_G.failing_message, "module exploded") ~= nil, "the module error message survives")
expect(_G.failing_runs_after_error == 1, "the failing module body ran once")
expect(_G.failing_second_ok == true, "a fixed module can be required again")
expect(_G.failing_recovered == "recovered", "the fixed module returns its value")
expect(_G.failing_runs_after_fix == 2, "a failed module is not permanently cached")
expect(_G.survivor_recovered == true, "a module error does not stop other Scripts")
expect(_G.survivor_still_works == true, "unrelated requires keep working after an error")
`,
		"part13_verify",
	)

	// =====================================================================
	part(12, "circular ModuleScript dependencies")
	// =====================================================================
	run(
		&server_vm,
		`
local storage = game:GetService("ReplicatedStorage")
local cycle_a = Instance.new("ModuleScript", storage)
local cycle_b = Instance.new("ModuleScript", storage)
cycle_a.Name, cycle_b.Name = "CycleA", "CycleB"
cycle_a.Source = "return require(game.ReplicatedStorage.CycleB)"
cycle_b.Source = "return require(game.ReplicatedStorage.CycleA)"

_G.cycle_ok, _G.cycle_message = pcall(function() return require(cycle_a) end)
_G.cycle_message = tostring(_G.cycle_message)

local selfish = Instance.new("ModuleScript", storage)
selfish.Name = "Selfish"
selfish.Source = "return require(script)"
_G.self_cycle_ok, _G.self_cycle_message = pcall(function() return require(selfish) end)
_G.self_cycle_message = tostring(_G.self_cycle_message)

-- A second, independent require of the pair still terminates.
_G.cycle_second_ok = pcall(function() return require(cycle_a) end)

-- The runtime is healthy afterwards.
local after = Instance.new("Script", game:GetService("ServerScriptService"))
after.Name = "AfterCycle"
after.Source = "_G.after_cycle = true"
`,
		"part12_setup",
	)

	step(&server, &server_vm, 3)

	verify(
		&server_vm,
		`
expect(_G.cycle_ok == false, "a circular require raises instead of hanging")
expect(string.find(_G.cycle_message, "cyclic require") ~= nil, "the cycle error is descriptive")
expect(_G.self_cycle_ok == false, "a self-require raises")
expect(string.find(_G.self_cycle_message, "cyclic require") ~= nil, "the self-require error is descriptive")
expect(_G.cycle_second_ok == false, "a failed cycle leaves no half-initialized cache")
expect(_G.after_cycle == true, "the runtime keeps running after a cycle")
`,
		"part12_verify",
	)

	// =====================================================================
	part(7, "ModuleScript return value types")
	// =====================================================================
	run(
		&server_vm,
		`
local storage = game:GetService("ReplicatedStorage")
local function define(name, source)
	local mod = Instance.new("ModuleScript", storage)
	mod.Name = name
	mod.Source = source
	return mod
end

_G.kind_table = typeof(require(define("TableMod", "return { a = 1 }")))
_G.kind_function = typeof(require(define("FunctionMod", "return function() return 1 end")))
_G.kind_instance = typeof(require(define("InstanceMod", "return workspace")))
_G.kind_number = typeof(require(define("NumberMod", "return 42")))
_G.kind_string = typeof(require(define("StringMod", "return 'text'")))
_G.kind_boolean = typeof(require(define("BoolMod", "return true")))
_G.kind_nil = typeof(require(define("NilMod", "return nil")))
_G.kind_vector = typeof(require(define("VectorMod", "return Vector3.new(1, 2, 3)")))
_G.kind_color = typeof(require(define("ColorMod", "return Color3.new(1, 0, 0)")))
_G.kind_cframe = typeof(require(define("FrameMod", "return CFrame.new(1, 2, 3)")))
_G.nil_cached = (require(storage:FindFirstChild("NilMod")) == nil)
_G.function_callable = require(storage:FindFirstChild("FunctionMod"))() == 1
_G.instance_identity = require(storage:FindFirstChild("InstanceMod")) == workspace
`,
		"part7_types",
	)

	step(&server, &server_vm, 2)

	verify(
		&server_vm,
		`
expect(_G.kind_table == "table", "modules may return tables")
expect(_G.kind_function == "function", "modules may return functions")
expect(_G.kind_instance == "Instance", "modules may return Instances")
expect(_G.kind_number == "number", "modules may return numbers")
expect(_G.kind_string == "string", "modules may return strings")
expect(_G.kind_boolean == "boolean", "modules may return booleans")
expect(_G.kind_nil == "nil", "modules may return nil")	expect(_G.kind_vector == "vector", "modules may return userdata")
expect(_G.kind_color == "Color3", "modules may return datatype userdata")
expect(_G.kind_cframe == "CFrame", "modules may return CFrame values")
expect(_G.nil_cached == true, "a nil result is cached")
expect(_G.function_callable == true, "a returned function is callable")
expect(_G.instance_identity == true, "a returned Instance keeps its identity")
`,
		"part7_types_verify",
	)

	// =====================================================================
	part(14, "reparenting does not re-run a script")
	// =====================================================================
	run(
		&server_vm,
		`
local mover = Instance.new("Script", game:GetService("ServerScriptService"))
mover.Name = "Mover"
mover.Source = [[
	_G.mover_runs = (_G.mover_runs or 0) + 1
]]

-- Never active until parented: an unparented Script does not run.
local late = Instance.new("Script")
late.Name = "Late"
late.Source = [[
	_G.late_runs = (_G.late_runs or 0) + 1
]]
_G.unparented_script = late
`,
		"part14_reparent_setup",
	)

	step(&server, &server_vm, 3)
	verify(
		&server_vm,
		`
expect(_G.mover_runs == 1, "the mover ran once")
expect(_G.late_runs == nil, "an unparented Script does not run")
expect(game:GetService("ServerScriptService"):FindFirstChild("Mover") ~= nil, "the mover is present")
`,
		"part14_reparent_verify_a",
	)

	run(
		&server_vm,
		`
local scripts = game:GetService("ServerScriptService")
local mover = scripts:FindFirstChild("Mover")
mover.Parent = workspace
mover.Parent = scripts

-- The unparented Script becomes active after being parented.
_G.unparented_script.Parent = scripts
`,
		"part14_reparent_move",
	)

	step(&server, &server_vm, 3)

	verify(
		&server_vm,
		`
expect(_G.mover_runs == 1, "reparenting a finished Script does not re-run it")
expect(_G.late_runs == 1, "a Script runs once when it becomes active")
`,
		"part14_reparent_verify_b",
	)

	// =====================================================================
	part(5, "server/client module cache isolation, 6: independent clients")
	// =====================================================================
	// Every runtime owns its own Instances, VM and module cache. Each side runs
	// the same module source and must see its own execution and its own table.
	shared_module_setup := `
local storage = game:GetService("ReplicatedStorage")
local shared = Instance.new("ModuleScript", storage)
shared.Name = "SharedState"
shared.Source = [[
	local Players = game:GetService("Players")
	_G.shared_runs = (_G.shared_runs or 0) + 1
	return {
		runs = _G.shared_runs,
		where = Players.LocalPlayer and "client" or "server",
	}
]]
`
	run(&server_vm, shared_module_setup, "part5_server_module")
	run(&client_a_vm, shared_module_setup, "part5_client_a_module")
	run(&client_b_vm, shared_module_setup, "part5_client_b_module")

	run(
		&server_vm,
		`
local consumer = Instance.new("Script", game:GetService("ServerScriptService"))
consumer.Name = "SharedStateConsumer"
consumer.Source = [[
	local module = require(game.ReplicatedStorage.SharedState)
	_G.server_module_runs = module.runs
	_G.server_module_where = module.where
	module.value = "server"
]]
`,
		"part5_server_consumer",
	)

	client_consumer := `
local starter = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local local_script = Instance.new("LocalScript", starter)
local_script.Name = "SharedStateConsumer"
local_script.Source = [[
	local name = game:GetService("Players").LocalPlayer.Name
	_G.runtime_name = name
	local module = require(game.ReplicatedStorage.SharedState)
	_G.module_runs = module.runs
	_G.module_where = module.where
	module.value = name
	if name == "Player1" then
		_G.only_client_a = true
	end
]]
`
	run(&client_a_vm, client_consumer, "part5_client_a_consumer")
	run(&client_b_vm, client_consumer, "part5_client_b_consumer")

	step(&server, &server_vm, 3)
	step(&client_a, &client_a_vm, 3)
	step(&client_b, &client_b_vm, 3)

	verify(
		&server_vm,
		`
expect(_G.server_module_runs == 1, "the server ran the module once")
expect(_G.server_module_where == "server", "the server module saw a server environment")
expect(_G.runtime_name == nil, "client globals do not leak into the server")
`,
		"part5_verify_server",
	)

	verify(
		&client_a_vm,
		`
expect(_G.module_runs == 1, "client A ran the module once, independently of the server")
expect(_G.module_where == "client", "client A's module saw a client environment")
expect(_G.runtime_name == "Player1", "client A globals are its own")
expect(_G.shared_runs == 1, "client A has its own module count")
`,
		"part5_verify_client_a",
	)

	verify(
		&client_b_vm,
		`
expect(_G.module_runs == 1, "client B ran the module once")
expect(_G.module_where == "client", "client B's module saw a client environment")
expect(_G.runtime_name == "Player2", "client B globals are its own")
expect(_G.only_client_a == nil, "client A state never reaches client B")
expect(_G.shared_runs == 1, "client B has its own module count")
`,
		"part5_verify_client_b",
	)

	// The same isolation holds for the module *values*.
	run(
		&server_vm,
		`_G.server_value = require(game.ReplicatedStorage.SharedState).value`,
		"part5_server_value",
	)
	run(
		&client_a_vm,
		`_G.client_value = require(game.ReplicatedStorage.SharedState).value`,
		"part5_client_a_value",
	)
	run(
		&client_b_vm,
		`_G.client_value = require(game.ReplicatedStorage.SharedState).value`,
		"part5_client_b_value",
	)
	verify(&server_vm, `expect(_G.server_value == "server", "server module value")`, "part5_value_server")
	verify(&client_a_vm, `expect(_G.client_value == "Player1", "client A module value")`, "part5_value_a")
	verify(&client_b_vm, `expect(_G.client_value == "Player2", "client B module value")`, "part5_value_b")

	// =====================================================================
	part(18, "server/client access boundaries and require rules")
	// =====================================================================
	verify(
		&server_vm,
		`
expect(game:GetService("Players").LocalPlayer == nil, "LocalPlayer does not exist on the server")
expect(game:GetService("ServerStorage") ~= nil, "the server can reach ServerStorage")
`,
		"part18_verify_server",
	)

	verify(
		&client_a_vm,
		`
expect(game:GetService("Players").LocalPlayer ~= nil, "LocalPlayer exists on the client")
`,
		"part18_verify_client",
	)

	// Required from the wrong runtime, a Script/LocalScript is rejected.
	run(
		&server_vm,
		`
local probe = Instance.new("LocalScript", game:GetService("ReplicatedStorage"))
probe.Name = "ServerForbiddenLocal"
probe.Source = "return {}"
_G.server_require_local_ok, _G.server_require_local_message = pcall(function()
	return require(probe)
end)
_G.server_require_local_message = tostring(_G.server_require_local_message)
`,
		"part18_server_require_local",
	)

	run(
		&client_a_vm,
		`
local probe = Instance.new("Script", workspace)
probe.Name = "ClientForbiddenScript"
probe.Source = "return {}"
_G.client_require_script_ok, _G.client_require_script_message = pcall(function()
	return require(probe)
end)
_G.client_require_script_message = tostring(_G.client_require_script_message)
`,
		"part18_client_require_script",
	)

	// ModuleScripts work in both runtimes, and a Script/LocalScript is requirable
	// in the runtime that owns it.
	run(
		&server_vm,
		`
local requirable = Instance.new("Script", game:GetService("ServerScriptService"))
requirable.Name = "RequirableServerScript"
requirable.Source = "return { kind = 'server script' }"
_G.server_require_script_ok, _G.server_require_script_value = pcall(function()
	return require(requirable)
end)
`,
		"part18_server_require_script",
	)

	run(
		&client_a_vm,
		`
local starter = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local requirable = Instance.new("LocalScript", starter)
requirable.Name = "RequirableClientScript"
requirable.Source = "return { kind = 'client script' }"
_G.client_require_local_ok, _G.client_require_local_value = pcall(function()
	return require(requirable)
end)
`,
		"part18_client_require_local",
	)

	verify(
		&server_vm,
		`
expect(_G.server_require_local_ok == false, "a server runtime cannot require a LocalScript")
expect(string.find(_G.server_require_local_message, "cannot be required from") ~= nil, "the context error explains itself")
expect(_G.server_require_script_ok == true, "a server runtime can require a Script")
expect(_G.server_require_script_value.kind == "server script", "requiring a Script returns its value")
`,
		"part18_verify_require_server",
	)

	verify(
		&client_a_vm,
		`
expect(_G.client_require_script_ok == false, "a client runtime cannot require a Script")
expect(string.find(_G.client_require_script_message, "cannot be required from") ~= nil, "the context error explains itself")
expect(_G.client_require_local_ok == true, "a client runtime can require a LocalScript")
expect(_G.client_require_local_value.kind == "client script", "requiring a LocalScript returns its value")
`,
		"part18_verify_require_client",
	)

	// A LocalScript that is required does not also run as a client script.
	step(&server, &server_vm, 2)

	// =====================================================================
	part(17, "replicated LocalScripts starting on clients")
	// =====================================================================
	run(
		&server_vm,
		`
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39431))

-- Authored in the StarterPlayer template: the client copies it into its own
-- PlayerScripts, so it must run there rather than in place.
local template = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local bootstrap = Instance.new("LocalScript", template)
bootstrap.Name = "NetBootstrap"
bootstrap.Source = [[
	_G.net_bootstrap_ran = true
	_G.net_bootstrap_parent = script.Parent.Name
	_G.net_bootstrap_player = game:GetService("Players").LocalPlayer.Name
]]

local direct = Instance.new("LocalScript", game:GetService("ReplicatedStorage"))
direct.Name = "NetDirect"
direct.Source = [[
	_G.net_direct_ran = true
	_G.net_direct_parent = script.Parent.Name
]]

-- A replicated module both runtimes execute independently.
local module = Instance.new("ModuleScript", game:GetService("ReplicatedStorage"))
module.Name = "NetModule"
module.Source = [[
	local Players = game:GetService("Players")
	_G.net_module_runs = (_G.net_module_runs or 0) + 1
	return {
		runs = _G.net_module_runs,
		where = Players.LocalPlayer and "client" or "server",
	}
]]

local consumer = Instance.new("Script", game:GetService("ServerScriptService"))
consumer.Name = "NetServerConsumer"
consumer.Source = [[
	local value = require(game.ReplicatedStorage.NetModule)
	_G.net_server_module_runs = value.runs
	_G.net_server_module_where = value.where
	value.side = "server"
]]

-- Server-only code and storage must never reach a client.
local secret = Instance.new("Script", game:GetService("ServerScriptService"))
secret.Name = "NetSecretScript"
secret.Source = "_G.net_secret_ran = true"
local secret_part = Instance.new("Part", game:GetService("ServerStorage"))
secret_part.Name = "NetSecretPart"
`,
		"part17_server_setup",
	)

	run(
		&client_a_vm,
		`assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39431))`,
		"part17_client_connect",
	)

	for _ in 0..<150 {
		engine_runtime.Environment_Update_Step(&server, &server_vm, STEP_DT)
		engine_runtime.Environment_Update_Step(&client_a, &client_a_vm, STEP_DT)
		engine_runtime.Environment_Render_Step(&server, &server_vm, STEP_DT)
		engine_runtime.Environment_Render_Step(&client_a, &client_a_vm, STEP_DT)
	}

	verify(
		&server_vm,
		`
expect(_G.net_server_module_runs == 1, "the server ran the replicated module once")
expect(_G.net_server_module_where == "server", "the server module ran in a server environment")
expect(game:GetService("ServerStorage"):FindFirstChild("NetSecretPart") ~= nil, "the server keeps ServerStorage")
`,
		"part17_verify_server",
	)

	verify(
		&client_a_vm,
		`
local Players = game:GetService("Players")

-- The replicated StarterPlayerScripts LocalScript was copied and ran.
expect(_G.net_bootstrap_ran == true, "a replicated LocalScript in StarterPlayerScripts runs on the client")
expect(_G.net_bootstrap_parent == "PlayerScripts", "the starter copy runs from PlayerScripts")
expect(_G.net_bootstrap_player == "Player1", "the copy sees the local player")
expect(Players.LocalPlayer.PlayerScripts:FindFirstChild("NetBootstrap") ~= nil, "the copy exists in PlayerScripts")

-- A LocalScript replicated straight into ReplicatedStorage also runs.
expect(_G.net_direct_ran == true, "a replicated LocalScript runs on the client")
expect(_G.net_direct_parent == "ReplicatedStorage", "it runs where it was replicated to")

-- Server-only code never executes on the client.
expect(_G.net_secret_ran == nil, "a replicated Script must not run on the client")
expect(game:GetService("ServerScriptService"):FindFirstChild("NetSecretScript") == nil, "ServerScriptService does not replicate")
expect(game:GetService("ServerStorage"):FindFirstChild("NetSecretPart") == nil, "ServerStorage does not replicate")

-- The replicated module has its own client-side cache and execution.
local module = require(game.ReplicatedStorage.NetModule)
expect(_G.net_module_runs == 1, "the client ran the replicated module itself")
expect(module.where == "client", "the module saw a client environment")
expect(module.side == nil, "the server's module table is not shared with the client")
expect(require(game.ReplicatedStorage.NetModule) == module, "the client caches its own module value")
`,
		"part17_verify_client",
	)

	// =====================================================================
	part(18, "shutdown leaves nothing running")
	// =====================================================================
	run(
		&server_vm,
		`
local waiter = Instance.new("Script", game:GetService("ServerScriptService"))
waiter.Name = "ShutdownWaiter"
waiter.Source = [[
	_G.shutdown_waiter_started = true
	task.wait(5)
	_G.shutdown_waiter_resumed = true
]]
`,
		"part18_shutdown_setup",
	)
	step(&server, &server_vm, 3)
	verify(
		&server_vm,
		`expect(_G.shutdown_waiter_started == true, "the shutdown waiter started")`,
		"part18_shutdown_verify",
	)

	script_context := cast(^services.ScriptContext)service(&server, "ScriptContext")
	live_threads := len(script_context.threads)
	check(live_threads > 0, "a suspended script is tracked while its context lives")

	services.ScriptContext_Stop_All(script_context)
	if len(script_context.threads) != 0 {
		fail("Stop_All must release every script thread")
	}
	tasks := scheduled_task_count(&server)
	if tasks != 0 {
		fmt.eprintf("scheduled tasks left after shutdown: %d\n", tasks)
		fail("stopping every script must cancel its scheduled resumes")
	}
	verify(
		&server_vm,
		`expect(_G.shutdown_waiter_resumed == nil, "a stopped script never resumes")`,
		"part18_shutdown_verify_b",
	)

	fmt.printf("total failures: %d\n", failures)
	if failures > 0 {
		panic("SCRIPT_SEMANTICS_SMOKE_FAILED")
	}
	fmt.println("SCRIPT_SEMANTICS_SMOKE_PASSED")
}
