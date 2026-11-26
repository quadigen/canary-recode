#+build !js
package profiling

import luauh "../vm/luauh"
import "core:testing"

@(test)
gc_step_timing_test :: proc(t: ^testing.T) {
	L := luauh.luaL_newstate()
	defer luauh.lua_close(L)
	gc_current_frame = {}
	gc_last_frame = {}
	testing.expect(t, set_gc_profiling(L, true))
	testing.expect(t, gc_profiling_enabled(L))
	for _ in 0 ..< 64 {
		_ = luauh.lua_gc(L, 6, 1)
	}
	gc_frame_tick()
	stats := last_gc_stats()
	testing.expect(t, stats.steps >= 64)
	testing.expect(t, stats.total_ns >= stats.max_ns)
	testing.expect(t, set_gc_profiling(L, false))
	testing.expect(t, !gc_profiling_enabled(L))
	_ = luauh.lua_gc(L, 6, 1)
	gc_frame_tick()
	testing.expect_value(t, last_gc_stats().steps, u64(0))
}
