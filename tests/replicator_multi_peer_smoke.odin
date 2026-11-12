package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("multi peer replication failed")
	}
}

main :: proc() {
	server_vm := vm.New()
	first_vm := vm.New()
	second_vm := vm.New()
	server: engine_runtime.Environment
	first: engine_runtime.Environment
	second: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm, nil, .Server)
	engine_runtime.Environment_Init(&first, &first_vm, nil, .Client)
	engine_runtime.Environment_Init(&second, &second_vm, nil, .Client)

	run_script(&server_vm, `
local r = game:GetService("ReplicatorService")
r.BandwidthBudget = 4096
r.RelevancyDistance = 512
joined = 0
left = 0
local starter = Instance.new("ScreenGui", game:GetService("StarterGui"))
starter.Name = "StarterHud"
local plotRemote = Instance.new("RemoteEvent", game:GetService("ReplicatedStorage"))
plotRemote.Name = "PlotRemote"
plotRemote.OnServerEvent:Connect(function(player, payload)
    if player.UserId == 1 then clientPayload = payload end
end)
local large = Instance.new("ModuleScript", game:GetService("ReplicatedStorage"))
large.Name = "LargeHudModule"
large.Source = "--[[" .. string.rep("large dependency ", 90000) .. "]]\nreturn 'ready'"
game:GetService("Players").PlayerAdded:Connect(function(player)
    joined += 1
    player:SetAttribute("Plot", "Plot" .. tostring(player.UserId))
    player:AddTag("PlotOwner")
    local hud = Instance.new("ScreenGui", player.PlayerGui)
    hud.Name = "PrivateHud" .. tostring(player.UserId)
    hud:SetAttribute("Owner", player.UserId)
    hud:AddTag("PrivateHud" .. tostring(player.UserId))
    local script = Instance.new("LocalScript", hud)
    script.Source = [[
        local player = game:GetService("Players").LocalPlayer
        assert(script.Parent.Name == "PrivateHud" .. tostring(player.UserId))
        assert(player:GetAttribute("Plot") == "Plot" .. tostring(player.UserId))
        assert(script.Parent:GetAttribute("Owner") == player.UserId)
        assert(require(game:GetService("ReplicatedStorage").LargeHudModule) == "ready")
        _G.privateHudText = script.Parent.Panel.Text
    ]]
    local label = Instance.new("TextLabel", hud)
    label.Name = "Panel"
    label.Text = "HUD for " .. tostring(player.UserId)
end)
game:GetService("Players").PlayerRemoving:Connect(function(player) left += 1 end)
assert(r:StartServer("127.0.0.1", 39184))
local common = Instance.new("Part")
common.Name = "Common"
common.Parent = game:GetService("Workspace")
workspace:SetAttribute("Mode", "Server")
common:SetAttribute("Enabled", false)
common:SetAttribute("Tint", Color3.new(0.25, 0.5, 0.75))
common:SetAttribute("Range", NumberRange.new(2, 6))
common:SetAttribute("Blob", string.rep("abcdef", 2500))
game:GetService("CollectionService"):AddTag(common, "CommonTag")
local emitter = Instance.new("ParticleEmitter", common)
emitter.Name = "Sparks"
emitter.Speed = NumberRange.new(2, 6)
emitter.Enabled = false
local farPart = Instance.new("Part")
farPart.Name = "FarPart"
farPart.Anchored = true
farPart.Position = Vector3.new(10000, 0, 0)
local farScript = Instance.new("LocalScript", farPart)
farScript.Source = "error('streamed out')"
farPart.Parent = game:GetService("Workspace")
local private = Instance.new("Part")
private.Name = "Private"
private.ReplicationMode = Enum.ReplicationMode.Manual
private:SetAttribute("Secret", "visible to the second peer")
private:AddTag("PrivateTag")
private.Parent = game:GetService("Workspace")
`, "multi_server_setup")

	run_script(&first_vm, `
local r = game:GetService("ReplicatorService")
assert(r:ConnectClient("127.0.0.1", 39184))
r:OnEvent("targeted", function(data) targeted = data end)
`, "multi_first_setup")

	for _ in 0..<100 {
		engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&first, &first_vm, 1.0 / 60.0)
	}

	run_script(&second_vm, `
local r = game:GetService("ReplicatorService")
assert(r:ConnectClient("127.0.0.1", 39184))
r:OnEvent("targeted", function(data) targeted = data end)
`, "multi_second_setup")

	for _ in 0..<100 {
		engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&first, &first_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&second, &second_vm, 1.0 / 60.0)
	}

	engine_runtime.Environment_Update_Step(&first, &first_vm, 1.0 / 60.0)
	engine_runtime.Environment_Update_Step(&second, &second_vm, 1.0 / 60.0)

	run_script(&first_vm, `
local player = game:GetService("Players").LocalPlayer
assert(player.UserId == 1)
assert(player:GetAttribute("Plot") == "Plot1" and player:HasTag("PlotOwner"))
assert(player.PlayerGui.PrivateHud1.Panel.Text == "HUD for 1" and _G.privateHudText == "HUD for 1")
assert(player.PlayerGui:FindFirstChild("PrivateHud2") == nil)
assert(#player.PlayerGui:GetChildren() == 2 and player.PlayerGui.StarterHud)
assert(game:GetService("Workspace"):FindFirstChild("Common"))
local collection = game:GetService("CollectionService")
local common = workspace.Common
game.ReplicatedStorage.PlotRemote.OnClientEvent:Connect(function(data)
    plotOwner = data.Plot.Owner
    plotPayload = data.Plot.Payload
    emptyPayload = data.Plot.Empty
end)
game.ReplicatedStorage.PlotRemote:FireServer(buffer.fromstring("build\0data"))
assert(workspace:GetAttribute("Mode") == "Server")
assert(common:GetAttribute("Enabled") == false)
assert(common:GetAttribute("Tint") == Color3.new(0.25, 0.5, 0.75))
assert(common:GetAttribute("Range").Max == 6)
assert(common:GetAttribute("Blob") == string.rep("abcdef", 2500))
assert(common:HasTag("CommonTag") and collection:GetTagged("CommonTag")[1] == common)
assert(#collection:GetTagged("PrivateHud2") == 0 and #collection:GetTagged("PrivateTag") == 0)
assert(game.Players.Player2:GetAttribute("Plot") == "Plot2" and game.Players.Player2:HasTag("PlotOwner"))
common:SetAttribute("ClientOnly", "local")
common:AddTag("ClientOnlyTag")
local sparks = workspace.Common.Sparks
assert(sparks:IsA("ParticleEmitter") and not sparks.Enabled)
assert(sparks.Speed.Min == 2 and sparks.Speed.Max == 6)
assert(game:GetService("Workspace"):FindFirstChild("FarPart") == nil)
assert(game:GetService("Workspace"):FindFirstChild("Private") == nil)
`, "multi_first_snapshot")

	run_script(&second_vm, `
local player = game:GetService("Players").LocalPlayer
assert(player.UserId == 2)
assert(player:GetAttribute("Plot") == "Plot2" and player:HasTag("PlotOwner"))
assert(game.Players.Player1:GetAttribute("Plot") == "Plot1")
assert(player.PlayerGui.PrivateHud2.Panel.Text == "HUD for 2" and _G.privateHudText == "HUD for 2")
assert(player.PlayerGui:FindFirstChild("PrivateHud1") == nil)
assert(#player.PlayerGui:GetChildren() == 2 and player.PlayerGui.StarterHud)
assert(game:GetService("Workspace"):FindFirstChild("Common"))
assert(game:GetService("Workspace"):FindFirstChild("Private") == nil)
`, "multi_second_snapshot")

	run_script(&server_vm, `
local players = game:GetService("Players"):GetPlayers()
assert(#players == 2)
assert(joined == 2)
assert(workspace.Common:GetAttribute("ClientOnly") == nil and not workspace.Common:HasTag("ClientOnlyTag"))
workspace.Common:SetAttribute("Enabled", true)
workspace.Common:SetAttribute("Blob", nil)
workspace.Common:RemoveTag("CommonTag")
workspace.Common:AddTag("UpdatedTag")
players[1]:SetAttribute("Plot", "Plot3")
players[1]:RemoveTag("PlotOwner")
workspace:SetAttribute("Mode", nil)
local r = game:GetService("ReplicatorService")
assert(r:SendEventTo(players[1], "targeted", "first"))
game.ReplicatedStorage.PlotRemote:FireClient(players[1], {
    Plot = {Owner = players[1], Payload = buffer.fromstring("placed\0block"), Empty = buffer.create(0)},
})
assert(r:ReplicateTo(game:GetService("Workspace"):FindFirstChild("Private"), players[2]))
local hitbox = Instance.new("Part", workspace)
hitbox.Name = "LaunchHitbox"
local weld = Instance.new("WeldConstraint", workspace.Common)
weld.Name = "LaunchWeld"
weld.Part0 = workspace.Common
weld.Part1 = hitbox
hitbox:Destroy()
`, "multi_target")

	// Launch workers can remove a hitbox before its weld's first snapshot.
	engine_runtime.Environment_Update_Step(&server, &server_vm, 1.0 / 60.0)

	for _ in 0..<45 {
		engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&first, &first_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&second, &second_vm, 1.0 / 60.0)
	}

	run_script(&server_vm, `
assert(typeof(clientPayload) == "buffer" and buffer.tostring(clientPayload) == "build\0data")
`, "multi_server_buffer_verify")

	run_script(&first_vm, `
assert(targeted == "first")
assert(game:GetService("Workspace"):FindFirstChild("Private") == nil)
local player = game.Players.LocalPlayer
assert(plotOwner == player and game.Players:GetPlayerByUserId(player.UserId) == player)
assert(typeof(plotPayload) == "buffer" and buffer.tostring(plotPayload) == "placed\0block")
assert(typeof(emptyPayload) == "buffer" and buffer.len(emptyPayload) == 0)
local collection = game:GetService("CollectionService")
assert(player:GetAttribute("Plot") == "Plot3" and not player:HasTag("PlotOwner"))
assert(workspace.Common:GetAttribute("Enabled") and workspace.Common:GetAttribute("Blob") == nil)
assert(workspace:GetAttribute("Mode") == nil)
assert(#collection:GetTagged("CommonTag") == 0 and #collection:GetTagged("PrivateTag") == 0)
assert(collection:GetTagged("UpdatedTag")[1] == workspace.Common)
assert(workspace.Common:GetAttribute("ClientOnly") == "local" and workspace.Common:HasTag("ClientOnlyTag"))
assert(workspace.Common.LaunchWeld.Part0 == workspace.Common)
assert(workspace.Common.LaunchWeld.Part1 == nil and not workspace:FindFirstChild("LaunchHitbox"))
game:GetService("ReplicatorService"):Stop()
`, "multi_first_verify")

	run_script(&second_vm, `
assert(targeted == nil)
assert(game:GetService("Workspace"):FindFirstChild("Private"))
assert(workspace.Private:GetAttribute("Secret") == "visible to the second peer")
assert(game:GetService("CollectionService"):GetTagged("PrivateTag")[1] == workspace.Private)
assert(game.Players.Player1:GetAttribute("Plot") == "Plot3" and not game.Players.Player1:HasTag("PlotOwner"))
assert(game.Players.LocalPlayer:GetAttribute("Plot") == "Plot2")
`, "multi_second_verify")

	// A playtest window can close while replication and its character are active.
	vm.Close(&second_vm)
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "multi_server_stop")
	run_script(&server_vm, `assert(left == 2)`, "multi_server_players_removed")
	vm.Close(&server_vm)
	vm.Close(&first_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&first)
	engine_runtime.Environment_Destroy(&second)
	fmt.println("REPLICATOR_MULTI_PEER_SMOKE_PASSED")
}
