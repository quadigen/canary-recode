package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_character_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("character replication smoke failed")
	}
}

character_step :: proc(server: ^engine_runtime.Environment, server_vm: ^vm.VM, first: ^engine_runtime.Environment, first_vm: ^vm.VM, second: ^engine_runtime.Environment, second_vm: ^vm.VM, frames: int) {
	for _ in 0..<frames {
		engine_runtime.Environment_Render_Step(server, server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(first, first_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(second, second_vm, 1.0 / 60.0)
	}
}

main :: proc() {
	server_vm := vm.New()
	first_vm := vm.New()
	second_vm := vm.New()
	server: engine_runtime.Environment
	first: engine_runtime.Environment
	second: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&first, &first_vm)
	engine_runtime.Environment_Init(&second, &second_vm)
	run_character_script(&server_vm, `
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39185))
assert(IsServer and not IsClient)
`, "character_server_start")
	run_character_script(&first_vm, `
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39185))
assert(IsClient and not IsServer)
`, "character_first_start")
	run_character_script(&second_vm, `
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39185))
assert(IsClient and not IsServer)
`, "character_second_start")
	character_step(&server, &server_vm, &first, &first_vm, &second, &second_vm, 180)
	run_character_script(&server_vm, `
local players = game:GetService("Players"):GetPlayers()
assert(#players == 2)
for _, player in ipairs(players) do
    assert(player.Character and player.Character.ClassName == "CharacterModel")
    assert(player.Character.OwnerUserId == player.UserId)
    assert(player.Character.RootPart.Name == "HumanoidRootPart")
    assert(player.Character:FindFirstChild("Head"))
    assert(game:GetService("CharacterService"):GetCharacter(player) == player.Character)
end
`, "character_server_spawn")
	run_character_script(&first_vm, `
local players = game:GetService("Players")
assert(#players:GetPlayers() == 2)
assert(players.LocalPlayer.Character and players.LocalPlayer.Character.RootPart)
assert(players.LocalPlayer.Character.OwnerUserId == players.LocalPlayer.UserId)
assert(workspace.CurrentCamera.CameraSubject == players.LocalPlayer.Character)
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(1, 0, 0)))
assert(game:GetService("CharacterService"):Jump())
`, "character_first_spawn")
	run_character_script(&second_vm, `
local players = game:GetService("Players")
assert(#players:GetPlayers() == 2)
assert(players.LocalPlayer.Character and players.LocalPlayer.Character.RootPart)
added = 0
removed = 0
players.LocalPlayer.CharacterAdded:Connect(function() added += 1 end)
players.LocalPlayer.CharacterRemoving:Connect(function() removed += 1 end)
`, "character_second_spawn")
	character_step(&server, &server_vm, &first, &first_vm, &second, &second_vm, 1)
	run_character_script(&first_vm, `
assert(game:GetService("Players").LocalPlayer.Character.RootPart.CFrame.Position.X > 0)
`, "character_client_prediction")
	character_step(&server, &server_vm, &first, &first_vm, &second, &second_vm, 11)
	run_character_script(&server_vm, `
assert(game:GetService("Players"):GetPlayers()[1].Character.RootPart.CFrame.Position.Y > 5)
`, "character_server_jump")
	character_step(&server, &server_vm, &first, &first_vm, &second, &second_vm, 108)
	run_character_script(&server_vm, `
local player = game:GetService("Players"):GetPlayers()[1]
assert(player.Character.RootPart.CFrame.Position.X > 10)
assert(player.Character:FindFirstChild("Head").CFrame.Position.X > 10)
`, "character_server_move")
	run_character_script(&first_vm, `
local x = game:GetService("Players").LocalPlayer.Character.RootPart.CFrame.Position.X
local root = game:GetService("Players").LocalPlayer.Character.RootPart
assert(x > 10, "client x=" .. tostring(x) .. " packets=" .. tostring(game:GetService("ReplicatorService"):GetStats().packetsReceived) .. " malformed=" .. tostring(game:GetService("ReplicatorService"):GetStats().malformedPackets) .. " rootid=" .. tostring(root.NetworkId) .. " parent=" .. tostring(root.Parent.ClassName))
assert(game:GetService("CharacterService"):SetMoveDirection(Vector3.new(0, 0, 0)))
`, "character_first_move")
	run_character_script(&second_vm, `
local localId = game:GetService("Players").LocalPlayer.UserId
for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
    if player.UserId ~= localId then assert(player.Character.RootPart.CFrame.Position.X > 10) end
end
`, "character_second_observe")
	run_character_script(&first_vm, `
local character = game:GetService("Players").LocalPlayer.Character
for _, part in ipairs(character:GetChildren()) do
    if part:IsA("Part") then
        local position = part.CFrame.Position
        part.CFrame = CFrame.new(position.X + 1000, position.Y, position.Z)
    end
end
`, "character_client_prediction_error")
	character_step(&server, &server_vm, &first, &first_vm, &second, &second_vm, 60)
	run_character_script(&first_vm, `
local character = game:GetService("Players").LocalPlayer.Character
assert(character.RootPart.CFrame.Position.X < 100)
assert(character:FindFirstChild("Head").CFrame.Position.X < 100)
`, "character_client_reconciled")
	run_character_script(&server_vm, `
local player = game:GetService("Players"):GetPlayers()[2]
assert(game:GetService("CharacterService"):UnloadPlayer(player))
`, "character_server_unload")
	character_step(&server, &server_vm, &first, &first_vm, &second, &second_vm, 45)
	run_character_script(&second_vm, `
assert(game:GetService("Players").LocalPlayer.Character == nil)
assert(removed == 1)
`, "character_second_unloaded")
	run_character_script(&server_vm, `
local player = game:GetService("Players"):GetPlayers()[2]
assert(player:LoadCharacter())
`, "character_server_reload")
	character_step(&server, &server_vm, &first, &first_vm, &second, &second_vm, 75)
	run_character_script(&second_vm, `
assert(game:GetService("Players").LocalPlayer.Character ~= nil)
assert(added == 1)
`, "character_second_reloaded")
	run_character_script(&first_vm, `
game:GetService("ReplicatorService"):Stop()
assert(not IsClient and IsEditor)
`, "character_first_stop")
	character_step(&server, &server_vm, &first, &first_vm, &second, &second_vm, 90)
	run_character_script(&second_vm, `
local players = game:GetService("Players"):GetPlayers()
assert(#players == 1, "players=" .. tostring(#players))
assert(game:GetService("Players").LocalPlayer.Character ~= nil)
`, "character_second_disconnect")
	run_character_script(&second_vm, `game:GetService("ReplicatorService"):Stop()`, "character_second_stop")
	run_character_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "character_server_stop")
	vm.Close(&second_vm)
	vm.Close(&first_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&second)
	engine_runtime.Environment_Destroy(&first)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("CHARACTER_REPLICATION_SMOKE_PASSED")
}
