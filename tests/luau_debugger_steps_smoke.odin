package main

import vm "../src/engine/vm"
import "core:fmt"

source := `local function inner(v)
    local first = v + 1
    local second = first + 2
    return second
end
local function outer()
    local start = 3
    local result = inner(start)
    local after = result + 1
    return after
end
value = outer()`

run_case :: proc(mode: vm.Debug_Step_Mode, breakpoint_line: i32) {
	state := vm.New()
	defer vm.Close(&state)
	vm.SetOptimizationLevel(&state, 0)
	vm.SetDebugLevel(&state, 2)
	assert(vm.Debugger_Enable(state.L, true))
	assert(vm.Debugger_SetBreakpoint(state.L, "=StepCase", breakpoint_line, true))

	co := vm.NewThread(state.L)
	ref := vm.RetainValue(state.L)
	vm.Pop(state.L)
	defer vm.ReleaseValue(state.L, ref)
	ok, compile_error := vm.LoadSource(&state, co, source, "=StepCase")
	if !ok {
		fmt.eprintln(compile_error)
		delete(compile_error)
		panic("cannot compile step case")
	}
	finished, yielded, message, trace := vm.ResumeThreadTraceback(co, state.L)
	defer delete(message)
	defer delete(trace)
	assert(!finished && yielded && vm.Debugger_IsPaused(co))
	before := vm.Debugger_GetFrames(co)
	assert(len(before) >= 2)
	depth := len(before)
	vm.Debugger_FreeFrames(before)

	assert(vm.Debugger_Resume(co, mode))
	step_finished, step_yielded, step_error, step_trace := vm.ResumeThreadTraceback(co, state.L)
	defer delete(step_error)
	defer delete(step_trace)
	assert(!step_finished && step_yielded && step_error == "" && vm.Debugger_IsPaused(co))
	after := vm.Debugger_GetFrames(co)
	assert(len(after) > 0)
	if mode == .Over {
		assert(len(after) <= depth)
	} else if mode == .Out {
		assert(len(after) < depth)
	}
	fmt.println(
		"Step mode ",
		mode,
		" at ",
		after[0].source,
		":",
		after[0].line,
		" stack depth ",
		len(after),
	)
	vm.Debugger_FreeFrames(after)
	assert(vm.Debugger_Resume(co, .None))
	last_finished, _, last_error, last_trace := vm.ResumeThreadTraceback(co, state.L)
	defer delete(last_error)
	defer delete(last_trace)
	assert(last_finished && last_error == "")
	assert(!vm.Debugger_IsPaused(co))
}

main :: proc() {
	run_case(.Over, 8)
	run_case(.Out, 3)
	fmt.println("LUAU_DEBUGGER_STEPS_SMOKE_PASSED")
}
