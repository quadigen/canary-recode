package luau

import "core:testing"
import luauh "luauh"

@(test)
budgeted_gc_test :: proc(t: ^testing.T) {
	vm := New()
	defer Close(&vm)
	L := vm.L
	testing.expect_value(t, GC_Step_Budgeted(nil, 450_000), 0)
	testing.expect_value(t, GC_Step_Budgeted(L, 0), 0)
	_ = luauh.lua_gc(L, i32(luauh.lua_GCOp.STOP), 0)
	testing.expect_value(t, GC_Step_Budgeted(L, 450_000), 0)
	testing.expect_value(t, luauh.lua_gc(L, i32(luauh.lua_GCOp.ISRUNNING), 0), i32(0))
	_ = luauh.lua_gc(L, i32(luauh.lua_GCOp.RESTART), 0)
	ok, err := Run(
		&vm,
		`live = {}
for i=1,10000 do
    live[i] = {i,i*2}
end
for i=1,10000 do
    local temporary = {i,i+1,i+2}
end
`,
		"gc_pacing_live",
	)
	testing.expect(t, ok, err)
	if !ok {delete(err); return}
	_ = luauh.lua_gc(L, i32(luauh.lua_GCOp.STEP), 0)
	total := 0
	for _ in 0 ..< 1024 {
		steps := GC_Step_Budgeted(L, 450_000)
		testing.expect(t, steps <= 64)
		total += steps
		if steps == 0 {break}
	}
	testing.expect(t, total > 0 || luauh.lua_gc(L, i32(luauh.lua_GCOp.ISPAUSED), 0) != 0)
	ok, err = Run(
		&vm,
		`for i=1,10000 do
    assert(live[i][1]==i and live[i][2]==i*2)
end
`,
		"gc_pacing_validate",
	)
	testing.expect(t, ok, err)
	if !ok {delete(err)}
}
