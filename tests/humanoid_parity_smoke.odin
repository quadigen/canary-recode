package main

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

run_humanoid :: proc(script_vm: ^vm.VM, source, label: string) {
	ok, err := vm.Run(script_vm, source, label)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("humanoid parity regression failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)
	defer {
		vm.Close(&script_vm)
		engine_runtime.Environment_Destroy(&environment)
	}

	run_humanoid(
		&script_vm,
		`
local character = Instance.new("CharacterModel", workspace)
character.Name = "HumanoidParityCharacter"
local root = Instance.new("Part", character)
root.Name = "HumanoidRootPart"
root.Anchored = true
root.CFrame = CFrame.new(0, 5, 0)

local controller = Instance.new("CharacterController", character)
local stateMachine = Instance.new("StateMachine", controller)
Instance.new("MovementController", controller)
local humanoid = Instance.new("Humanoid", character)
-- A name-matched lookup would mistakenly cast this Folder to Humanoid.
local impostor = Instance.new("Folder", character)
impostor.Name = "Humanoid"
humanoid.Name = "RenamedHumanoid"

test = {
    humanoid = humanoid,
    stateMachine = stateMachine,
    character = character,
    moveResults = {},
    states = {},
    enabledEvents = {},
    healthEvents = {},
    diedCount = 0,
}

humanoid.Died:Connect(function() test.diedCount += 1 end)
humanoid.MoveToFinished:Connect(function(reached)
    table.insert(test.moveResults, reached)
end)
humanoid.HealthChanged:Connect(function(value)
    table.insert(test.healthEvents, value)
end)
humanoid.StateChanged:Connect(function(old, new)
    table.insert(test.states, old .. "->" .. new)
end)
humanoid.StateEnabledChanged:Connect(function(state, enabled)
    table.insert(test.enabledEvents, {state, enabled})
end)

assert(humanoid:GetState() == "Idle")
assert(humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping))
assert(humanoid:GetStateEnabled(Enum.HumanoidStateType.Running))
humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
assert(not humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping))
assert(controller.JumpEnabled == false)
humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
assert(humanoid:GetState() == "Idle", "disabled explicit transition")
assert(stateMachine:SetState("Jumping") == false, "disabled internal transition")
assert(#test.states == 0, "blocked transition emitted StateChanged")
humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
assert(controller.JumpEnabled == true)
humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
assert(humanoid:GetState() == "Jumping")
assert(stateMachine:GetState() == "Jumping")
assert(test.states[1] == "Idle->Jumping")
humanoid:ChangeState("Idle")
assert(humanoid:GetState() == "Idle")
assert(#test.enabledEvents == 2, "enabled changed should only fire for toggles")
assert(test.enabledEvents[1][1] == Enum.HumanoidStateType.Jumping)
assert(test.enabledEvents[1][2] == false)
assert(test.enabledEvents[2][2] == true)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
assert(#test.enabledEvents == 2, "duplicate enable emitted event")

humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
assert(stateMachine:SetState("Falling") == false, "internal Falling must map to Freefall")
assert(humanoid:GetState() == "Idle")
humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)
assert(stateMachine:SetState("Running") == false)
assert(stateMachine:SetState("Falling") == true)
assert(stateMachine:SetState("Idle") == true, "internal Idle must remain available")
humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true)

humanoid:MoveTo(Vector3.new(0, 5, 0))
`,
		"humanoid_parity_setup",
	)

	workspace := services.Ensure_Service(&environment.services, "Workspace")
	character := cast(^classes.CharacterModel)classes.Find_Child(workspace, "CharacterModel")
	assert(character != nil)
	controller := classes.CharacterController_From_Model(character)
	assert(controller != nil)
	humanoid: ^classes.Humanoid
	for child in character.children {
		if child != nil && !child.destroyed && classes.Is_A(child, "Humanoid") {
			humanoid = cast(^classes.Humanoid)child
			break
		}
	}
	assert(humanoid != nil)


	classes.Humanoid_Sync(humanoid, controller, script_vm.L, 1.0 / 60.0)
	classes.Humanoid_Sync(humanoid, controller, script_vm.L, 1.0 / 60.0)
	run_humanoid(
		&script_vm,
		`
assert(#test.moveResults == 1 and test.moveResults[1] == true, "MoveTo completion")
test.humanoid:MoveTo(Vector3.new(200, 5, 0))
`,
		"humanoid_parity_arrival",
	)


	for _ in 0 ..< 17 {
		classes.Humanoid_Sync(humanoid, controller, script_vm.L, 0.5)
	}
	run_humanoid(
		&script_vm,
		`
assert(#test.moveResults == 2 and test.moveResults[2] == false, "MoveTo timeout")
test.humanoid:MoveTo(Vector3.new(200, 5, 0))
test.humanoid:Move(Vector3.new(0, 0, 0))
`,
		"humanoid_parity_timeout",
	)
	classes.Humanoid_Sync(humanoid, controller, script_vm.L, 10.0)
	run_humanoid(
		&script_vm,
		`
assert(#test.moveResults == 2, "manual Move should cancel old MoveTo")
test.humanoid:TakeDamage(25)
assert(test.humanoid.Health == 75)
assert(test.healthEvents[#test.healthEvents] == 75)
test.humanoid.Health = 0
assert(test.humanoid:GetState() == "Dead", "death state after health setter")
assert(test.diedCount == 1, "Died should fire on Health reaching 0")
assert(test.healthEvents[#test.healthEvents] == 0)
test.humanoid.Health = 0
test.humanoid:TakeDamage(25)
assert(test.diedCount == 1, "Died fired again on zero health")
test.humanoid.Health = 50
test.humanoid:ChangeState("Idle")
assert(test.humanoid:GetState() == "Idle")
test.humanoid:TakeDamage(100)
assert(test.humanoid.Health == 0)
assert(test.diedCount == 2, "Died did not fire after revival")
test.character:Destroy()
`,
		"humanoid_parity_death",
	)

	fmt.println("HUMANOID_PARITY_SMOKE_PASSED")
}
