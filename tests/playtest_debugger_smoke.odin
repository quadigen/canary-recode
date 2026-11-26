package main

import "core:fmt"
import "core:os"
import "core:strings"

import environment "../src/engine/runtime"
import services "../src/engine/services"
import target "../src/engine/target"
import vm "../src/engine/vm"

must :: proc(vm_state: ^vm.VM, source, name: string) {
	ok, err := vm.RunInternal(vm_state, source, name)
	if !ok {
		fmt.eprintf("%s: %s\n", name, err)
		delete(err)
		panic("remote debugger test failed")
	}
}

main :: proc() {
	target.set_mode(.Editor)
	target.set_playtest(false)
	editor := vm.New()
	editor_env: environment.Environment
	environment.Environment_Init(&editor_env, &editor)
	defer {
		environment.Environment_Destroy(&editor_env)
		vm.Close(&editor)
	}
	editor_sc := services.ScriptContext_From_Registry(&editor_env.services)
	assert(editor_sc != nil)
	must(
		&editor,
		`
local sc = game:GetService("ScriptContext")
assert(sc:DebugEnable(true))
assert(sc:DebugSetBreakpoint("=RemoteCase", 3, true))
`,
		"debugger_bootstrap_parent",
	)
	config_path := os.get_env(services.PLAYTEST_DEBUG_ENV, context.temp_allocator)
	assert(config_path != "" && os.exists(config_path))

	dir, err := os.make_directory_temp("", "kinemium-remote-debug-smoke-*", context.allocator)
	assert(err == nil)
	defer {
		_ = os.remove_all(dir)
		delete(dir)
	}
	server_dir, path_error := os.join_path({dir, "Server"}, context.allocator)
	assert(path_error == nil)
	defer delete(server_dir)
	assert(os.make_directory(server_dir) == nil)

	editor_service := cast(^services.PlaytestService)services.Ensure_Service(
		&editor_env.services,
		"PlaytestService",
	)
	assert(editor_service != nil)
	editor_service.running = true
	editor_service.tree_dir = strings.clone(dir)
	editor_service.server_process.pid = 0x7FFFFFFF
	defer {
		editor_service.running = false
		editor_service.server_process.pid = 0
		delete(editor_service.tree_dir)
		editor_service.tree_dir = ""
	}

	target.set_mode(.Server)
	target.set_playtest(true)
	child := vm.New()
	child_env: environment.Environment
	environment.Environment_Init(&child_env, &child)
	defer {
		environment.Environment_Destroy(&child_env)
		vm.Close(&child)
	}
	assert(services.Playtest_Debugger_Bootstrap(&child, server_dir))
	assert(vm.Debugger_Enabled(child.L))

	thread := vm.NewThread(child.L)
	thread_ref := vm.RetainValue(child.L)
	vm.Pop(child.L)
	defer vm.ReleaseValue(child.L, thread_ref)
	source := `local function test()
    local n = 4
    n += 1
    return n
end
answer = test()`
	ok, load_error := vm.LoadSource(&child, thread, source, "=RemoteCase")
	if !ok {fmt.eprintln(load_error); delete(load_error)}
	assert(ok)
	finished, yielded, runtime_error, trace := vm.ResumeThreadTraceback(thread, child.L)
	defer delete(runtime_error)
	defer delete(trace)
	assert(!finished && yielded && vm.Debugger_IsPaused(thread))

	target.set_mode(.Editor)
	target.set_playtest(false)
	must(
		&editor,
		`
local sc = game:GetService("ScriptContext")
assert(sc:DebugRemoteSend("Server", "snapshot"))
`,
		"remote_request",
	)
	target.set_mode(.Server)
	target.set_playtest(true)
	services.Playtest_Debugger_Pump(server_dir, &child_env.services, child.L)
	target.set_mode(.Editor)
	target.set_playtest(false)
	must(
		&editor,
		`
local sc = game:GetService("ScriptContext")
local state = sc:DebugRemotePoll("Server")
assert(state and state.enabled)
assert(#state.pausedThreads == 1, "Remote paused thread missing")
assert(state.pausedThreads[1].source == "=RemoteCase")
assert(state.pausedThreads[1].line == 3)
assert(#state.frames > 0 and state.frames[1].line == 3)
assert(#state.breakpoints == 1)
assert(sc:DebugRemoteSend("Server", "resume", state.pausedThreads[1].id, 0, "continue"))
`,
		"remote_snapshot",
	)
	target.set_mode(.Server)
	target.set_playtest(true)
	services.Playtest_Debugger_Pump(server_dir, &child_env.services, child.L)
	target.set_mode(.Editor)
	target.set_playtest(false)
	must(
		&editor,
		`
local sc = game:GetService("ScriptContext")
local state = sc:DebugRemotePoll("Server")
assert(state and state.enabled)
assert(#state.pausedThreads == 0)
assert(sc:DebugSetBreakpoint("=DynamicAfterStart", 2, true))
assert(sc:DebugRemoteSend("Server", "sync"))
`,
		"remote_resume",
	)
	target.set_mode(.Server)
	target.set_playtest(true)
	services.Playtest_Debugger_Pump(server_dir, &child_env.services, child.L)
	target.set_mode(.Editor)
	target.set_playtest(false)
	must(
		&editor,
		`
local sc = game:GetService("ScriptContext")
local state = sc:DebugRemotePoll("Server")
assert(state and state.enabled)
local found = false
for _, breakpoint in ipairs(state.breakpoints) do
    if breakpoint.source == "=DynamicAfterStart" and breakpoint.line == 2 then
        found = true
    end
end
assert(found, "Hot-sync breakpoint was not applied to child")
assert(sc:DebugEnable(false))
`,
		"remote_hot_sync",
	)
	assert(!vm.Debugger_IsPaused(thread))
	fmt.println("PLAYTEST_DEBUGGER_BRIDGE_SMOKE_PASSED")
}
