package luau

import platform "../platform"
import luauh "luauh"

GC_Step_Budgeted :: proc(L: ^State, budget_ns: u64) -> int {
	if L == nil || budget_ns == 0 {return 0}
	if luauh.lua_gc(L, i32(luauh.lua_GCOp.ISRUNNING), 0) == 0 ||
	   luauh.lua_gc(L, i32(luauh.lua_GCOp.ISPAUSED), 0) != 0 {return 0}
	start := platform.GetTicksNS()
	steps := 0
	for steps < 64 {
		if platform.GetTicksNS() - start >= budget_ns {break}
		completed := luauh.lua_gc(L, i32(luauh.lua_GCOp.STEP), 0)
		steps += 1
		if completed != 0 || luauh.lua_gc(L, i32(luauh.lua_GCOp.ISPAUSED), 0) != 0 {break}
	}
	return steps
}
