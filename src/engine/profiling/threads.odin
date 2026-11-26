
package profiling

import platform "../platform"
import tracy "../util/odin-tracy"
import luauh "../vm/luauh"
import "core:fmt"
import "core:strings"


Thread_Row :: struct {
	id:           u64,
	cpu_ns:       u64,
	total_cpu_ns: u64,
	resumes:      u64,
	alloc_bytes:  u64,
	free_bytes:   u64,
}

Thread_Frame_Data :: struct {
	serial:            u64,
	rows:              [dynamic]Thread_Row,
	total_alloc_bytes: u64,
}

Thread_Record :: struct {
	id:                 u64,
	record_index:       int,
	L:                  ^luauh.lua_State,
	root:               ^luauh.lua_State,
	alive:              bool,
	name:               string,
	script:             string,
	callback_source:    string,
	last_sample_serial: u64,
	cpu_ns:             u64,
	total_cpu_ns:       u64,
	resumes:            u64,
	alloc_bytes:        u64,
	free_bytes:         u64,
	live_bytes:         i64,
	start_ns:           u64,
	nested_ns:          u64,
	frame_cpu_ns:       u64,
	frame_total_cpu_ns: u64,
	frame_resumes:      u64,
	frame_alloc_bytes:  u64,
	frame_free_bytes:   u64,
	frame_touched:      bool,
}

Block_Owner :: struct {
	record: ^Thread_Record,
	size:   u64,
}


Script_Total_Key :: struct {
	root: ^luauh.lua_State,
	name: string,
}

Script_Total :: struct {
	root:         ^luauh.lua_State,
	name:         string,
	cpu_ns:       u64,
	total_cpu_ns: u64,
	resumes:      u64,
	alloc_bytes:  u64,
	free_bytes:   u64,
	live_bytes:   i64,
	threads:      u64,
}


Script_Stat :: struct {
	name:          string,
	cpu_ns:        u64,
	total_cpu_ns:  u64,
	resumes:       u64,
	alloc_bytes:   u64,
	free_bytes:    u64,
	live_bytes:    i64,
	threads:       u64,
	alive_threads: u64,
}

thread_records: [dynamic]^Thread_Record
record_by_ptr: map[^luauh.lua_State]^Thread_Record
record_by_id: map[u64]^Thread_Record
callback_sources: map[string]string
Thread_Name_Entry :: struct {
	value: string,
	refs:  int,
}
thread_names: map[string]Thread_Name_Entry
script_total_index: map[Script_Total_Key]int
retirement_queue: [dynamic]^Thread_Record
retirement_cursor: int
block_owner: map[rawptr]Block_Owner
active_stack: [dynamic]^Thread_Record
frame_dirty_records: [dynamic]^Thread_Record
thread_history: [dynamic]Thread_Frame_Data
script_totals: [dynamic]Script_Total
thread_frame_serial: u64
next_thread_id: u64 = 1
thread_state_ready: bool
thread_tracking_on: bool = true
chained_userthread: proc "c" (parent, thread: ^luauh.lua_State)


thread_record_touch :: #force_inline proc(record: ^Thread_Record) {
	if record == nil || record.frame_touched {
		return
	}
	record.frame_touched = true
	append(&frame_dirty_records, record)
}


tracking_userthread :: proc "c" (parent, thread: ^luauh.lua_State) {
	context = tracy.DefaultContext()
	if thread != nil {
		if parent == nil {


			if rec, ok := record_by_ptr[thread]; ok {
				rec.alive = false
				rec.L = nil
				append(&retirement_queue, rec)
				delete_key(&record_by_ptr, thread)
			}
		} else if _, ok := record_by_ptr[thread]; !ok {
			root := parent
			if parent_record, tracked := record_by_ptr[parent]; tracked {
				root = parent_record.root
			}
			record := new(Thread_Record)
			record^ = Thread_Record {
				id           = next_thread_id,
				record_index = len(thread_records),
				L            = thread,
				root         = root,
				alive        = true,
			}
			next_thread_id += 1
			append(&thread_records, record)
			record_by_ptr[thread] = record
			record_by_id[record.id] = record
		}
	}
	if chained_userthread != nil {
		chained_userthread(parent, thread)
	}
}

tracking_preresume :: proc "c" (L: ^luauh.lua_State) {
	context = tracy.DefaultContext()
	record, ok := record_by_ptr[L]
	if !ok {
		return
	}
	record.start_ns = platform.GetTicksNS()
	record.nested_ns = 0
	record.resumes += 1
	record.frame_resumes += 1
	thread_record_touch(record)
	append(&active_stack, record)
}

tracking_postresume :: proc "c" (L: ^luauh.lua_State) {
	context = tracy.DefaultContext()
	record, ok := record_by_ptr[L]
	if !ok {
		return
	}


	stack_pos := -1
	for index := len(active_stack) - 1; index >= 0; index -= 1 {
		if active_stack[index] == record {
			stack_pos = index
			break
		}
	}
	if stack_pos < 0 {
		return
	}
	resize(&active_stack, stack_pos)

	if record.start_ns == 0 {
		return
	}
	now := platform.GetTicksNS()
	if now < record.start_ns {
		record.start_ns = 0
		record.nested_ns = 0
		return
	}
	slice_ns := now - record.start_ns
	record.start_ns = 0
	nested_ns := record.nested_ns
	record.nested_ns = 0

	exclusive_ns := u64(0)
	if slice_ns > nested_ns {
		exclusive_ns = slice_ns - nested_ns
	}
	record.cpu_ns += exclusive_ns
	record.total_cpu_ns += slice_ns
	record.frame_cpu_ns += exclusive_ns
	record.frame_total_cpu_ns += slice_ns


	if len(active_stack) > 0 {
		parent := active_stack[len(active_stack) - 1]
		parent.nested_ns += slice_ns
	}
}

tracking_onallocate :: proc "c" (
	L: ^luauh.lua_State,
	block: rawptr,
	osize: uintptr,
	nsize: uintptr,
	memcat: u8,
	tt: i32,
	tag: i32,
) {
	if !thread_tracking_on || block == nil {
		return
	}


	if nsize == 0 {return}
	record: ^Thread_Record
	if len(active_stack) > 0 {
		active := active_stack[len(active_stack) - 1]
		if active.L == L {record = active}
	}
	if record == nil {record = record_by_ptr[L]}
	if record == nil {return}
	context = tracy.DefaultContext()
	record.live_bytes += i64(nsize)
	size := u64(nsize)
	record.alloc_bytes += size
	record.frame_alloc_bytes += size
	thread_record_touch(record)
	block_owner[block] = Block_Owner {
		record = record,
		size   = size,
	}
}

tracking_onfree :: proc "c" (L: ^luauh.lua_State, block: rawptr) {
	if !thread_tracking_on || block == nil {
		return
	}
	previous, ok := block_owner[block]
	if !ok {
		return
	}


	context = tracy.DefaultContext()
	if previous.record != nil {
		previous.record.live_bytes -= i64(previous.size)
		previous.record.free_bytes += previous.size
		previous.record.frame_free_bytes += previous.size
		thread_record_touch(previous.record)
	}
	delete_key(&block_owner, block)
}


install_thread_hooks :: proc(L: ^luauh.lua_State) {
	if L == nil {
		return
	}
	context = tracy.DefaultContext()
	if !thread_state_ready {
		reset_thread_state()
		thread_state_ready = true
	}
	callbacks := luauh.lua_callbacks(L)
	if callbacks == nil || callbacks.userthread == tracking_userthread {
		return
	}
	if callbacks.userthread != nil {
		chained_userthread = callbacks.userthread
	}
	callbacks.userthread = tracking_userthread
	callbacks.preresume = tracking_preresume
	callbacks.postresume = tracking_postresume
	callbacks.onallocate = tracking_onallocate
	callbacks.onfree = tracking_onfree
}


shutdown_thread_state :: proc() {
	reset_thread_state()
	thread_state_ready = false
	chained_userthread = nil
}

reset_thread_state :: proc() {
	context = tracy.DefaultContext()
	clear(&frame_dirty_records)
	clear(&retirement_queue)
	retirement_cursor = 0
	for record in thread_records {
		free(record)
	}
	clear(&thread_records)
	for name in thread_names {delete(name)}
	clear(&thread_names)
	clear(&record_by_ptr)
	clear(&record_by_id)
	for _, source in callback_sources {delete(source)}
	clear(&callback_sources)
	clear(&block_owner)
	clear(&active_stack)
	for frame in thread_history {
		delete(frame.rows)
	}
	clear(&thread_history)
	for &total in script_totals {
		if total.name != "" {
			delete(total.name)
		}
	}
	clear(&script_totals)
	clear(&script_total_index)
	thread_frame_serial = 0
	next_thread_id = 1
	thread_tracking_on = true
}


thread_frame_flush :: proc() {
	context = tracy.DefaultContext()
	thread_frame_serial += 1
	frame := Thread_Frame_Data {
		serial = thread_frame_serial,
	}
	if len(thread_history) >= MAX_HISTORY {
		frame.rows = thread_history[0].rows
		clear(&frame.rows)
		ordered_remove(&thread_history, 0)
	}
	for record in frame_dirty_records {
		record.last_sample_serial = frame.serial
		append(
			&frame.rows,
			Thread_Row {
				id = record.id,
				cpu_ns = record.frame_cpu_ns,
				total_cpu_ns = record.frame_total_cpu_ns,
				resumes = record.frame_resumes,
				alloc_bytes = record.frame_alloc_bytes,
				free_bytes = record.frame_free_bytes,
			},
		)
		frame.total_alloc_bytes += record.frame_alloc_bytes
		record.frame_cpu_ns = 0
		record.frame_total_cpu_ns = 0
		record.frame_resumes = 0
		record.frame_alloc_bytes = 0
		record.frame_free_bytes = 0
		record.frame_touched = false
	}
	clear(&frame_dirty_records)
	append(&thread_history, frame)
	sweep_dead_thread_records()
}


thread_frame_discard :: proc() {
	thread_frame_serial += 1
	for record in frame_dirty_records {
		record.frame_cpu_ns = 0
		record.frame_total_cpu_ns = 0
		record.frame_resumes = 0
		record.frame_alloc_bytes = 0
		record.frame_free_bytes = 0
		record.frame_touched = false
	}
	clear(&frame_dirty_records)
	sweep_dead_thread_records()
}


sweep_dead_thread_records :: proc() {
	if len(retirement_queue) == 0 {return}
	context = tracy.DefaultContext()
	oldest := thread_frame_serial + 1
	if len(thread_history) > 0 {oldest = thread_history[0].serial}
	budget := min(1024, len(retirement_queue))
	for _ in 0 ..< budget {
		if len(retirement_queue) == 0 {break}
		if retirement_cursor >= len(retirement_queue) {retirement_cursor = 0}
		record := retirement_queue[retirement_cursor]
		if record.alive ||
		   record.start_ns != 0 ||
		   record.live_bytes != 0 ||
		   record.frame_touched ||
		   record.last_sample_serial >= oldest {
			retirement_cursor += 1
			continue
		}
		fold_into_script_totals(record)
		delete_key(&record_by_id, record.id)
		index := record.record_index
		last := len(thread_records) - 1
		if index != last {
			moved := thread_records[last]
			thread_records[index] = moved
			moved.record_index = index
		}
		resize(&thread_records, last)
		unordered_remove(&retirement_queue, retirement_cursor)
		release_thread_name(record.name)
		release_thread_name(record.script)
		free(record)
	}
}


fold_into_script_totals :: proc(record: ^Thread_Record) {
	context = tracy.DefaultContext()
	name := script_identity(record)
	total := find_script_total(record.root, name)
	if total == nil {
		append(&script_totals, Script_Total{root = record.root, name = strings.clone(name)})
		total = &script_totals[len(script_totals) - 1]
		script_total_index[Script_Total_Key{record.root, total.name}] = len(script_totals) - 1
	}
	total.cpu_ns += record.cpu_ns
	total.total_cpu_ns += record.total_cpu_ns
	total.resumes += record.resumes
	total.alloc_bytes += record.alloc_bytes
	total.free_bytes += record.free_bytes
	total.live_bytes += record.live_bytes
	total.threads += 1
}

find_script_total :: proc(root: ^luauh.lua_State, name: string) -> ^Script_Total {
	if index, ok := script_total_index[Script_Total_Key{root, name}]; ok {
		return &script_totals[index]
	}
	return nil
}


all_thread_records :: proc() -> []^Thread_Record {
	return thread_records[:]
}

thread_history_frames :: proc() -> []Thread_Frame_Data {
	return thread_history[:]
}

find_thread_record :: proc(id: u64) -> ^Thread_Record {
	return record_by_id[id]
}


script_stats :: proc(root: ^luauh.lua_State) -> [dynamic]Script_Stat {
	context = tracy.DefaultContext()
	result: [dynamic]Script_Stat
	index := make(map[string]int)
	defer delete(index)

	slot :: proc(
		result: ^[dynamic]Script_Stat,
		index: ^map[string]int,
		name: string,
	) -> ^Script_Stat {
		if at, ok := index[name]; ok {
			return &result[at]
		}
		index[name] = len(result)
		append(result, Script_Stat{name = name})
		return &result[len(result) - 1]
	}

	for total in script_totals {
		if total.root != root {
			continue
		}
		stat := slot(&result, &index, total.name)
		stat.cpu_ns += total.cpu_ns
		stat.total_cpu_ns += total.total_cpu_ns
		stat.resumes += total.resumes
		stat.alloc_bytes += total.alloc_bytes
		stat.free_bytes += total.free_bytes
		stat.live_bytes += total.live_bytes
		stat.threads += total.threads
	}

	for record in thread_records {
		if record.root != root {
			continue
		}
		stat := slot(&result, &index, script_identity(record))
		stat.cpu_ns += record.cpu_ns
		stat.total_cpu_ns += record.total_cpu_ns
		stat.resumes += record.resumes
		stat.alloc_bytes += record.alloc_bytes
		stat.free_bytes += record.free_bytes
		stat.live_bytes += record.live_bytes
		stat.threads += 1
		if record.alive {
			stat.alive_threads += 1
		}
	}

	return result
}


caller_root :: proc(L: ^luauh.lua_State) -> ^luauh.lua_State {
	if L == nil {
		return nil
	}
	if record, ok := record_by_ptr[L]; ok {
		return record.root
	}
	return L
}


thread_display_name :: proc(record: ^Thread_Record) -> string {
	if record == nil {
		return "Thread"
	}
	if record.name != "" {
		return record.name
	}
	if record.callback_source != "" {return record.callback_source}
	if record.L != nil {
		info: luauh.lua_Debug
		if luauh.lua_getinfo(record.L, 0, "nS", &info) != 0 {
			if info.name != nil && info.short_src != nil {
				return fmt.tprintf("%s @ %s:%d", info.name, info.short_src, info.linedefined)
			}
			if info.short_src != nil && info.linedefined > 0 {
				return fmt.tprintf("%s:%d", info.short_src, info.linedefined)
			}
		}
	}
	return fmt.tprintf("Thread #%d", record.id)
}


callback_source :: proc(L: ^luauh.lua_State, index: int) -> string {
	if L == nil {return ""}
	relative := index
	if index > 0 {relative = index - int(luauh.lua_gettop(L)) - 1}
	if relative >= 0 {return ""}
	info: luauh.lua_Debug
	if luauh.lua_getinfo(L, i32(relative), "s", &info) == 0 || info.source == nil {return ""}
	source := string(info.source)
	if len(source) == 0 || source == "=[C]" {return ""}
	if saved, ok := callback_sources[source]; ok {return saved}
	context = tracy.DefaultContext()
	saved := strings.clone(source)
	callback_sources[saved] = saved
	return saved
}

set_callback_source :: proc(L: ^luauh.lua_State, source: string) {
	if source == "" {return}
	if record := record_by_ptr[L]; record != nil {record.callback_source = source}
}

retain_thread_name :: proc(name: string) -> string {
	if name == "" {return ""}
	if entry, ok := thread_names[name]; ok {
		entry.refs += 1
		thread_names[name] = entry
		return entry.value
	}
	saved := strings.clone(name)
	thread_names[saved] = Thread_Name_Entry{saved, 1}
	return saved
}

release_thread_name :: proc(name: string) {
	if name == "" {return}
	entry, ok := thread_names[name]
	if !ok {return}
	if entry.refs > 1 {
		entry.refs -= 1
		thread_names[name] = entry
	} else {
		delete_key(&thread_names, name)
		delete(entry.value)
	}
}

set_thread_name :: proc(L: ^luauh.lua_State, name: string, script: string = "") {
	if L == nil || name == "" {return}
	record, ok := record_by_ptr[L]
	if !ok {return}
	identity := script
	if identity == "" {identity = name}
	if record.name == name && record.script == identity {return}
	context = tracy.DefaultContext()
	next_name := retain_thread_name(name)
	next_script := retain_thread_name(identity)
	release_thread_name(record.name)
	release_thread_name(record.script)
	record.name = next_name
	record.script = next_script
}


script_identity :: proc(record: ^Thread_Record) -> string {
	if record == nil {
		return "Unknown"
	}
	if record.script != "" {
		return record.script
	}
	if record.callback_source != "" {return record.callback_source}
	if record.name != "" {
		return record.name
	}
	return "Unknown"
}

is_tracking_enabled :: proc() -> bool {
	return thread_tracking_on
}


set_tracking_enabled :: proc(on: bool) {
	if on == thread_tracking_on {
		return
	}
	thread_tracking_on = on
	if !on {
		context = tracy.DefaultContext()
		clear(&block_owner)
		for record in thread_records {
			record.live_bytes = 0
		}
	}
}

LUA_GCCOUNT :: 3


heap_bytes :: proc(L: ^luauh.lua_State) -> u64 {
	if L == nil {
		return 0
	}
	return u64(luauh.lua_gc(L, LUA_GCCOUNT, 0)) * 1024
}


allocation_rate_bytes_per_sec :: proc() -> f64 {
	thread_frames := thread_history
	zone_frames := history
	count := len(thread_frames)
	if count > len(zone_frames) {
		count = len(zone_frames)
	}
	window := min(count, 30)
	if window == 0 {
		return 0
	}
	bytes_total: u64
	ns_total: u64
	for index := count - window; index < count; index += 1 {
		bytes_total += thread_frames[index].total_alloc_bytes
		ns_total += zone_frames[index].delta_ns
	}
	if ns_total == 0 {
		return 0
	}
	return f64(bytes_total) / (f64(ns_total) * 1e-9)
}
