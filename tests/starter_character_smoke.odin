package main

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

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

	run_script(
		&script_vm,
		`
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
for _, name in ipairs({"CustomAnimateCount", "StarterServerCount", "StarterClientCount"}) do
    local marker = Instance.new("NumberValue", template)
    marker.Name = name
end

-- Standard attachment objects on custom character parts must be cloned.
local socket = Instance.new("Attachment", root)
socket.Name = "RootSocket"
socket.CFrame = CFrame.new(0, 2, 0)

-- Weld endpoints must reference the spawned clone, not the starter template.
local weld = Instance.new("WeldConstraint", template)
weld.Name = "BodyWeld"
weld.Part0 = root
weld.Part1 = body
weld.Enabled = false -- Reference remapping is independent of physics activation.

-- Existing scripts inside the custom StarterCharacter should be cloned.
local customScript = Instance.new("Script", template)
customScript.Name = "Animate"

local starterScripts = game:GetService("StarterPlayer"):FindFirstChild("StarterCharacterScripts")
assert(starterScripts, "StarterCharacterScripts container must exist")
local ignored = Instance.new("Script", starterScripts)
ignored.Name = "Animate" -- Should not override the custom character's Animate.
local serverScript = Instance.new("Script", starterScripts)
serverScript.Name = "OnCharacterServer"
local clientScript = Instance.new("LocalScript", starterScripts)
clientScript.Name = "OnCharacterClient"
local moduleScript = Instance.new("ModuleScript", starterScripts)
moduleScript.Name = "CharacterUtilities"
`,
	)


	starter := services.Ensure_Service(&env.services, "StarterPlayer")
	template := classes.Find_First_Child(starter, "StarterCharacter")
	starter_scripts := classes.Find_First_Child(starter, "StarterCharacterScripts")
	classes.Script_Set_Source(
		cast(^classes.Script)classes.Find_First_Child(template, "Animate"),
		"script.Parent.CustomAnimateCount.Value += 1",
	)
	classes.Script_Set_Source(
		cast(^classes.Script)classes.Find_First_Child(starter_scripts, "Animate"),
		"error('StarterCharacterScripts overrode custom Animate')",
	)
	classes.Script_Set_Source(
		cast(^classes.Script)classes.Find_First_Child(starter_scripts, "OnCharacterServer"),
		`local m=script.Parent:FindFirstChild("StarterServerCount"); if m then m.Value += 1 end`,
	)
	classes.LocalScript_Set_Source(
		cast(^classes.LocalScript)classes.Find_First_Child(starter_scripts, "OnCharacterClient"),
		`local m=script.Parent:FindFirstChild("StarterClientCount"); if m then m.Value += 1 end`,
	)
	classes.ModuleScript_Set_Source(
		cast(^classes.ModuleScript)classes.Find_First_Child(starter_scripts, "CharacterUtilities"),
		"return {loaded = true}",
	)

	_ = services.Ensure_Service(&env.services, "ScriptContext")
	players := cast(^services.Players)services.Ensure_Service(&env.services, "Players")
	players.local_player = services.Players_Add(players, script_vm.L, 1, "TestPlayer")
	run_script(
		&script_vm,
		`
local player = game:GetService("Players").LocalPlayer
local character = assert(game:GetService("CharacterService"):LoadCharacter(player), "character did not load")
assert(character.Name == player.Name and character.Parent == workspace)
assert(not character:FindFirstChild("CharacterCollider"))
local root, body = character.RootPart, character.Visuals.Body
assert(math.abs(root.Position.X) < 1)
assert(math.abs((body.Position - root.Position).Magnitude - 2) < 0.1)
assert(root.RootSocket and root.RootSocket:IsA("Attachment"))
assert(math.abs((root.RootSocket.WorldPosition - (root.Position + Vector3.new(0, 2, 0))).Magnitude) < 0.1)
assert(character.BodyWeld.Part0 == root and character.BodyWeld.Part1 == body)
assert(character.Animate:IsA("Script"))
assert(character.OnCharacterServer:IsA("Script"))
assert(character.OnCharacterClient:IsA("LocalScript"))
assert(character.CharacterUtilities:IsA("ModuleScript"))
assert(character.OnCharacterServer ~= game:GetService("StarterPlayer").StarterCharacterScripts.OnCharacterServer)
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(1, 0, 0)))
`,
	)
	for _ in 0 ..< 90 {
		engine_runtime.Environment_Update_Step(&env, &script_vm, 1.0 / 60.0)
	}
	run_script(
		&script_vm,
		`
local character = game:GetService("Players").LocalPlayer.Character
local root, body = character.RootPart, character.Visuals.Body
assert(root.Position.X > 10)
local offset = root.CFrame:PointToObjectSpace(body.Position)
assert((offset - Vector3.new(2, 0, 0)).Magnitude < 0.1)
assert(character.CustomAnimateCount.Value == 1, "custom StarterCharacter Script did not run once")
assert(character.StarterServerCount.Value == 1, "StarterCharacterScripts Script did not run once")
assert(character.StarterClientCount.Value == 1, "StarterCharacterScripts LocalScript did not run once")
`,
	)
	run_script(
		&script_vm,
		`
local template = game:GetService("StarterPlayer").StarterCharacter
assert(template.HumanoidRootPart.CFrame.Position.X == 30)
assert(template.Visuals.Body.CFrame.Position.X == 32)
local player = game:GetService("Players"):GetPlayers()[1]
local characters = game:GetService("CharacterService")
local original = player.Character
assert(characters:UnloadCharacter(player))
local replacement = assert(characters:LoadCharacter(player))
assert(replacement ~= original and replacement.Visuals.Body)
assert(replacement.RootPart.RootSocket and replacement.BodyWeld.Part0 == replacement.RootPart)
assert(replacement.BodyWeld.Part1 == replacement.Visuals.Body)
assert(replacement.OnCharacterServer and replacement.OnCharacterClient)
assert(replacement.CharacterUtilities and replacement.Animate)
assert(replacement.StarterServerCount.Value == 0)
template:Destroy()
assert(characters:UnloadCharacter(player))
local fallback = assert(characters:LoadCharacter(player))
assert(fallback:FindFirstChild("CharacterCollider"))
assert(fallback.OnCharacterServer and fallback.OnCharacterClient and fallback.CharacterUtilities)
assert(not fallback:FindFirstChild("CustomAnimateCount"))
`,
	)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&env)
	fmt.println("STARTER_CHARACTER_SMOKE_PASSED")
}
