package main
import classes "../src/engine/classes"
import runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
run :: proc(script_vm: ^vm.VM, source: string) {
	ok, err := vm.Run(script_vm, source, "rewind_replay_luau_smoke")
	if !ok {fmt.eprintln(err); delete(err); panic("rewind/replay Luau fixture failed")}
}
main :: proc() {
	script_vm := vm.New()
	env: runtime.Environment
	runtime.Environment_Init(&env, &script_vm)
	defer {runtime.Environment_Destroy(&env); vm.Close(&script_vm)}
	repl := cast(^services.ReplicatorService)services.Ensure_Service(
		&env.services,
		"ReplicatorService",
	)
	world := cast(^services.Workspace)services.Ensure_Service(&env.services, "Workspace")
	repl.mode = .Server
	run(
		&script_vm,
		`
local p=Instance.new("Part",workspace)
p.Name="RewindTarget"
p.Anchored=true
p.Size=vector.create(2,2,2)
p.CanQuery=true
game:GetService("ReplicatorService"):Register(p)
assert(workspace:ConfigureRewind(0.5,30,16))
`,
	)
	ctx := classes.Class_Step_Context {
		L          = script_vm.L,
		delta_time = 0.1,
	}
	for tick in 0 ..= 3 {
		repl.clock = f32(tick) * 0.1
		run(&script_vm, fmt.tprintf(`workspace.RewindTarget.CFrame=CFrame.new(%d,0,0)`, tick))
		services.workspace_update(&world.object, &ctx)
	}
	run(
		&script_vm,
		`
local p=workspace.RewindTarget
local cf=workspace:GetHistoricalTransform(p,0.15)
assert(cf and math.abs(cf.Position.X-1.5)<0.001)
local hit=workspace:RaycastRewind(vector.create(-10,0,0),vector.create(30,0,0),0.15)
assert(hit and hit.Instance==p and math.abs(hit.Distance-10.5)<0.001)
assert(math.abs(p.CFrame.Position.X-3)<0.001)
assert(workspace:GetRewindStats().Entities>=1)
assert(workspace:GetRewindTime()>0)
local id=workspace:CreateInputReplay(vector.create(0,0,0),vector.create(0,0,0),4)
for i=1,6 do assert(workspace:PushReplayInput(id,i,0.1,vector.create(10,0,0))) end
assert(workspace:ReconcileInputReplay(id,1,vector.create(0,0,0),vector.create(0,0,0))==nil)
local pos,vel,tick=workspace:ReconcileInputReplay(id,4,vector.create(1,0,0),vector.create(4,0,0))
assert(math.abs(pos.X-2)<0.001 and math.abs(vel.X-6)<0.001 and tick==6)
workspace:DestroyInputReplay(id)
assert(not pcall(function()workspace:GetInputReplayState(id)end))
`,
	)
	repl.mode = .Client
	run(&script_vm, `assert(not pcall(function() workspace:ConfigureRewind(0.5,30,16) end))`)
	repl.mode = .Server
	vm.SetThreadActorPhase(script_vm.L, 1, true)
	run(
		&script_vm,
		`
assert(not pcall(function() workspace:GetRewindStats() end))
assert(not pcall(function() workspace:CreateInputReplay(vector.create(0,0,0),vector.create(0,0,0)) end))
`,
	)
	vm.SetThreadActorPhase(script_vm.L, 0, false)
	fmt.println("REPLICATION_REWIND_REPLAY_LUAU_SMOKE_PASSED")
}
