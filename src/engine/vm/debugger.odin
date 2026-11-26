package luau

import tracy "../util/odin-tracy"
import "core:fmt"
import "core:strings"
import luauh "luauh"


Debug_Step_Mode :: enum {
	None,
	Into,
	Over,
	Out,
}

Debug_Breakpoint :: struct {
	source:        string,
	line:          i32,
	resolved_line: i32,
}

Debug_Thread :: struct {
	id:              u64,
	thread:          ^State,
	paused:          bool,
	reason:          string,
	source:          string,
	line:            i32,
	step_mode:       Debug_Step_Mode,
	step_line:       i32,
	step_depth:      i32,
	skip_break_once: bool,
}

Debug_Closure :: struct {
	thread:    ^State,
	source:    string,
	reference: i32,
}


Debugger :: struct {
	enabled:     bool,
	root:        ^State,
	next_id:     u64,
	closures:    [dynamic]Debug_Closure,
	breakpoints: [dynamic]Debug_Breakpoint,
	threads:     [dynamic]Debug_Thread,
}

debugger_for :: proc(L: ^State) -> ^Debugger {
	if L == nil {return nil}
	callbacks := luauh.lua_callbacks(L)
	if callbacks == nil || callbacks.debugbreak != debugger_break_hook {return nil}
	return cast(^Debugger)callbacks.userdata
}

debugger_thread :: proc(debugger: ^Debugger, L: ^State, create := false) -> ^Debug_Thread {
	if debugger == nil || L == nil {return nil}
	for &item in debugger.threads {
		if item.thread == L {return &item}
	}
	if !create {return nil}
	debugger.next_id += 1
	append(&debugger.threads, Debug_Thread{id = debugger.next_id, thread = L})
	return &debugger.threads[len(debugger.threads) - 1]
}

debugger_frame :: proc(L: ^State, level: i32 = 0) -> (luauh.lua_Debug, bool) {
	info: luauh.lua_Debug
	if luauh.lua_getinfo(L, level, "nsl", &info) == 0 {return info, false}
	return info, true
}

debugger_capture :: proc(item: ^Debug_Thread, L: ^State, reason: string, info: luauh.lua_Debug) {
	delete(item.source)
	item.source = info.source != nil ? strings.clone(string(info.source)) : ""
	item.line = info.currentline
	item.paused = true
	item.reason = reason
	item.step_mode = .None
	luauh.lua_singlestep(L, 0)
}

debugger_break_hook :: proc "c" (L: ^State, ar: ^luauh.lua_Debug) {
	context = tracy.DefaultContext()
	debugger := debugger_for(L)
	if debugger == nil || !debugger.enabled {return}
	item := debugger_thread(debugger, L, true)
	if item.skip_break_once {
		item.skip_break_once = false
		return
	}
	if item.paused {return}
	info, ok := debugger_frame(L)
	if !ok && ar != nil {info = ar^}
	if ar != nil && ar.currentline > 0 {info.currentline = ar.currentline}
	debugger_capture(item, L, "breakpoint", info)
	_ = luauh.lua_break_direct(L)
}

debugger_step_hook :: proc "c" (L: ^State, ar: ^luauh.lua_Debug) {
	context = tracy.DefaultContext()
	debugger := debugger_for(L)
	if debugger == nil || !debugger.enabled {return}
	item := debugger_thread(debugger, L)
	if item == nil || item.paused || item.step_mode == .None {return}
	info, ok := debugger_frame(L)
	if !ok && ar != nil {info = ar^}
	if ar != nil && ar.currentline > 0 {info.currentline = ar.currentline}
	depth := luauh.lua_stackdepth(L)
	line := info.currentline
	should_pause := false
	#partial switch item.step_mode {
	case .Into:
		should_pause = line > 0 && (line != item.step_line || depth != item.step_depth)
	case .Over:
		should_pause =
			line > 0 &&
			depth <= item.step_depth &&
			(line != item.step_line || depth < item.step_depth)
	case .Out:
		should_pause = depth < item.step_depth
	}
	if !should_pause {return}
	debugger_capture(item, L, "step", info)
	_ = luauh.lua_break_direct(L)
}

Debugger_Init :: proc(L: ^State) {
	if L == nil || debugger_for(L) != nil {return}
	callbacks := luauh.lua_callbacks(L)

	if callbacks == nil ||
	   callbacks.debugbreak != nil ||
	   callbacks.debugstep != nil ||
	   callbacks.userdata != nil {return}
	dbg := new(Debugger)
	dbg.root = L
	callbacks.userdata = dbg
	callbacks.debugbreak = debugger_break_hook
	callbacks.debugstep = debugger_step_hook
}

Debugger_Shutdown :: proc(L: ^State) {
	dbg := debugger_for(L)
	if dbg == nil {return}
	callbacks := luauh.lua_callbacks(L)
	callbacks.debugbreak = nil
	callbacks.debugstep = nil
	callbacks.userdata = nil
	for bp in dbg.breakpoints {delete(bp.source)}
	delete(dbg.breakpoints)
	for closure in dbg.closures {
		ReleaseValue(dbg.root, closure.reference)
		delete(closure.source)
	}
	delete(dbg.closures)
	for &item in dbg.threads {
		if item.thread != nil {luauh.lua_singlestep(item.thread, 0)}
		delete(item.source)
	}
	delete(dbg.threads)
	free(dbg)
}

Debugger_Enable :: proc(L: ^State, enabled: bool) -> bool {
	dbg := debugger_for(L)
	if dbg == nil {return false}
	dbg.enabled = enabled
	if !enabled {
		for &item in dbg.threads {
			item.paused = false
			item.step_mode = .None
			item.skip_break_once = false


			if item.thread != nil {luauh.lua_singlestep(item.thread, 0)}
		}
	}
	return true
}

Debugger_Enabled :: proc(L: ^State) -> bool {
	dbg := debugger_for(L)
	return dbg != nil && dbg.enabled
}


Debugger_SetBreakpoint :: proc(L: ^State, source: string, line: i32, enabled: bool) -> bool {
	dbg := debugger_for(L)
	if dbg == nil || source == "" || line < 1 || line > 1_000_000 {return false}
	for bp, index in dbg.breakpoints {
		if bp.source != source || bp.line != line {continue}
		if !enabled {
			for closure in dbg.closures {
				if closure.source != source {continue}
				PushRegistryReference(dbg.root, closure.reference)
				_ = luauh.lua_breakpoint(dbg.root, -1, line, 0)
				Pop(dbg.root)
			}
			delete(bp.source)
			ordered_remove(&dbg.breakpoints, index)
		}
		return true
	}
	if !enabled || len(dbg.breakpoints) >= 4096 {return false}
	append(&dbg.breakpoints, Debug_Breakpoint{source = strings.clone(source), line = line})
	for closure in dbg.closures {
		if closure.source != source {continue}
		PushRegistryReference(dbg.root, closure.reference)
		resolved := luauh.lua_breakpoint(dbg.root, -1, line, 1)
		Pop(dbg.root)
		dbg.breakpoints[len(dbg.breakpoints) - 1].resolved_line = resolved
	}
	return true
}

Debugger_ApplyBreakpoints :: proc(L: ^State, source: string) {
	dbg := debugger_for(L)
	if dbg == nil || !dbg.enabled || !IsFunction(L, -1) {return}
	if len(dbg.closures) < 4096 {
		CopyValueToThread(L, dbg.root, -1)
		reference := RetainValue(dbg.root)
		Pop(dbg.root)
		append(
			&dbg.closures,
			Debug_Closure{thread = L, source = strings.clone(source), reference = reference},
		)
	}
	_ = debugger_thread(dbg, L, true)
	for &bp in dbg.breakpoints {
		if bp.source != source {continue}
		bp.resolved_line = luauh.lua_breakpoint(L, -1, bp.line, 1)
	}
}

Debugger_RegisterThread :: proc(L: ^State) {
	dbg := debugger_for(L)
	if dbg == nil || !dbg.enabled {return}
	_ = debugger_thread(dbg, L, true)
}

Debug_Thread_Summary :: struct {
	id:     u64,
	line:   i32,
	source: string,
	reason: string,
}

Debugger_ThreadInfo :: proc(L: ^State) -> (Debug_Thread_Summary, bool) {
	dbg := debugger_for(L)
	item := debugger_thread(dbg, L)
	if item == nil {return Debug_Thread_Summary{}, false}
	return Debug_Thread_Summary {
			id = item.id,
			line = item.line,
			source = item.source,
			reason = item.reason,
		},
		true
}

Debugger_ThreadByID :: proc(L: ^State, id: u64) -> ^State {
	dbg := debugger_for(L)
	if dbg == nil || id == 0 {return nil}
	for item in dbg.threads {
		if item.id == id {return item.thread}
	}
	return nil
}

Debugger_IsPaused :: proc(L: ^State) -> bool {
	dbg := debugger_for(L)
	item := debugger_thread(dbg, L)
	return item != nil && item.paused
}

Debugger_PausedThreads :: proc(L: ^State) -> []^State {
	dbg := debugger_for(L)
	result: [dynamic]^State
	if dbg == nil {return nil}
	for item in dbg.threads {
		if item.paused {append(&result, item.thread)}
	}
	return result[:]
}

Debugger_Resume :: proc(L: ^State, mode: Debug_Step_Mode = .None) -> bool {
	dbg := debugger_for(L)
	item := debugger_thread(dbg, L)
	if dbg == nil || !dbg.enabled || item == nil || !item.paused {return false}
	item.paused = false
	item.skip_break_once = true
	item.step_line = item.line
	item.step_depth = luauh.lua_stackdepth(L)
	item.step_mode = mode
	luauh.lua_singlestep(L, mode != .None ? 1 : 0)
	return true
}

Debugger_RequestPause :: proc(L: ^State) -> bool {
	dbg := debugger_for(L)
	if dbg == nil || !dbg.enabled {return false}
	item := debugger_thread(dbg, L, true)
	if item.paused {return true}
	item.step_mode = .Into
	item.step_line = -1
	item.step_depth = luauh.lua_stackdepth(L)
	luauh.lua_singlestep(L, 1)
	return true
}

Debugger_ForgetThread :: proc(L: ^State) {
	dbg := debugger_for(L)
	if dbg == nil {return}
	for i := len(dbg.closures) - 1; i >= 0; i -= 1 {
		if dbg.closures[i].thread != L {continue}
		ReleaseValue(dbg.root, dbg.closures[i].reference)
		delete(dbg.closures[i].source)
		ordered_remove(&dbg.closures, i)
	}
	for item, i in dbg.threads {
		if item.thread != L {continue}
		luauh.lua_singlestep(L, 0)
		delete(item.source)
		ordered_remove(&dbg.threads, i)
		return
	}
}


Debugger_Preview :: proc(L: ^State, index: int) -> string {
	#partial switch TypeOf(L, index) {
	case .Nil:
		return "nil"
	case .Boolean:
		return fmt.tprintf("%v", ArgBoolean(L, index))
	case .Number, .Integer:
		number, _ := ToNumber(L, index)
		return fmt.tprintf("%g", number)
	case .String:
		value, _ := ToString(L, index)
		if len(value) > 160 {return fmt.tprintf("%s...", value[:160])}
		return strings.clone(value, context.temp_allocator)
	case .Table:
		return fmt.tprintf("table (%d array entries)", RawLen(L, index))
	case:
		return TypeName(L, index)
	}
}

Debugger_GetFrames :: proc(L: ^State) -> []Debug_Frame {
	if !Debugger_IsPaused(L) {return nil}
	item := debugger_thread(debugger_for(L), L)
	result: [dynamic]Debug_Frame
	for level: i32 = 0; level < min(luauh.lua_stackdepth(L), 64); level += 1 {
		info, valid := debugger_frame(L, level)
		if !valid {continue}
		append(
			&result,
			Debug_Frame {
				source = info.source != nil ? strings.clone(string(info.source)) : "",
				name = info.name != nil ? strings.clone(string(info.name)) : "",
				line = item != nil && level == 0 && item.line > 0 ? item.line : info.currentline,
				depth = level,
			},
		)
	}
	return result[:]
}

Debug_Frame :: struct {
	source: string,
	name:   string,
	line:   i32,
	depth:  i32,
}

Debugger_FreeFrames :: proc(frames: []Debug_Frame) {
	for frame in frames {delete(frame.source); delete(frame.name)}
	delete(frames)
}

Debug_Variable :: struct {
	name:      string,
	value:     string,
	type_name: string,
}

Debugger_GetLocals :: proc(L: ^State, level: i32) -> []Debug_Variable {
	if !Debugger_IsPaused(L) || level < 0 || level >= 64 {return nil}
	result: [dynamic]Debug_Variable
	for index: i32 = 1; index <= 64; index += 1 {
		name := luauh.lua_getlocal(L, level, index)
		if name == nil {break}
		append(
			&result,
			Debug_Variable {
				name = strings.clone(string(name)),
				value = strings.clone(Debugger_Preview(L, -1)),
				type_name = strings.clone(TypeName(L, -1)),
			},
		)
		Pop(L)
	}
	return result[:]
}

Debugger_FreeVariables :: proc(vars: []Debug_Variable) {
	for var in vars {delete(var.name); delete(var.value); delete(var.type_name)}
	delete(vars)
}

Debugger_GetBreakpoints :: proc(L: ^State) -> []Debug_Breakpoint {
	dbg := debugger_for(L)
	if dbg == nil {return nil}
	result := make([]Debug_Breakpoint, len(dbg.breakpoints))
	for bp, i in dbg.breakpoints {
		result[i] = Debug_Breakpoint {
			source        = strings.clone(bp.source),
			line          = bp.line,
			resolved_line = bp.resolved_line,
		}
	}
	return result
}

Debugger_FreeBreakpoints :: proc(points: []Debug_Breakpoint) {
	for bp in points {delete(bp.source)}
	delete(points)
}
