package main

import vm "../src/engine/vm"
import "core:fmt"

expect :: proc(value: bool, message: string) {
	if !value {panic(message)}
}

main :: proc() {
	script_vm := vm.New()
	defer vm.Close(&script_vm)
	L := script_vm.L
	script_vm.compile_options.debug_level = 2
	script_vm.compile_options.optimization_level = 0
	expect(vm.Debugger_Enable(L, true), "debugger callbacks were not installed")
	expect(vm.Debugger_SetBreakpoint(L, "=debugtest", 3, true), "failed to register breakpoint")
	thread := vm.NewThread(L)
	thread_ref := vm.RetainValue(L)
	vm.Pop(L)
	defer vm.ReleaseValue(L, thread_ref)
	source := `local function work()
    local x = 5
    x += 2
    x += 3
    return x
end
result = work()`
	ok, err := vm.LoadSource(&script_vm, thread, source, "=debugtest")
	if !ok {fmt.println(err); delete(err)}
	expect(ok, "could not load debugger smoke source")
	finished, yielded, resume_error, traceback := vm.ResumeThreadTraceback(thread, L, 0)
	defer delete(resume_error)
	defer delete(traceback)
	expect(!finished && yielded, "breakpoint must suspend before script finishes")
	expect(vm.Debugger_IsPaused(thread), "expected paused script thread")
	frames := vm.Debugger_GetFrames(thread)
	expect(len(frames) > 0, "expected debugger stack frames")
	fmt.println("paused at:", frames[0].source, frames[0].line)
	expect(frames[0].line == 3, "paused frame must report the requested breakpoint line")
	vm.Debugger_FreeFrames(frames)
	locals := vm.Debugger_GetLocals(thread, 0)
	fmt.println("local count:", len(locals))

	vm.Debugger_FreeVariables(locals)
	expect(vm.Debugger_Resume(thread, .Into), "step into should resume paused script")
	finished2, yielded2, error2, traceback2 := vm.ResumeThreadTraceback(thread, L, 0)
	defer delete(error2)
	defer delete(traceback2)
	expect(!finished2 && yielded2 && error2 == "", "step must yield at next source line")
	expect(vm.Debugger_IsPaused(thread), "step should pause again")
	expect(vm.Debugger_Resume(thread, .None), "continue should resume after stepping")
	for i in 0 ..< 12 {
		if finished2 {break}
		finished2, yielded2, _, _ = vm.ResumeThreadTraceback(thread, L, 0)
		if vm.Debugger_IsPaused(thread) {
			expect(vm.Debugger_Resume(thread, .None), "cannot resume repeated breakpoint")
		}
	}
	expect(finished2, "script never completed")
	expect(!vm.Debugger_IsPaused(thread), "finished script must not stay paused")
	_ = yielded2
	fmt.println("LUAU_DEBUGGER_SMOKE_PASSED")
}
