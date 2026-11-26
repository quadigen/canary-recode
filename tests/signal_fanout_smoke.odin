package main

import signals "../src/engine/signals"
import vm "../src/engine/vm"
import "core:fmt"
import "core:time"

count_callback :: proc "c" (ctx: rawptr, L: ^vm.State) -> i32 {
	counter := cast(^int)ctx
	counter^ += 1
	return 0
}

main :: proc() {
	v := vm.New()
	registry: signals.Registry
	signals.Registry_Init(&registry)
	signals.Install(&registry, &v)
	defer {vm.Close(&v); signals.Registry_Destroy(&registry)}
	top := vm.StackTop(v.L)
	ok, err := vm.RunInternal(
		&v,
		`
local s=Signal.new()
local order=""
local b
s:Connect(function(x)
    order ..= "A"
    if x==1 then b:Disconnect(); s:Fire(2) end
end)
b=s:Connect(function() order ..= "B" end)
local once=s:Once(function() order ..= "C" end)
s:Fire(1)
assert(order=="AABC",order)
assert(not once.Connected and not b.Connected)
local large=Signal.new()
local total=0
for i=1,300 do
    if i%2==0 then large:Once(function(x) total+=x end)
    else large:Connect(function(x) total+=x end) end
end
large:Fire(2)
assert(total==600)
large:Fire(3)
assert(total==1050)
large:DisconnectAll()
large:Fire(100)
assert(total==1050)
`,
		"signal_fanout_smoke",
	)
	assert(ok, err)
	assert(vm.StackTop(v.L) == top)
	for sample in 0 ..< 5 {
		s := signals.Create(&registry)
		count: int
		connections := make([]^signals.KinemiumConnection, 16000)
		for i in 0 ..< len(connections) {
			connections[i] = signals.Connect_Native(s, count_callback, &count, i % 2 == 0)
		}
		start := time.tick_now()
		signals.Fire(v.L, s)
		elapsed := time.duration_milliseconds(time.tick_since(start))
		assert(count == 16000)
		assert(len(s.listeners) == 8000)
		for i in 0 ..< len(connections) {assert(signals.Connection_Connected(connections[i]) == (i % 2 != 0))}
		signals.Fire(v.L, s)
		assert(count == 24000)
		assert(vm.StackTop(v.L) == top)
		fmt.println("SIGNAL_FANOUT_MS", sample, elapsed)
		signals.Destroy(s)
		for c in connections {free(c)}
		delete(connections)
	}
	fmt.println("SIGNAL_FANOUT_SMOKE_PASSED")
}
