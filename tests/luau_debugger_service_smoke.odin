package main

import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

must :: proc(vm_state: ^vm.VM, code, name: string) {
	ok, err := vm.RunInternal(vm_state, code, name)
	if !ok {
		fmt.eprintf("%s: %s\n", name, err)
		delete(err)
		panic("script debugger service smoke failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)
	defer {
		engine_runtime.Environment_Destroy(&environment)
		vm.Close(&script_vm)
	}

	must(
		&script_vm,
		`
local sc = game:GetService("ScriptContext")
assert(sc and not sc.DebuggerEnabled)
assert(sc:DebugEnable(true) and sc.DebuggerEnabled)
assert(sc:DebugSetBreakpoint("=ServiceTest", 3, true))
local points = sc:DebugGetBreakpoints()
assert(#points == 1 and points[1].source == "=ServiceTest")
assert(not pcall(function() sc:DebugSetBreakpoint("=ServiceTest", -4) end))
`,
		"enable_debugger",
	)

	thread := vm.NewThread(script_vm.L)
	thread_ref := vm.RetainValue(script_vm.L)
	vm.Pop(script_vm.L)
	defer vm.ReleaseValue(script_vm.L, thread_ref)
	source := `local function sample()
    local x = 15
    x += 20
    return x
end
answer = sample()`
	ok, err := vm.LoadSource(&script_vm, thread, source, "=ServiceTest")
	if !ok {fmt.eprintln(err); delete(err); panic("load failed")}
	finished, yielded, message, traceback := vm.ResumeThreadTraceback(thread, script_vm.L, 0)
	defer delete(message)
	defer delete(traceback)
	assert(!finished && yielded && vm.Debugger_IsPaused(thread))

	must(
		&script_vm,
		`
local sc = game:GetService("ScriptContext")
local paused = sc:DebugGetPausedThreads()
assert(#paused == 1)
assert(paused[1].id > 0 and paused[1].source == "=ServiceTest")
local stack = sc:DebugGetFrames(paused[1].id)
assert(#stack > 0 and stack[1].source == "=ServiceTest")
local locals = sc:DebugGetLocals(paused[1].id, 0)
assert(type(locals) == "table")
assert(sc:DebugResume(paused[1].id, "into"))
`,
		"inspect_and_step",
	)

	must(
		&script_vm,
		`
local sc = game:GetService("ScriptContext")
local attempts = 0
while #sc:DebugGetPausedThreads() > 0 do
    attempts += 1
    assert(attempts < 16, "debugger cannot continue")
    assert(sc:DebugResume(sc:DebugGetPausedThreads()[1].id, "continue"))
end
assert(sc:DebugSetBreakpoint("=ServiceTest", 3, false))
assert(#sc:DebugGetBreakpoints() == 0)
assert(sc:DebugEnable(false))
assert(not sc.DebuggerEnabled)
`,
		"resume_and_disable",
	)
	must(
		&script_vm,
		`
local sc = game:GetService("ScriptContext")
assert(sc:DebugEnable(true))
assert(sc:DebugSetBreakpoint("=TrackedSource", 2, true))
`,
		"source_reference_prepare",
	)
	ctx := services.ScriptContext_From_Registry(&environment.services)
	assert(ctx != nil)
	completed := services.ScriptContext_Run_Source(
		ctx,
		"local value = 20\nvalue += 22\nworkspace:SetAttribute('DebugSourceAnswer', value)",
		"=TrackedSource",
	)
	assert(!completed && len(ctx.debug_source_threads) == 1)
	must(
		&script_vm,
		`
local sc = game:GetService("ScriptContext")
local paused = sc:DebugGetPausedThreads()
assert(#paused == 1)
assert(sc:DebugResume(paused[1].id, "continue"))
assert(workspace:GetAttribute("DebugSourceAnswer") == 42)
assert(#sc:DebugGetPausedThreads() == 0)
assert(sc:DebugEnable(false))
`,
		"source_reference_complete",
	)
	assert(len(ctx.debug_source_threads) == 0)
	fmt.println("LUAU_DEBUGGER_SERVICE_SMOKE_PASSED")
}
