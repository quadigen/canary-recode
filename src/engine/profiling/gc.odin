package profiling

import "base:runtime"
import platform "../platform"
import luauh "../vm/luauh"

GC_Frame_Stats :: struct {
	steps:    u64,
	total_ns: u64,
	max_ns:   u64,
}

@(thread_local)
gc_current_frame: GC_Frame_Stats
@(thread_local)
gc_last_frame: GC_Frame_Stats
@(thread_local)
gc_started_ns: u64
@(thread_local)
gc_in_step: bool

gc_interrupt :: proc "c" (L: ^luauh.lua_State, state: i32) {
	context = runtime.default_context()
	if state < 0 {return}
	if !gc_in_step {
		gc_started_ns = platform.GetTicksNS()
		gc_in_step = true
		return
	}
	elapsed := platform.GetTicksNS() - gc_started_ns
	gc_in_step = false
	gc_current_frame.steps += 1
	gc_current_frame.total_ns += elapsed
	gc_current_frame.max_ns = max(gc_current_frame.max_ns, elapsed)
}

set_gc_profiling :: proc(L: ^luauh.lua_State, enabled: bool) -> bool {
	if L == nil {return false}
	callbacks := luauh.lua_callbacks(L)
	if callbacks == nil {return false}
	if enabled {
		if callbacks.interrupt != nil && callbacks.interrupt != gc_interrupt {return false}
		callbacks.interrupt = gc_interrupt
	} else if callbacks.interrupt == gc_interrupt {
		callbacks.interrupt = nil
		gc_in_step = false
	}
	return true
}

gc_profiling_enabled :: proc(L: ^luauh.lua_State) -> bool {
	if L == nil {return false}
	callbacks := luauh.lua_callbacks(L)
	return callbacks != nil && callbacks.interrupt == gc_interrupt
}

gc_frame_tick :: proc() {
	gc_last_frame = gc_current_frame
	gc_current_frame = {}
}

last_gc_stats :: proc() -> GC_Frame_Stats {return gc_last_frame}
