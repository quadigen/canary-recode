package main
import packages "../src/engine/packages"
import profiling "../src/engine/profiling"
import runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"
import "core:time"
run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.RunInternal(v, source, "editor_animation_native")
	assert(ok, err)
}
main :: proc() {
	v := vm.New()
	env: runtime.Environment
	runtime.Environment_Init(&env, &v, nil, .Editor)
	defer {vm.Close(&v); runtime.Environment_Destroy(&env)}
	assert(packages.Load_Internal_Modules_From_Directory(&env.packages, os.args[1]))
	profiling.set_collection_enabled(true)
	run(
		&v,
		`
local UI=require("@internal/editor_ui")
local parent=UI.frame(UI.root(),UDim2.fromOffset(0,0),UDim2.fromOffset(500,500),UI.tokens.color.panel)
parent.Visible=false
_G.animProbe={parent=parent,checks={},switches={}}
for i=1,24 do local _,c=UI.checkbox(parent,"Hidden",nil,false,nil); table.insert(_G.animProbe.checks,c) end
for i=1,12 do local _,c=UI.switch(parent,UDim2.fromOffset(0,0),false,nil); table.insert(_G.animProbe.switches,c) end
for i=1,40 do UI.tooltip(UI.frame(parent,UDim2.fromOffset(0,0),UDim2.fromOffset(10,10),UI.tokens.color.panel),"Hidden") end
_G.animProbe.totals=function()
 local cpu,resumes,alloc=0,0,0
 for _,row in ipairs(game:GetService("ProfilerService"):GetScripts()) do
  if row.Name:find("Components/checkbox",1,true) or row.Name:find("Components/switch",1,true) or row.Name:find("Components/tooltip",1,true) or row.Name:find("animation_scheduler",1,true) then
   cpu+=row.CpuMs; resumes+=row.Resumes; alloc+=row.AllocatedBytes
  end
 end
 return {cpu,resumes,alloc}
end
`,
	)
	for _ in 0 ..< 5 {runtime.Environment_Update_Step(&env, &v, 1.0 / 60.0)}
	run(&v, `_G.animProbe.before=_G.animProbe.totals()`)
	start := time.tick_now()
	for _ in 0 ..< 240 {runtime.Environment_Update_Step(&env, &v, 1.0 / 60.0)}
	fmt.println("IDLE_WALL_MS", time.duration_milliseconds(time.tick_since(start)))
	run(
		&v,
		`
local p=_G.animProbe
local a=p.totals()
print("IDLE_DELTA",a[1]-p.before[1],a[2]-p.before[2],a[3]-p.before[3])
for _,c in ipairs(p.checks) do c:SetValue(true,true) end
for _,c in ipairs(p.switches) do c:SetValue(true,true) end
`,
	)
	for _ in 0 ..< 120 {runtime.Environment_Update_Step(&env, &v, 1.0 / 60.0)}
	run(
		&v,
		`
local p=_G.animProbe
for _,c in ipairs(p.checks) do assert(c:GetValue() and c.mark.Visible) end
for _,c in ipairs(p.switches) do assert(c:GetValue()) end
p.parent.Visible=true
p.checks[1]:SetValue(false,true)
p.switches[1]:SetValue(false,true)
`,
	)
	for _ in 0 ..< 120 {runtime.Environment_Update_Step(&env, &v, 1.0 / 60.0)}
	run(&v, `local p=_G.animProbe; assert(not p.checks[1].mark.Visible); p.parent:Destroy()`)
	for _ in 0 ..< 5 {runtime.Environment_Update_Step(&env, &v, 1.0 / 60.0)}
	run(
		&v,
		`assert(next(require("@internal/editor_ui").shared().tooltips)==nil,"stale tooltip registry")`,
	)
	fmt.println("NATIVE_ANIMATION_PROBE_PASSED")
}
