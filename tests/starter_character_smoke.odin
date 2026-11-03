package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source: string) {
	ok, err := vm.Run(script_vm, source, "starter_character_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("starter character smoke failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm)
	engine_runtime.Environment_Set_Mode(&env, .Singleplayer)

	run_script(&script_vm, `
local floor = Instance.new("Part", workspace)
floor.Name = "Spawn"
floor.Anchored = true
floor.Size = Vector3.new(200, 2, 200)
floor.CFrame = CFrame.new(0, -1, 0)

local template = Instance.new("Model", game:GetService("StarterPlayer"))
template.Name = "StarterCharacter"
local root = Instance.new("Part", template)
root.Name = "HumanoidRootPart"
root.Size = Vector3.new(3, 5, 3)
root.CFrame = CFrame.new(30, 10, 20)
root.Transparency = 1
local visuals = Instance.new("Model", template)
visuals.Name = "Visuals"
local body = Instance.new("Part", visuals)
body.Name = "Body"
body.CFrame = CFrame.new(32, 10, 20)
`)
	players := cast(^services.Players)services.Ensure_Service(&env.services, "Players")
	players.local_player = services.Players_Add(players, script_vm.L, 1, "TestPlayer")
	run_script(&script_vm, `
local player = game:GetService("Players").LocalPlayer
local character = assert(game:GetService("CharacterService"):LoadCharacter(player), "character did not load")
assert(character.Name == player.Name and character.Parent == workspace)
assert(not character:FindFirstChild("CharacterCollider"))
local root, body = character.RootPart, character.Visuals.Body
assert(math.abs(root.Position.X) < 1)
assert(math.abs((body.Position - root.Position).Magnitude - 2) < 0.1)
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(1, 0, 0)))
`)
	for _ in 0..<90 {
		engine_runtime.Environment_Render_Step(&env, &script_vm, 1.0 / 60.0)
	}
	run_script(&script_vm, `
local character = game:GetService("Players").LocalPlayer.Character
local root, body = character.RootPart, character.Visuals.Body
assert(root.Position.X > 10)
local offset = root.CFrame:PointToObjectSpace(body.Position)
assert((offset - Vector3.new(2, 0, 0)).Magnitude < 0.1)
`)
	run_script(&script_vm, `
local template = game:GetService("StarterPlayer").StarterCharacter
assert(template.HumanoidRootPart.CFrame.Position.X == 30)
assert(template.Visuals.Body.CFrame.Position.X == 32)
local player = game:GetService("Players"):GetPlayers()[1]
local characters = game:GetService("CharacterService")
local original = player.Character
assert(characters:UnloadCharacter(player))
local replacement = assert(characters:LoadCharacter(player))
assert(replacement ~= original and replacement.Visuals.Body)
template:Destroy()
assert(characters:UnloadCharacter(player))
assert(characters:LoadCharacter(player):FindFirstChild("CharacterCollider"))
`)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&env)
	fmt.println("STARTER_CHARACTER_SMOKE_PASSED")
}
