package main

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	script_vm := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm)
	defer {vm.Close(&script_vm); engine_runtime.Environment_Destroy(&env)}

	ok, err := vm.Run(&script_vm, `
local floor = Instance.new("Part", workspace)
floor.Anchored = true
floor.Size = Vector3.new(100, 1, 100)

local mount = Instance.new("Part", workspace)
mount.Anchored = true
mount.CanCollide = false
mount.CFrame = CFrame.new(0, 5, 0)
local pin = Instance.new("Attachment", mount)
pin.Name = "Left"
pin.Position = Vector3.new(-3, 0, 0)
local second = Instance.new("Attachment", mount)
second.Name = "Right"
second.Position = Vector3.new(3, 0, 0)
mount.Name = "CurtainMount"
cloth = Instance.new("Cloth", workspace)
cloth.Attachment0 = pin
cloth.Name = "Curtain"
cloth.Size = Vector2.new(12, 4)

character = Instance.new("CharacterModel", workspace)
local root = Instance.new("Part", character)
root.Name = "HumanoidRootPart"
root.Anchored = false
root.CanCollide = false
root.Size = Vector3.new(2, 2, 1)
root.CFrame = CFrame.new(0, 1.6, 4)

soft = Instance.new("SoftBody", workspace)
soft.MeshId = "src/engine/assets/shapes/Block.glb"
soft.CFrame = CFrame.new(0, 1.5, -4)
soft.GravityScale = 0
soft.ShapeRetention = 0.8
clothHits, softHits, rootClothHits, rootSoftHits = 0, 0, 0, 0
cloth.Touched:Connect(function(part)
	assert(part == root)
	clothHits += 1
end)
soft.Touched:Connect(function(part)
	assert(part == root)
	softHits += 1
end)
root.Touched:Connect(function(object)
	if object == cloth then rootClothHits += 1 end
	if object == soft then rootSoftHits += 1 end
end)
`, "cloth_collision_smoke")
	assert(ok, err)

	vm.GetGlobal(script_vm.L, "character")
	character := cast(^classes.CharacterModel)classes.Object_From_Argument(script_vm.L, -1)
	vm.Pop(script_vm.L)
	vm.GetGlobal(script_vm.L, "cloth")
	cloth := cast(^classes.Cloth)classes.Object_From_Argument(script_vm.L, -1)
	vm.Pop(script_vm.L)

	classes.CharacterController_Build(&env.classes, script_vm.L, character)
	controller := classes.CharacterController_From_Model(character)
	motor := cast(^classes.CharacterMotor)classes.Find_Child(&character.object, "CharacterMotor")
	movement := cast(^classes.MovementController)classes.CharacterController_Find(controller, "MovementController")
	root := classes.CharacterController_Root(controller)
	physics := cast(^services.Physics)services.Ensure_Service(&env.services, "Physics")
	collision := cast(^classes.CollisionController)classes.CharacterController_Find(controller, "CollisionController")
	defer services.Physics_Destroy_Character_Capsule(physics, collision)
	dt :: f32(1.0 / 60.0)
	movement.input_direction = {0, 0, -1}

	workspace := services.Ensure_Service(&env.services, "Workspace")
	assert(cloth.attachment1 == nil)
	assert(classes.Cloth_Prepare_Surface(cloth, workspace))
	assert(cloth.width == 6, "the curtain preview should take its width from both points")
	assert(cloth.particles[0].position == [3]f32{-3, 5, 0})
	assert(cloth.particles[classes.CLOTH_SEGMENTS].position == [3]f32{3, 5, 0})

	ok, err = vm.Run(&script_vm, `workspace.CurtainMount.Right.Position = Vector3.new(1, 0, 0)`, "move_preview_pin")
	assert(ok, err)
	assert(classes.Cloth_Prepare_Surface(cloth, workspace))
	assert(cloth.width == 4 && cloth.particles[classes.CLOTH_SEGMENTS].position == [3]f32{1, 5, 0})
	services.Physics_Step(physics, dt)
	assert(cloth.width == 4, "the solver must use the shorter span even if Size.X is larger")

	ok, err = vm.Run(&script_vm, `workspace.CurtainMount.Right.Position = Vector3.new(3, 0, 0)`, "move_simulated_pin")
	assert(ok, err)
	services.Physics_Step(physics, dt)
	assert(cloth.width == 6)
	assert(cloth.particles[0].position == [3]f32{-3, 5, 0})
	assert(cloth.particles[classes.CLOTH_SEGMENTS].position == [3]f32{3, 5, 0})

	furthest := f32(0)
	for _ in 0 ..< 55 {
		services.CharacterMotor_Advance(motor, controller, physics, script_vm.L, dt)
		services.Physics_Step(physics, dt)
		for particle in cloth.particles {furthest = min(furthest, particle.position.z)}
	}
	assert(root.cframe.z < -2, "character did not cross the cloth plane")
	assert(furthest < -0.1, fmt.tprintf("the controller capsule did not push the curtain, Z=%v", furthest))
	assert(cloth.particles[0].position == [3]f32{-3, 5, 0})
	assert(cloth.particles[classes.CLOTH_SEGMENTS].position == [3]f32{3, 5, 0})

	ok, err = vm.Run(&script_vm, `
assert(clothHits > 0 and clothHits == rootClothHits, "cloth contact didn't reach both objects")
assert(softHits > 0 and softHits == rootSoftHits, "soft body contact didn't reach both objects")
assert(soft:GetSimulationCFrame().Position.Z < -4.5, "the capsule did not push the soft body")
`, "deformable_touched")
	assert(ok, err)

	ok, err = vm.Run(&script_vm, `
workspace.SimulatePhysics = false
workspace.CurtainMount.Right.Position = Vector3.new(2, 0, 0)
`, "pause_and_move_pin")
	assert(ok, err)
	assert(classes.Cloth_Prepare_Surface(cloth, workspace))
	assert(cloth.width == 5 && cloth.particles[classes.CLOTH_SEGMENTS].position == [3]f32{2, 5, 0})

	ok, err = vm.Run(&script_vm, `
workspace.SimulatePhysics = true
second = workspace.CurtainMount.Right
second.Parent = nil
`, "detach_curtain_corner")
	assert(ok, err)
	services.Physics_Step(physics, dt)
	assert(cloth.particles[classes.CLOTH_PIN].position == [3]f32{-3, 5, 0})

	ok, err = vm.Run(&script_vm, `
local mount = workspace.CurtainMount
second.Parent = mount
cloth.Attachment1 = second
CurtainGroup = Instance.new("Folder")
mount.Parent = CurtainGroup
cloth.Parent = CurtainGroup
`, "group_curtain_for_save")
	assert(ok, err)
	vm.GetGlobal(script_vm.L, "CurtainGroup")
	group := classes.Object_From_Argument(script_vm.L, -1)
	vm.Pop(script_vm.L)
	snapshot, write_err := serializer.Serialize(&env.classes, script_vm.L, group)
	assert(serializer.Error_Is_None(write_err), serializer.Error_String(write_err))
	defer delete(snapshot)
	restored, read_err := serializer.Deserialize(&env.classes, script_vm.L, nil, snapshot)
	assert(serializer.Error_Is_None(read_err), serializer.Error_String(read_err))
	mount := classes.Find_First_Child(restored, "CurtainMount")
	curtain := cast(^classes.Cloth)classes.Find_First_Child(restored, "Curtain")
	assert(curtain != nil && mount != nil)
	assert(curtain.attachment == classes.Find_First_Child(mount, "Left"))
	assert(curtain.attachment1 == classes.Find_First_Child(mount, "Right"))
	fmt.println("CLOTH_COLLISION_SMOKE_PASSED")
}
