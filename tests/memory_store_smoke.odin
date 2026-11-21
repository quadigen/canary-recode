package main

import engine_runtime "../src/engine/runtime"
import target "../src/engine/target"
import vm "../src/engine/vm"
import sandbox "../src/sandboxed"
import "core:fmt"
import "core:time"

main :: proc() {
	target.set_mode(.Server)
	script_vm := vm.New()
	environment: engine_runtime.Environment
	sandbox.init_runtime(&script_vm, &environment, nil)
	defer {
		vm.Close(&script_vm)
		sandbox.shutdown()
	}
	ok, err := vm.Run(
		&script_vm,
		`
local service = game:GetService("MemoryStoreService")
local map = service:GetHashMap("players")
local other = service:GetMap("players")
assert(map.Name == "players")
assert(map:GetAsync("missing") == nil)
local original = {score = 10, nest = {1, 2}, [4] = "number"}
assert(map:SetAsync("player", original, 60))
original.nest[1] = 999
local got = other:GetAsync("player")
assert(got.score == 10 and got.nest[1] == 1 and got[4] == "number")
got.nest[1] = 777
assert(map:GetAsync("player").nest[1] == 1)
assert(map:UpdateAsync("player", function(old)
    old.score += 1
    return old
end, 60).score == 11)
assert(map:UpdateAsync("player", function() return nil end, 60) == nil)
assert(map:GetAsync("player").score == 11)
assert(not pcall(function()
    map:UpdateAsync("player", function()
        other:SetAsync("player", 999, 60)
        return 1
    end, 60)
end))
assert(map:GetAsync("player").score == 11)
assert(not pcall(function() map:UpdateAsync("player", function() error("transform failed") end, 60) end))
assert(map:UpdateAsync("new", function(old) assert(old == nil); return 3 end, 60) == 3)
assert(map:RemoveAsync("new") and not map:RemoveAsync("new"))
assert(not pcall(function() map:SetAsync("bad", 1, 0) end))
assert(not pcall(function() map:SetAsync("bad", 1, 0/0) end))
assert(not pcall(function() map:SetAsync("bad", string.rep("x", 33000), 60) end))
local cycle = {}; cycle.self = cycle
assert(not pcall(function() map:SetAsync("bad", cycle, 60) end))
assert(not pcall(function() map:SetAsync("bad", function() end, 60) end))
assert(tonumber(map:GetSizeAsync()) == 1, "size=" .. tostring(map:GetSizeAsync()))
assert(map:SetAsync("expire", "gone", 0.001))
local sorted = service:GetSortedMap("players")
assert(sorted:GetAsync("player") == nil)
assert(sorted:SetAsync("a", "A", 60, 10))
assert(sorted:SetAsync("b", "B", 60, 5))
assert(sorted:SetAsync("c", "C", 60, 10))
local v, k = sorted:GetAsync("a")
assert(v == "A" and k == 10)
local range = sorted:GetRangeAsync(Enum.SortDirection.Ascending, 3)
assert(#range == 3 and range[1].key == "b" and range[2].key == "a" and range[3].key == "c")
local bounded = sorted:GetRangeAsync(Enum.SortDirection.Ascending, 10, {key = "b", sortKey = 5}, {key = "c", sortKey = 10})
assert(#bounded == 1 and bounded[1].key == "a")
local desc = sorted:GetRangeAsync(Enum.SortDirection.Descending, 2)
assert(desc[1].key == "c" and desc[2].key == "a")
local updated, sortKey = sorted:UpdateAsync("b", function(old, key) return old .. "!", key + 2 end, 60)
assert(updated == "B!" and sortKey == 7)
local q = service:GetQueue("jobs", 0.05)
q:AddAsync("normal", 60)
q:AddAsync("high", 60, 10)
q:AddAsync("high2", 60, 10)
local empty, noReceipt = q:ReadAsync(4, true)
assert(#empty == 0 and noReceipt == nil)
local jobs, receipt = q:ReadAsync(2, true)
assert(jobs[1] == "high" and jobs[2] == "high2" and type(receipt) == "string")
local unrelated = service:GetQueue("unrelated", 1)
unrelated:AddAsync("other", 60)
local _, unrelatedReceipt = unrelated:ReadAsync(1, true)
assert(not unrelated:RemoveAsync(receipt))
assert(not q:RemoveAsync(unrelatedReceipt))
assert(unrelated:RemoveAsync(unrelatedReceipt))
assert(q:RemoveAsync(receipt) and not q:RemoveAsync(receipt))
local nextJobs, oldReceipt = q:ReadAsync(1, true)
assert(nextJobs[1] == "normal")
assert(#q:ReadAsync(1, false) == 0)
_G.oldReceipt = oldReceipt
`,
		"memory_store_smoke",
	)
	if !ok {fmt.eprintln(err); delete(err); panic("memory store smoke failed")}
	time.sleep(100 * time.Millisecond)
	ok, err = vm.Run(
		&script_vm,
		`
local service = game:GetService("MemoryStoreService")
assert(service:GetHashMap("players"):GetAsync("expire") == nil)
local q = service:GetQueue("jobs")
assert(not q:RemoveAsync(_G.oldReceipt))
local items, receipt = q:ReadAsync(1, true)
assert(items[1] == "normal" and receipt ~= _G.oldReceipt)
assert(q:RemoveAsync(receipt) and tonumber(q:GetSizeAsync()) == 0)
_G.previousStore = service:GetMap("players")
`,
		"memory_store_expiration",
	)
	if !ok {fmt.eprintln(err); delete(err); panic("memory store expiration failed")}
	engine_runtime.Environment_Set_Mode(&environment, .Client)
	ok, err = vm.Run(
		&script_vm,
		`
assert(not pcall(function() game:GetService("MemoryStoreService"):GetMap("players") end))
assert(not pcall(function() _G.previousStore:GetAsync("player") end))
`,
		"memory_store_client",
	)
	if !ok {fmt.eprintln(err); delete(err); panic("memory store client denial failed")}
	fmt.println("MEMORY_STORE_SMOKE_PASSED")
}
