package main

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
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
cloth = Instance.new("Cloth", workspace)
cloth.Attachment0 = pin
cloth.Size = Vector2.new(6, 4)

character = Instance.new("CharacterModel", workspace)
local root = Instance.new("Part", character)
root.Name = "HumanoidRootPart"
root.Anchored = false
root.CanCollide = false
root.Size = Vector3.new(2, 2, 1)
root.CFrame = CFrame.new(0, 1.6, 4)
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

	furthest := f32(0)
	for _ in 0 ..< 45 {
		services.CharacterMotor_Advance(motor, controller, physics, script_vm.L, dt)
		services.Physics_Step(physics, dt)
		for particle in cloth.particles {furthest = min(furthest, particle.position.z)}
	}
	assert(root.cframe.z < -2, "character did not cross the cloth plane")
	assert(furthest < -0.5, "the controller capsule crossed without pushing the cloth")
	assert(cloth.particles[classes.CLOTH_PIN].position == [3]f32{0, 5, 0})
	fmt.println("CLOTH_COLLISION_SMOKE_PASSED")
}
