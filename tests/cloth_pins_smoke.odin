package main

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:math"

main :: proc() {
	script_vm := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm)
	defer {vm.Close(&script_vm); engine_runtime.Environment_Destroy(&env)}
	ok, err := vm.Run(&script_vm, `
group = Instance.new("Folder", workspace)
local rail = Instance.new("Part", group)
rail.Name = "Rail"
rail.Anchored = true
rail.CanCollide = false
rail.CFrame = CFrame.new(0, 10, 0)
left = Instance.new("Attachment", rail)
left.Name = "Left"
left.Position = Vector3.new(-3, 0, 0)
right = Instance.new("Attachment", rail)
right.Name = "Right"
right.Position = Vector3.new(3, 0, 0)
cloth = Instance.new("Cloth", group)
cloth.Name = "Fabric"
cloth.CanCollide = false
cloth.Attachment0 = left
cloth.Attachment1 = right
cloth.FoldCount = 2
cloth.FoldDepth = 0.4
assert(cloth:GetVertexCount() == 121)
assert(not pcall(function() cloth:PinVertex(0, left) end))
assert(not pcall(function() cloth:PinPoint(Vector2.new(2, 0), left) end))
assert(not pcall(function() cloth.FoldDepth = math.huge end))
`, "cloth_pins_setup")
	assert(ok, err)
	vm.GetGlobal(script_vm.L, "cloth")
	cloth := cast(^classes.Cloth)classes.Object_From_Argument(script_vm.L, -1)
	vm.Pop(script_vm.L)
	workspace := services.Ensure_Service(&env.services, "Workspace")
	physics := cast(^services.Physics)services.Ensure_Service(&env.services, "Physics")
	assert(classes.Cloth_Prepare_Surface(cloth, workspace))
	assert(abs(cloth.particles[1].position.z) > 0.1)
	for _ in 0..<60 {services.Physics_Step(physics, 1.0/60.0)}
	assert(abs(cloth.particles[1].position.z) > 0.1)
	for particle in cloth.particles {
		for v in particle.position {assert(!math.is_nan(v) && !math.is_inf(v))}
	}
	ok, err = vm.Run(&script_vm, `
cloth:ClearPins()
cloth:PinPoint(Vector2.new(0, 0), left)
cloth:PinPoint(Vector2.new(1, 0), right)
assert(cloth:GetPins()[1] == left)
assert(cloth:GetPins()[11] == right)
right.Position = Vector3.new(4, 0, 1)
`, "cloth_custom_pins")
	assert(ok, err)
	services.Physics_Step(physics, 1.0/60.0)
	assert(cloth.particles[0].position == [3]f32{-3, 10, 0})
	assert(cloth.particles[10].position == [3]f32{4, 10, 1})
	vm.GetGlobal(script_vm.L, "group")
	group := classes.Object_From_Argument(script_vm.L, -1)
	vm.Pop(script_vm.L)
	snapshot, write_err := serializer.Serialize(&env.classes, script_vm.L, group)
	assert(serializer.Error_Is_None(write_err), serializer.Error_String(write_err))
	defer delete(snapshot)
	restored, read_err := serializer.Deserialize(&env.classes, script_vm.L, nil, snapshot)
	assert(serializer.Error_Is_None(read_err), serializer.Error_String(read_err))
	restored_cloth := cast(^classes.Cloth)classes.Find_First_Child(restored, "Fabric")
	rail := classes.Find_First_Child(restored, "Rail")
	assert(restored_cloth.custom_pins && restored_cloth.fold_count == 2)
	assert(restored_cloth.pin_attachments[0] == classes.Find_First_Child(rail, "Left"))
	assert(restored_cloth.pin_attachments[10] == classes.Find_First_Child(rail, "Right"))
	ok, err = vm.Run(&script_vm, `
cloth:UnpinVertex(1)
assert(cloth:GetPins()[1] == nil)
right:Destroy()
assert(cloth:GetPins()[11] == nil)
`, "cloth_release")
	assert(ok, err)
	services.Physics_Step(physics, 1.0/60.0)
	assert(cloth.initialized && !cloth.pinned[0] && !cloth.pinned[10])
	fmt.println("CLOTH_PINS_SMOKE_PASSED")
}

