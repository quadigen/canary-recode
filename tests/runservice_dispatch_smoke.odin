package main

import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:time"

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.Run(v, source, "runservice_dispatch_smoke")
	assert(ok, err)
}

main :: proc() {
	v := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &v)
	defer {vm.Close(&v); engine_runtime.Environment_Destroy(&env)}
	service := cast(^services.RunService)services.Find_Service(&env.services, "RunService").object
	run(
		&v,
		`
local rs=game:GetService("RunService")
dispatchOrder=""
rs:BindToRenderStep("b",20,function() dispatchOrder ..= "B" end)
rs:BindToRenderStep("a",10,function()
    dispatchOrder ..= "A"
    rs:UnbindFromRenderStep("b")
    rs:BindToRenderStep("c",30,function() dispatchOrder ..= "C" end)
end)
local connection=rs.RenderStepped:Connect(function(dt) dispatchOrder ..= "S" end)
`,
	)
	top := vm.StackTop(v.L)
	services.Run_Service_Render_Step(service, v.L, 0.1)
	services.Run_Service_Render_Step(service, v.L, 0.2)
	assert(vm.StackTop(v.L) == top, "callback snapshot must restore stack")
	run(
		&v,
		`
assert(dispatchOrder=="ABSACS",dispatchOrder)
local rs=game:GetService("RunService")
rs:UnbindFromRenderStep("a")
rs:UnbindFromRenderStep("c")
largeCount=0
for i=1,300 do rs:BindToRenderStep("large"..i,i,function() largeCount+=1 end) end
`,
	)
	services.Run_Service_Render_Step(service, v.L, 0.1)
	assert(vm.StackTop(v.L) == top)
	run(
		&v,
		`
assert(largeCount==300)
local rs=game:GetService("RunService")
for i=1,300 do rs:UnbindFromRenderStep("large"..i) end
benchCount=0
for i=1,32 do rs:BindToRenderStep("bench"..i,i,function() benchCount+=1 end) end
`,
	)
	start := time.tick_now()
	for _ in 0 ..< 10000 {services.Run_Service_Render_Step(service, v.L, 1.0 / 144)}
	elapsed := time.duration_milliseconds(time.tick_since(start))
	assert(vm.StackTop(v.L) == top)
	run(&v, `assert(benchCount==320000)`)
	fmt.println("RUNSERVICE_DISPATCH_BENCH_MS", elapsed)
	ok, err := vm.RunInternal(
		&v,
		`
local s=Signal.new()
local total=0
local order=""
local b
s:Connect(function(x)
    order ..= "A"
    if b then b:Disconnect() end
    if x==1 then s:Fire(2) end
end)
b=s:Connect(function(x) order ..= "B"; total+=x end)
s:Once(function(x) order ..= "C"; total+=x*10 end)
s:Fire(1)
assert(order=="AABC",order)
assert(total==11,total)
local large=Signal.new()
local count=0
for i=1,300 do large:Connect(function(x) count+=x end) end
large:Fire(2)
assert(count==600,count)
local yielding=Signal.new()
local waited=nil
task.spawn(function() waited=yielding:Wait() end)
yielding:Fire(42)
assert(waited==42)
local calls=0
yielding:Connect(function(x) calls+=x; task.wait(); calls+=x end)
yielding:Fire(3)
assert(calls==3)
local profiler=game:GetService("ProfilerService")
local found=false
for _,row in profiler:GetScripts() do
    if string.find(row.Name,"signal_dispatch_snapshot",1,true) then
        assert(row.Resumes>=300)
        found=true
    end
end
assert(found,"signal callback source must be attributed")
`,
		"signal_dispatch_snapshot",
	)
	assert(ok, err)
	assert(vm.StackTop(v.L) == top)
	fmt.println("SIGNAL_DISPATCH_SNAPSHOT_SMOKE_PASSED")
	fmt.println("RUNSERVICE_DISPATCH_SMOKE_PASSED")
}
