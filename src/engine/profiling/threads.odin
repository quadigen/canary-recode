
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
	rows:              [dynamic]Thread_Row,
	total_alloc_bytes: u64,
}

Thread_Record :: struct {
	id:                 u64,
	L:                  ^luauh.lua_State,
	root:               ^luauh.lua_State,
	alive:              bool,
	name:               string,
	script:             string,
	death_serial:       u64,
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
block_owner: map[rawptr]Block_Owner
active_stack: [dynamic]^Thread_Record
frame_dirty_records: [dynamic]^Thread_Record
thread_history: [dynamic]Thread_Frame_Data
script_totals: [dynamic]Script_Total
thread_frame_serial: u64
retired_pending: int
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
				rec.death_serial = thread_frame_serial + 1
				retired_pending += 1
				delete_key(&record_by_ptr, thread)
			}
		} else if _, ok := record_by_ptr[thread]; !ok {
			root := parent
			if parent_record, tracked := record_by_ptr[parent]; tracked {
				root = parent_record.root
			}
			record := new(Thread_Record)
			record^ = Thread_Record {
				id    = next_thread_id,
				L     = thread,
				root  = root,
				alive = true,
			}
			next_thread_id += 1
			append(&thread_records, record)
			record_by_ptr[thread] = record
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


	context = tracy.DefaultContext()

	if previous, ok := block_owner[block]; ok {
		if previous.record != nil {
			previous.record.live_bytes -= i64(previous.size)
			previous.record.free_bytes += previous.size
			previous.record.frame_free_bytes += previous.size
			thread_record_touch(previous.record)
		}
		delete_key(&block_owner, block)
	}
	if nsize == 0 {
		return
	}
	record, tracked := record_by_ptr[L]
	if !tracked {


		return
	}
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
	retired_pending = 0
	for record in thread_records {
		if record.name != "" {
			delete(record.name)
		}
		if record.script != "" {
			delete(record.script)
		}
		free(record)
	}
	clear(&thread_records)
	clear(&record_by_ptr)
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
	thread_frame_serial = 0
	next_thread_id = 1
	thread_tracking_on = true
}


thread_frame_flush :: proc() {
	context = tracy.DefaultContext()
	thread_frame_serial += 1
	frame := Thread_Frame_Data{}
	for record in frame_dirty_records {
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
	if len(thread_history) >= MAX_HISTORY {
		oldest := thread_history[0]
		delete(oldest.rows)
		ordered_remove(&thread_history, 0)
	}
	append(&thread_history, frame)
	sweep_dead_thread_records()
}


thread_frame_discard :: proc() {
	for record in frame_dirty_records {
		record.frame_cpu_ns = 0
		record.frame_total_cpu_ns = 0
		record.frame_resumes = 0
		record.frame_alloc_bytes = 0
		record.frame_free_bytes = 0
		record.frame_touched = false
	}
	clear(&frame_dirty_records)
}


sweep_dead_thread_records :: proc() {
	if retired_pending == 0 || len(thread_history) == 0 {
		return
	}
	context = tracy.DefaultContext()
	oldest := thread_frame_serial - u64(len(thread_history)) + 1
	write := 0
	for read in 0 ..< len(thread_records) {
		record := thread_records[read]
		retired :=
			!record.alive &&
			record.start_ns == 0 &&
			record.live_bytes == 0 &&
			record.death_serial != 0 &&
			record.death_serial < oldest
		if retired {
			fold_into_script_totals(record)
			if record.name != "" {
				delete(record.name)
			}
			if record.script != "" {
				delete(record.script)
			}
			free(record)
			retired_pending -= 1
			continue
		}
		thread_records[write] = record
		write += 1
	}
	if write < len(thread_records) {
		resize(&thread_records, write)
	}
}


fold_into_script_totals :: proc(record: ^Thread_Record) {
	context = tracy.DefaultContext()
	name := script_identity(record)
	total := find_script_total(record.root, name)
	if total == nil {
		append(&script_totals, Script_Total{root = record.root, name = strings.clone(name)})
		total = &script_totals[len(script_totals) - 1]
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
	for &total in script_totals {
		if total.root == root && total.name == name {
			return &total
		}
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
	for record in thread_records {
		if record.id == id {
			return record
		}
	}
	return nil
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


set_thread_name :: proc(L: ^luauh.lua_State, name: string, script: string = "") {
	if L == nil || name == "" {
		return
	}
	record, ok := record_by_ptr[L]
	if !ok {
		return
	}
	identity := script
	if identity == "" {
		identity = name
	}
	context = tracy.DefaultContext()
	if record.name != "" {
		delete(record.name)
	}
	if record.script != "" {
		delete(record.script)
	}
	record.name = strings.clone(name)
	record.script = strings.clone(identity)
}


script_identity :: proc(record: ^Thread_Record) -> string {
	if record == nil {
		return "Unknown"
	}
	if record.script != "" {
		return record.script
	}
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
