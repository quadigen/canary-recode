package main

import "core:fmt"
import classes "../src/engine/classes"
import datatypes "../src/engine/datatypes"
import services "../src/engine/services"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

STEP_DT :: f32(1.0 / 60.0)

make_part :: proc(
	registry: ^classes.Registry,
	script_vm: ^vm.VM,
	parent: ^classes.Object,
	name: string,
	size: datatypes.Vector3,
	position: datatypes.Vector3,
	anchored: bool,
) -> ^classes.Part {
	object, ok := classes.Push_New(registry, script_vm, "Part")
	assert(ok && object != nil)
	vm.Pop(script_vm.L)
	classes.Set_Name(object, name)
	part := cast(^classes.Part)object
	part.size = size
	part.cframe = datatypes.CFrame_New_XYZ(position.x, position.y, position.z)
	part.position = position
	part.anchored = anchored
	if parent != nil {
		classes.Set_Parent(object, parent)
	}
	return part
}

step_world :: proc(
	environment: ^engine_runtime.Environment,
	script_vm: ^vm.VM,
	motor: ^classes.CharacterMotor,
	controller: ^classes.CharacterController,
	physics: ^services.Physics,
	frames: int,
) {
	for _ in 0..<frames {
		services.CharacterMotor_Advance(motor, controller, physics, script_vm.L, STEP_DT)
		engine_runtime.Environment_Render_Step(environment, script_vm, STEP_DT)
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)
	registry := &environment.classes
	workspace := services.Ensure_Service(&environment.services, "Workspace")
	physics := cast(^services.Physics)services.Ensure_Service(&environment.services, "Physics")

	// Floor with its top face at y = 0.5.
	make_part(
		registry,
		&script_vm,
		workspace,
		"Floor",
		datatypes.Vector3{200, 1, 200},
		datatypes.Vector3{0, 0, 0},
		true,
	)

	// A crate resting on it at x = 8. Unanchored, so the solver owns it.
	crate := make_part(
		registry,
		&script_vm,
		workspace,
		"Crate",
		datatypes.Vector3{2, 2, 2},
		datatypes.Vector3{8, 1.5, 0},
		false,
	)

	// The character. The root part is sized so its capsule is 2 studs tall and
	// stands on the floor at y = 1.5, and it starts at x = -8 walking towards
	// +X, i.e. straight at the crate.
	model_object, model_ok := classes.Push_New(registry, &script_vm, "CharacterModel")
	assert(model_ok && model_object != nil)
	vm.Pop(script_vm.L)
	classes.Set_Name(model_object, "TestCharacter")
	model := cast(^classes.CharacterModel)model_object
	root := make_part(
		registry,
		&script_vm,
		model_object,
		"HumanoidRootPart",
		datatypes.Vector3{2, 2, 1},
		datatypes.Vector3{-8, 1.5, 0},
		false,
	)
	classes.Set_Parent(model_object, workspace)
	classes.CharacterController_Build(registry, script_vm.L, model)

	controller := classes.CharacterController_From_Model(model)
	assert(controller != nil, "CharacterController_Build must install a controller")
	motor := cast(^classes.CharacterMotor)classes.Find_Child(model_object, "CharacterMotor")
	assert(motor != nil, "CharacterController_Build must install a CharacterMotor")
	movement := cast(^classes.MovementController)classes.CharacterController_Find(
		controller,
		"MovementController",
	)
	assert(movement != nil, "CharacterController_Build must install a MovementController")
	movement.input_direction = datatypes.Vector3{1, 0, 0}

	// Settle onto the floor first, and confirm the crate is actually standing on
	// it before asking the character to shove it.
	step_world(&environment, &script_vm, motor, controller, physics, 20)
	fmt.println("settled crate y:", crate.cframe.y, "character y:", root.cframe.y)
	assert(abs(crate.cframe.y - 1.5) < 0.2, "crate must rest on the floor")
	assert(abs(root.cframe.y - 1.5) < 0.3, "character must settle onto the floor")
	crate_start := crate.cframe.x

	// Walk into the crate long enough to cover the gap and push it along.
	step_world(&environment, &script_vm, motor, controller, physics, 180)

	pushed := crate.cframe.x - crate_start
	travelled := root.cframe.x + 8
	fmt.println("crate push:", pushed, "character travel:", travelled, "crate x:", crate.cframe.x, "crate y:", crate.cframe.y)

	// The character has to have got there in the first place.
	assert(travelled > 12, "character never reached the crate")
	// And the crate has to have moved. Before the fix this stayed at exactly
	// crate_start: the kinematic capsule read as a wall.
	assert(pushed > 0.5, "character did not push the crate")
	// It should still be sitting on the floor rather than launched or sunk.
	assert(crate.cframe.y > 0.9 && crate.cframe.y < 2.5, "crate left the floor")

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("CHARACTER_PUSH_SMOKE_PASSED")
}