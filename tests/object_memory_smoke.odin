package main

import classes "../src/engine/classes"
import runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	script_vm := vm.New()
	environment: runtime.Environment
	runtime.Environment_Init(&environment, &script_vm)
	defer runtime.Environment_Destroy(&environment)
	defer vm.Close(&script_vm)


	object := classes.Object_Init()
	classes.Set_Name(&object, "probe")
	classes.Object_Fire_Property_Changed(&object, "Name")
	assert(object.event_state == nil)
	classes.Object_Destroy(&object)

	source := `
local p = Instance.new("Folder")
local c = Instance.new("Folder")
local names, attrs, added, removed, destroying = 0, 0, 0, 0, 0
p:GetPropertyChangedSignal("Name"):Connect(function() names += 1 end)
p:GetAttributeChangedSignal("Probe"):Connect(function() attrs += 1 end)
p.ChildAdded:Connect(function(child) assert(child == c); added += 1 end)
p.ChildRemoved:Connect(function(child) assert(child == c); removed += 1 end)
p.Destroying:Connect(function() destroying += 1 end)
p.Name = "Changed"
p:SetAttribute("Probe", 1)
p:SetAttribute("Probe", nil)
c.Parent = p
c.Parent = nil
assert(names == 1 and attrs == 2 and added == 1 and removed == 1)
p:Destroy()
assert(destroying == 1)
c:Destroy()

order = {}
task.delay(0.1, function() table.insert(order, "delay") end)
task.defer(function()
    table.insert(order, "defer")
    task.defer(function() table.insert(order, "nested") end)
end)
task.spawn(function()
    task.wait(0.1)
    table.insert(order, "wait")
end)
`
	ok, err := vm.Run(&script_vm, source, "object_memory_smoke")
	if !ok {fmt.eprintln(err); delete(err); panic("setup failed")}
	scheduler := cast(^services.TaskScheduler)services.Ensure_Service(
		&environment.services,
		"TaskScheduler",
	)
	for _ in 0 ..< 8 {services.Task_Scheduler_Step(scheduler, 0.05)}
	ok, err = vm.Run(
		&script_vm,
		`assert(#order == 4 and order[1] == "delay" and order[2] == "defer" and order[3] == "wait" and order[4] == "nested", table.concat(order, ","))`,
		"object_memory_order",
	)
	if !ok {fmt.eprintln(err); delete(err); panic("scheduler failed")}
	assert(len(scheduler.tasks) == 0)
	fmt.println("OBJECT_MEMORY_SMOKE_PASSED")
}
