package services

import classes "../classes"
import datatypes "../datatypes"
import vm "../vm"
import "core:strings"


script_debugger_authorized :: proc(L: ^vm.State) -> bool {
	return vm.ThreadHasSecurityCapability(L, datatypes.SECURITY_CAPABILITY_INTERNAL_STUDIO_ACCESS)
}

script_debugger_source :: proc(L: ^vm.State, index: int) -> string {
	if vm.IsString(L, index) {return vm.ArgString(L, index)}
	object := classes.Object_From_Argument(L, index)
	if object == nil ||
	   object.destroyed ||
	   (!classes.Is_A(object, "Script") &&
			   !classes.Is_A(object, "LocalScript") &&
			   !classes.Is_A(object, "ModuleScript")) {return ""}
	return classes.Get_Full_Name(object)
}

script_debugger_push_frames :: proc(L: ^vm.State, thread: ^vm.State) -> i32 {
	frames := vm.Debugger_GetFrames(thread)
	defer vm.Debugger_FreeFrames(frames)
	vm.NewTable(L, len(frames))
	for frame, i in frames {
		vm.NewTable(L, 0, 4)
		vm.PushString(L, frame.source)
		vm.SetField(L, -2, "source")
		vm.PushString(L, frame.name)
		vm.SetField(L, -2, "name")
		vm.PushNumber(L, f64(frame.line))
		vm.SetField(L, -2, "line")
		vm.PushNumber(L, f64(frame.depth))
		vm.SetField(L, -2, "depth")
		vm.SetArrayValue(L, -2, i + 1)
	}
	return 1
}

script_debugger_push_locals :: proc(L: ^vm.State, thread: ^vm.State, depth: i32) -> i32 {
	variables := vm.Debugger_GetLocals(thread, depth)
	defer vm.Debugger_FreeVariables(variables)
	vm.NewTable(L, len(variables))
	for variable, i in variables {
		vm.NewTable(L, 0, 3)
		vm.PushString(L, variable.name)
		vm.SetField(L, -2, "name")
		vm.PushString(L, variable.value)
		vm.SetField(L, -2, "value")
		vm.PushString(L, variable.type_name)
		vm.SetField(L, -2, "type")
		vm.SetArrayValue(L, -2, i + 1)
	}
	return 1
}

script_debugger_push_paused :: proc(L: ^vm.State, sc: ^ScriptContext) -> i32 {
	threads := vm.Debugger_PausedThreads(sc.vm_state.L)
	defer delete(threads)
	vm.NewTable(L, len(threads))
	for thread, i in threads {
		info, ok := vm.Debugger_ThreadInfo(thread)
		if !ok {continue}
		vm.NewTable(L, 0, 5)
		vm.PushNumber(L, f64(info.id))
		vm.SetField(L, -2, "id")
		vm.PushNumber(L, f64(info.line))
		vm.SetField(L, -2, "line")
		vm.PushString(L, info.source)
		vm.SetField(L, -2, "source")
		vm.PushString(L, info.reason)
		vm.SetField(L, -2, "reason")
		vm.PushString(L, ScriptContext_Describe_Thread(sc, thread))
		vm.SetField(L, -2, "script")
		vm.SetArrayValue(L, -2, i + 1)
	}
	return 1
}

script_debugger_push_breakpoints :: proc(L: ^vm.State, sc: ^ScriptContext) -> i32 {
	points := vm.Debugger_GetBreakpoints(sc.vm_state.L)
	defer vm.Debugger_FreeBreakpoints(points)
	vm.NewTable(L, len(points))
	for bp, i in points {
		vm.NewTable(L, 0, 3)
		vm.PushString(L, bp.source)
		vm.SetField(L, -2, "source")
		vm.PushNumber(L, f64(bp.line))
		vm.SetField(L, -2, "line")
		vm.PushNumber(L, f64(bp.resolved_line))
		vm.SetField(L, -2, "resolvedLine")
		vm.SetArrayValue(L, -2, i + 1)
	}
	return 1
}

script_debugger_resume_native :: proc(sc: ^ScriptContext, id: u32, mode_name: string) -> bool {
	if sc == nil || sc.vm_state == nil || id == 0 {return false}
	thread := vm.Debugger_ThreadByID(sc.vm_state.L, u64(id))
	if thread == nil || !vm.Debugger_IsPaused(thread) {return false}
	mode: vm.Debug_Step_Mode
	switch mode_name {
	case "continue":
		mode = .None
	case "into":
		mode = .Into
	case "over":
		mode = .Over
	case "out":
		mode = .Out
	case:
		return false
	}
	if !vm.Debugger_Resume(thread, mode) {return false}
	if scheduler := script_context_task_scheduler(sc);
	   scheduler != nil && TaskScheduler_Owns_Thread(scheduler, thread) {
		return true
	}

	finished, _, message, traceback := vm.ResumeThreadTraceback(thread, sc.vm_state.L, 0)
	if finished || message != "" {
		for index := len(sc.debug_source_threads) - 1; index >= 0; index -= 1 {
			held := sc.debug_source_threads[index]
			if held.thread != thread {continue}
			vm.ReleaseValue(sc.vm_state.L, held.reference)
			ordered_remove(&sc.debug_source_threads, index)
		}
	}
	if message != "" {
		for entry in sc.threads {
			if entry.thread != thread || entry.object == nil || entry.object.destroyed {continue}
			script_context_report_error(sc, entry.object, message, traceback)
			if common := classes.Script_Common_Of(entry.object); common != nil {
				classes.Require_Frame_Pop(sc.object_registry, thread)
				script_context_fail_script(sc, entry.object, common)
			}
			break
		}
	}
	delete(message)
	delete(traceback)
	if finished {
		for entry in sc.threads {
			if entry.thread != thread || entry.object == nil || entry.object.destroyed {continue}
			if common := classes.Script_Common_Of(entry.object); common != nil {
				classes.Require_Frame_Pop(sc.object_registry, thread)
				script_context_finish_script(sc, entry.object, common)
			}
			break
		}
	}
	return true
}

script_debugger_resume :: proc(L: ^vm.State, sc: ^ScriptContext) -> i32 {
	id := vm.ArgNumber(L, 2)
	if id <= 0 || id > 4_294_967_295 || f64(u32(id)) != id {
		return vm.RaiseError(L, "thread ID must be a positive integer")
	}
	mode_name := vm.ArgOptionalString(L, 3, "continue")
	if mode_name != "continue" &&
	   mode_name != "into" &&
	   mode_name != "over" &&
	   mode_name != "out" {
		return vm.RaiseError(L, "mode must be continue, into, over, or out")
	}
	vm.PushBoolean(L, script_debugger_resume_native(sc, u32(id), mode_name))
	return 1
}

script_debugger_namecall :: proc(L: ^vm.State, sc: ^ScriptContext, method: string) -> (i32, bool) {
	switch method {
	case "DebugEnable",
	     "DebugSetBreakpoint",
	     "DebugGetBreakpoints",
	     "DebugGetPausedThreads",
	     "DebugGetFrames",
	     "DebugGetLocals",
	     "DebugResume",
	     "DebugPause":
	case:
		return 0, false
	}
	if !script_debugger_authorized(L) {
		return vm.RaiseError(L, "debugger controls require Studio privileges"), true
	}
	if sc == nil || sc.vm_state == nil || sc.vm_state.L == nil {
		return vm.RaiseError(L, "ScriptContext VM is unavailable"), true
	}
	root := sc.vm_state.L
	switch method {
	case "DebugEnable":
		enabled := vm.ArgBoolean(L, 2)
		if enabled && !sc.debugger_options_saved {
			sc.debugger_saved_options = sc.vm_state.compile_options
			sc.debugger_options_saved = true
		}
		if enabled {
			vm.SetOptimizationLevel(sc.vm_state, 0)
			vm.SetDebugLevel(sc.vm_state, 2)
		} else if sc.debugger_options_saved {
			vm.SetCompileOptions(sc.vm_state, sc.debugger_saved_options)
			sc.debugger_options_saved = false
		}
		result := vm.Debugger_Enable(root, enabled)
		when ODIN_OS != .JS {
			if result && enabled {
				_ = Playtest_Debugger_Update_Boot(sc)
			} else if !enabled {
				Playtest_Debugger_Clear_Boot(sc)
			}
		}
		vm.PushBoolean(L, result)
		return 1, true
	case "DebugSetBreakpoint":
		source := script_debugger_source(L, 2)
		if source ==
		   "" {return vm.RaiseError(L, "expected a Script instance or source name"), true}
		line := vm.ArgNumber(L, 3)
		if line < 1 || line > 1_000_000 || f64(i64(line)) != line {
			return vm.RaiseError(L, "breakpoint line must be between 1 and 1000000"), true
		}
		enabled := vm.ArgOptionalBoolean(L, 4, true)
		result := vm.Debugger_SetBreakpoint(root, source, i32(line), enabled)
		when ODIN_OS != .JS {
			if result {_ = Playtest_Debugger_Update_Boot(sc)}
		}
		vm.PushBoolean(L, result)
		return 1, true
	case "DebugGetBreakpoints":
		return script_debugger_push_breakpoints(L, sc), true
	case "DebugGetPausedThreads":
		return script_debugger_push_paused(L, sc), true
	case "DebugGetFrames":
		id := vm.ArgNumber(L, 2)
		thread := id > 0 ? vm.Debugger_ThreadByID(root, u64(id)) : nil
		if thread == nil || !vm.Debugger_IsPaused(thread) {vm.NewTable(L); return 1, true}
		return script_debugger_push_frames(L, thread), true
	case "DebugGetLocals":
		id := vm.ArgNumber(L, 2)
		depth := vm.ArgOptionalNumber(L, 3, 0)
		thread := id > 0 ? vm.Debugger_ThreadByID(root, u64(id)) : nil
		if depth < 0 ||
		   depth > 63 ||
		   f64(i64(depth)) !=
			   depth {return vm.RaiseError(L, "frame depth must be between 0 and 63"), true}
		if thread == nil || !vm.Debugger_IsPaused(thread) {vm.NewTable(L); return 1, true}
		return script_debugger_push_locals(L, thread, i32(depth)), true
	case "DebugResume":
		return script_debugger_resume(L, sc), true
	case "DebugPause":
		if ScriptContext_Mode(sc) == .Editor {vm.PushNumber(L, 0); return 1, true}
		if !vm.Debugger_Enabled(root) {vm.PushNumber(L, 0); return 1, true}
		count := 0
		for entry in sc.threads {
			if entry.thread == nil {continue}
			if vm.Debugger_RequestPause(entry.thread) {count += 1}
		}
		vm.PushNumber(L, f64(count))
		return 1, true
	}
	return 0, false
}
