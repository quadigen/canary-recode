#+build !js
package services

import datatypes "../datatypes"
import target "../target"
import vm "../vm"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

PLAYTEST_DEBUG_MAGIC :: u32(0x32474244)
PLAYTEST_DEBUG_REQUEST_MAGIC :: u32(0x51574244)
PLAYTEST_DEBUG_RESPONSE_MAGIC :: u32(0x52574244)
PLAYTEST_DEBUG_ENV :: "KINEMIUM_PLAYTEST_DEBUG_BOOT"
PLAYTEST_DEBUG_MAX_POINTS :: 512
PLAYTEST_DEBUG_MAX_THREADS :: 128
PLAYTEST_DEBUG_TIMEOUT :: 3 * time.Second

debug_remote_slot :: proc(role: string, service: ^PlaytestService) -> (int, bool) {
	if service == nil {return 0, false}
	if service.singleplayer && role == "Server" {return 1, false}
	if role == "Server" && playtest_process_active(service.server_process) {return 0, true}
	if role == "Client" && playtest_process_active(service.client_process) {return 1, true}
	return 0, false
}

debug_boot_path :: proc(dir: string) -> string {
	return pt_path(dir, "bootstrap.bin")
}

debug_boot_data :: proc(root: ^vm.State) -> []u8 {
	points := vm.Debugger_GetBreakpoints(root)
	defer vm.Debugger_FreeBreakpoints(points)
	result: [dynamic]u8
	pt_put_u32(&result, PLAYTEST_DEBUG_MAGIC)
	count := min(len(points), PLAYTEST_DEBUG_MAX_POINTS)
	pt_put_u32(&result, u32(count))
	for i in 0 ..< count {
		point := points[i]
		pt_put_string(&result, point.source)
		pt_put_u32(&result, u32(point.line))
	}
	return result[:]
}


Playtest_Debugger_Update_Boot :: proc(sc: ^ScriptContext) -> bool {
	if sc == nil || sc.vm_state == nil || !target.is_editor() {return false}
	if !vm.Debugger_Enabled(sc.vm_state.L) {return false}
	if sc.debug_bootstrap_dir == "" {
		dir, err := os.make_directory_temp("", "kinemium-debug-boot-*", context.allocator)
		if err != nil {return false}
		when ODIN_OS != .Windows {
			if os.change_mode(dir, os.Permissions{.Read_User, .Write_User, .Execute_User}) != nil {
				_ = os.remove_all(dir)
				delete(dir)
				return false
			}
		}
		sc.debug_bootstrap_dir = dir
	}
	path := debug_boot_path(sc.debug_bootstrap_dir)
	data := debug_boot_data(sc.vm_state.L)
	defer delete(data)
	if !pt_atomic_write(path, data) {return false}
	return os.set_env(PLAYTEST_DEBUG_ENV, path) == nil
}

Playtest_Debugger_Clear_Boot :: proc(sc: ^ScriptContext) {
	if sc == nil || sc.debug_bootstrap_dir == "" {return}
	path := debug_boot_path(sc.debug_bootstrap_dir)
	env_path := os.get_env(PLAYTEST_DEBUG_ENV, context.temp_allocator)
	if env_path == path {_ = os.unset_env(PLAYTEST_DEBUG_ENV)}
	_ = os.remove_all(sc.debug_bootstrap_dir)
	delete(sc.debug_bootstrap_dir)
	sc.debug_bootstrap_dir = ""
}

playtest_debugger_apply_points :: proc(root: ^vm.VM, data: []u8) -> bool {
	if root == nil || root.L == nil || len(data) < 8 {return false}
	r := Playtest_Tree_Reader {
		data = data,
	}
	if pt_get_u32(&r) != PLAYTEST_DEBUG_MAGIC {return false}
	count := pt_get_u32(&r)
	if count > PLAYTEST_DEBUG_MAX_POINTS {return false}

	points: [dynamic]vm.Debug_Breakpoint
	defer {
		for point in points {delete(point.source)}
		delete(points)
	}
	for _ in 0 ..< count {
		source := pt_get_string(&r)
		line := pt_get_u32(&r)
		if r.bad || len(source) == 0 || len(source) > 4096 || line < 1 || line > 1_000_000 {
			return false
		}
		append(&points, vm.Debug_Breakpoint{source = strings.clone(source), line = i32(line)})
	}
	if r.bad || r.pos != len(data) {return false}
	if !vm.Debugger_Enabled(root.L) {
		vm.SetOptimizationLevel(root, 0)
		vm.SetDebugLevel(root, 2)
		if !vm.Debugger_Enable(root.L, true) {return false}
	}
	old := vm.Debugger_GetBreakpoints(root.L)
	for point in old {
		_ = vm.Debugger_SetBreakpoint(root.L, point.source, point.line, false)
	}
	vm.Debugger_FreeBreakpoints(old)
	for point in points {_ = vm.Debugger_SetBreakpoint(root.L, point.source, point.line, true)}
	return true
}


Playtest_Debugger_Bootstrap :: proc(root: ^vm.VM, directory: string) -> bool {
	if root == nil || directory == "" || !target.is_playtest() {return false}
	path := os.get_env(PLAYTEST_DEBUG_ENV, context.temp_allocator)
	if path == "" {return false}
	data, ok := pt_read_file(path)
	if !ok {return false}
	defer delete(data)
	return playtest_debugger_apply_points(root, data)
}

debug_remote_push_thread :: proc(out: ^[dynamic]u8, sc: ^ScriptContext, thread: ^vm.State) {
	info, ok := vm.Debugger_ThreadInfo(thread)
	if !ok {pt_put_u32(out, 0); return}
	pt_put_u32(out, u32(info.id))
	pt_put_string(out, info.source)
	pt_put_u32(out, u32(max(0, info.line)))
	pt_put_string(out, info.reason)
	pt_put_string(out, ScriptContext_Describe_Thread(sc, thread))
}

debug_remote_snapshot :: proc(out: ^[dynamic]u8, sc: ^ScriptContext, id, depth: u32) {
	root := sc.vm_state.L
	pt_put_u32(out, vm.Debugger_Enabled(root) ? 1 : 0)
	threads := vm.Debugger_PausedThreads(root)
	defer delete(threads)
	pt_put_u32(out, u32(min(len(threads), PLAYTEST_DEBUG_MAX_THREADS)))
	for thread in threads[:min(len(threads), PLAYTEST_DEBUG_MAX_THREADS)] {
		debug_remote_push_thread(out, sc, thread)
	}
	points := vm.Debugger_GetBreakpoints(root)
	defer vm.Debugger_FreeBreakpoints(points)
	pt_put_u32(out, u32(min(len(points), PLAYTEST_DEBUG_MAX_POINTS)))
	for point in points[:min(len(points), PLAYTEST_DEBUG_MAX_POINTS)] {
		pt_put_string(out, point.source)
		pt_put_u32(out, u32(point.line))
		pt_put_u32(out, u32(max(point.resolved_line, 0)))
	}
	selected := id
	if selected == 0 && len(threads) > 0 {
		info, ok := vm.Debugger_ThreadInfo(threads[0])
		if ok {selected = u32(info.id)}
	}
	pt_put_u32(out, selected)
	thread := vm.Debugger_ThreadByID(root, u64(selected))
	if thread == nil || !vm.Debugger_IsPaused(thread) {
		pt_put_u32(out, 0)
		pt_put_u32(out, 0)
		return
	}
	frames := vm.Debugger_GetFrames(thread)
	defer vm.Debugger_FreeFrames(frames)
	pt_put_u32(out, u32(len(frames)))
	for frame in frames {
		pt_put_string(out, frame.source)
		pt_put_string(out, frame.name)
		pt_put_u32(out, u32(max(frame.line, 0)))
		pt_put_u32(out, u32(frame.depth))
	}
	variables := vm.Debugger_GetLocals(thread, i32(min(depth, 63)))
	defer vm.Debugger_FreeVariables(variables)
	pt_put_u32(out, u32(len(variables)))
	for v in variables {
		pt_put_string(out, v.name)
		pt_put_string(out, v.value)
		pt_put_string(out, v.type_name)
	}
}


Playtest_Debugger_Pump :: proc(dir: string, registry: ^Registry, root: ^vm.State) {
	if dir == "" || registry == nil || root == nil || !target.is_playtest() {return}
	path := pt_path(dir, "debug-request.bin")
	data, ok := pt_read_file(path)
	if !ok {return}
	defer delete(data)
	_ = os.remove(path)
	r := Playtest_Tree_Reader {
		data = data,
	}
	if pt_get_u32(&r) != PLAYTEST_DEBUG_REQUEST_MAGIC {return}
	seq := pt_get_u32(&r)
	action := pt_get_string(&r)
	id := pt_get_u32(&r)
	depth := pt_get_u32(&r)
	mode := pt_get_string(&r)
	boot := pt_get_bytes(&r)
	if r.bad || r.pos != len(data) || seq == 0 || len(action) > 64 {return}
	sc := ScriptContext_From_Registry(registry)
	if sc == nil || sc.vm_state == nil {return}
	err_message := ""
	switch action {
	case "sync":
		if !playtest_debugger_apply_points(
			sc.vm_state,
			boot,
		) {err_message = "Invalid breakpoint synchronization"}
	case "detach":
		_ = vm.Debugger_Enable(root, false)
	case "pause":
		if !vm.Debugger_Enabled(root) {err_message = "Debugger is not attached"}
		if err_message == "" {
			for entry in sc.threads {
				if entry.thread != nil {_ = vm.Debugger_RequestPause(entry.thread)}
			}
		}
	case "resume":
		if !script_debugger_resume_native(
			sc,
			id,
			mode,
		) {err_message = "Thread is not paused or mode is invalid"}
	case "snapshot":

	case:
		err_message = "Unsupported debug command"
	}
	response: [dynamic]u8
	defer delete(response)
	pt_put_u32(&response, PLAYTEST_DEBUG_RESPONSE_MAGIC)
	pt_put_u32(&response, seq)
	pt_put_u32(&response, err_message == "" ? 1 : 0)
	pt_put_string(&response, err_message)
	if err_message == "" {debug_remote_snapshot(&response, sc, id, depth)}
	filename := fmt.aprintf("debug-response-%d.bin", seq)
	defer delete(filename)
	output := pt_path(dir, filename)
	_ = pt_atomic_write(output, response[:])
}

debug_remote_get_service :: proc(sc: ^ScriptContext) -> ^PlaytestService {
	if sc == nil {return nil}
	object := Service_Get_Service(&sc.service, "PlaytestService")
	if object == nil || object.destroyed {return nil}
	return cast(^PlaytestService)object
}

debug_remote_parse_role :: proc(
	L: ^vm.State,
	sc: ^ScriptContext,
	role: string,
) -> (
	int,
	^PlaytestService,
	bool,
) {
	if !target.is_editor() {return 0, nil, false}
	service := debug_remote_get_service(sc)
	if service == nil || !service.running || service.tree_dir == "" {return 0, nil, false}
	slot, ok := debug_remote_slot(role, service)
	return slot, service, ok
}

debug_remote_begin :: proc(L: ^vm.State, sc: ^ScriptContext) -> i32 {
	role := vm.ArgString(L, 2)
	action := vm.ArgString(L, 3)
	id_number := vm.ArgOptionalNumber(L, 4, 0)
	depth_number := vm.ArgOptionalNumber(L, 5, 0)
	mode := vm.ArgOptionalString(L, 6, "continue")
	slot, service, ok := debug_remote_parse_role(L, sc, role)
	if !ok {vm.PushBoolean(L, false); return 1}
	if id_number < 0 ||
	   id_number > 4_294_967_295 ||
	   f64(u32(id_number)) != id_number ||
	   depth_number < 0 ||
	   depth_number > 63 ||
	   f64(u32(depth_number)) != depth_number {
		return vm.RaiseError(L, "Invalid debugger thread ID or frame depth")
	}
	if action != "snapshot" &&
	   action != "sync" &&
	   action != "resume" &&
	   action != "pause" &&
	   action != "detach" {
		return vm.RaiseError(L, "Invalid debugger command")
	}
	if sc.debug_remote_pending[slot].sequence != 0 {
		if time.tick_diff(time.tick_now(), sc.debug_remote_pending[slot].deadline) <= 0 {
			sc.debug_remote_pending[slot] = {}
		} else {
			vm.PushBoolean(L, false)
			return 1
		}
	}
	dir := pt_path(service.tree_dir, role)
	path := pt_path(dir, "debug-request.bin")
	if os.exists(path) {vm.PushBoolean(L, false); return 1}
	sc.debug_remote_sequence += 1
	if sc.debug_remote_sequence == 0 {sc.debug_remote_sequence = 1}
	seq := sc.debug_remote_sequence
	data: [dynamic]u8
	defer delete(data)
	pt_put_u32(&data, PLAYTEST_DEBUG_REQUEST_MAGIC)
	pt_put_u32(&data, seq)
	pt_put_string(&data, action)
	pt_put_u32(&data, u32(id_number))
	pt_put_u32(&data, u32(depth_number))
	pt_put_string(&data, mode)
	if action == "sync" {
		boot := debug_boot_data(sc.vm_state.L)
		defer delete(boot)
		pt_put_bytes(&data, boot)
	} else {
		pt_put_bytes(&data, nil)
	}
	if !pt_atomic_write(path, data[:]) {vm.PushBoolean(L, false); return 1}
	sc.debug_remote_pending[slot] = Debug_Remote_Pending {
		sequence = seq,
		deadline = time.tick_add(time.tick_now(), PLAYTEST_DEBUG_TIMEOUT),
	}
	vm.PushBoolean(L, true)
	return 1
}

debug_remote_push_result :: proc(L: ^vm.State, role: string, r: ^Playtest_Tree_Reader) -> bool {
	enabled := pt_get_u32(r) != 0
	vm.NewTable(L, 0, 7)
	vm.PushBoolean(L, enabled); vm.SetField(L, -2, "enabled")
	vm.PushString(L, role); vm.SetField(L, -2, "role")
	count := pt_get_u32(r)
	if count > PLAYTEST_DEBUG_MAX_THREADS {return false}
	vm.NewTable(L, int(count))
	for i in 0 ..< int(count) {
		id := pt_get_u32(r)
		source := pt_get_string(r)
		line := pt_get_u32(r)
		reason := pt_get_string(r)
		script := pt_get_string(r)
		vm.NewTable(L, 0, 5)
		vm.PushNumber(L, f64(id)); vm.SetField(L, -2, "id")
		vm.PushString(L, source); vm.SetField(L, -2, "source")
		vm.PushNumber(L, f64(line)); vm.SetField(L, -2, "line")
		vm.PushString(L, reason); vm.SetField(L, -2, "reason")
		vm.PushString(L, script); vm.SetField(L, -2, "script")
		vm.SetArrayValue(L, -2, i + 1)
	}
	vm.SetField(L, -2, "pausedThreads")
	count = pt_get_u32(r)
	if count > PLAYTEST_DEBUG_MAX_POINTS {return false}
	vm.NewTable(L, int(count))
	for i in 0 ..< int(count) {
		source := pt_get_string(r)
		line := pt_get_u32(r)
		resolved := pt_get_u32(r)
		vm.NewTable(L, 0, 3)
		vm.PushString(L, source); vm.SetField(L, -2, "source")
		vm.PushNumber(L, f64(line)); vm.SetField(L, -2, "line")
		vm.PushNumber(L, f64(resolved)); vm.SetField(L, -2, "resolvedLine")
		vm.SetArrayValue(L, -2, i + 1)
	}
	vm.SetField(L, -2, "breakpoints")
	selected := pt_get_u32(r)
	vm.PushNumber(L, f64(selected)); vm.SetField(L, -2, "selectedThread")
	count = pt_get_u32(r)
	if count > 64 {return false}
	vm.NewTable(L, int(count))
	for i in 0 ..< int(count) {
		source := pt_get_string(r)
		name := pt_get_string(r)
		line := pt_get_u32(r)
		depth := pt_get_u32(r)
		vm.NewTable(L, 0, 4)
		vm.PushString(L, source); vm.SetField(L, -2, "source")
		vm.PushString(L, name); vm.SetField(L, -2, "name")
		vm.PushNumber(L, f64(line)); vm.SetField(L, -2, "line")
		vm.PushNumber(L, f64(depth)); vm.SetField(L, -2, "depth")
		vm.SetArrayValue(L, -2, i + 1)
	}
	vm.SetField(L, -2, "frames")
	count = pt_get_u32(r)
	if count > 64 {return false}
	vm.NewTable(L, int(count))
	for i in 0 ..< int(count) {
		name := pt_get_string(r)
		value := pt_get_string(r)
		type_name := pt_get_string(r)
		vm.NewTable(L, 0, 3)
		vm.PushString(L, name); vm.SetField(L, -2, "name")
		vm.PushString(L, value); vm.SetField(L, -2, "value")
		vm.PushString(L, type_name); vm.SetField(L, -2, "type")
		vm.SetArrayValue(L, -2, i + 1)
	}
	vm.SetField(L, -2, "locals")
	return !r.bad
}

debug_remote_poll :: proc(L: ^vm.State, sc: ^ScriptContext) -> i32 {
	role := vm.ArgString(L, 2)
	slot, service, valid := debug_remote_parse_role(L, sc, role)
	if !valid {


		sc.debug_remote_pending = {}
		vm.PushNil(L)
		return 1
	}
	pending := &sc.debug_remote_pending[slot]
	if pending.sequence == 0 {vm.PushNil(L); return 1}
	dir := pt_path(service.tree_dir, role)
	filename := fmt.aprintf("debug-response-%d.bin", pending.sequence)
	defer delete(filename)
	path := pt_path(dir, filename)
	data, ok := pt_read_file(path)
	if !ok {
		if time.tick_diff(time.tick_now(), pending.deadline) <= 0 {
			pending^ = {}
			_ = os.remove(pt_path(dir, "debug-request.bin"))
			return vm.RaiseError(L, "Playtest debugger request timed out")
		}
		vm.PushNil(L)
		return 1
	}
	defer delete(data)
	_ = os.remove(path)
	seq := pending.sequence
	pending^ = {}
	r := Playtest_Tree_Reader {
		data = data,
	}
	if pt_get_u32(&r) != PLAYTEST_DEBUG_RESPONSE_MAGIC ||
	   pt_get_u32(&r) != seq {return vm.RaiseError(L, "Invalid debugger response")}
	success := pt_get_u32(&r) != 0
	reason := pt_get_string(&r)
	if r.bad {return vm.RaiseError(L, "Malformed debugger response")}
	if !success {return vm.RaiseError(L, reason)}
	top := vm.StackTop(L)
	if !debug_remote_push_result(L, role, &r) || r.pos != len(data) {
		vm.SetStackTop(L, top)
		return vm.RaiseError(L, "Malformed debugger snapshot")
	}
	return 1
}

Playtest_Debugger_Namecall :: proc(
	L: ^vm.State,
	sc: ^ScriptContext,
	method: string,
) -> (
	i32,
	bool,
) {
	if method != "DebugRemoteSend" && method != "DebugRemotePoll" {return 0, false}
	if !vm.ThreadHasSecurityCapability(L, datatypes.SECURITY_CAPABILITY_INTERNAL_STUDIO_ACCESS) {
		return vm.RaiseError(L, "Remote debugger commands require Studio privileges"), true
	}
	if sc == nil || sc.vm_state == nil || !target.is_editor() {
		return vm.RaiseError(L, "Remote debugging requires Kinemium Editor"), true
	}
	if method == "DebugRemoteSend" {return debug_remote_begin(L, sc), true}
	return debug_remote_poll(L, sc), true
}
