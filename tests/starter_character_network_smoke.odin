package main

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

run_chunk :: proc(v: ^vm.VM, source, label: string) {
	ok, error := vm.RunInternal(v, source, label)
	if !ok {
		fmt.eprintln(label, error)
		delete(error)
		panic("starter character network smoke failed")
	}
}

main :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)
	engine_runtime.Environment_Set_Mode(&server, .Server)
	engine_runtime.Environment_Set_Mode(&client, .Client)
	_ = services.Ensure_Service(&server.services, "ScriptContext")
	_ = services.Ensure_Service(&client.services, "ScriptContext")

	run_chunk(
		&server_vm,
		`
local floor = Instance.new("Part", workspace)
floor.Name = "Spawn"
floor.Anchored = true
floor.Size = Vector3.new(500, 2, 500)
floor.CFrame = CFrame.new(0, -1, 0)
local starter = game:GetService("StarterPlayer")
local custom = Instance.new("Model", starter)
custom.Name = "StarterCharacter"
local root = Instance.new("Part", custom)
root.Name = "HumanoidRootPart"
root.Size = Vector3.new(3, 5, 3)
root.Transparency = 1
root.CanCollide = false
local surface = Instance.new("MeshPart", custom)
surface.Name = "CustomBody"
surface.CanCollide = false
surface.Size = Vector3.new(3, 5, 3)
local att = Instance.new("Attachment", surface)
att.Name = "HatAttachment"
att.Position = Vector3.new(0, 2, 0)
local weld = Instance.new("WeldConstraint", custom)
weld.Name = "VisualWeld"
weld.Enabled = false
weld.Part0 = root
weld.Part1 = surface
for _, name in {"ServerMarker", "ClientMarker"} do
    local val = Instance.new("NumberValue", custom)
    val.Name = name
end
local sc = starter.StarterCharacterScripts
local ss = Instance.new("Script", sc)
ss.Name = "CharacterServer"
local cs = Instance.new("LocalScript", sc)
cs.Name = "CharacterClient"
`,
		"author starter character",
	)

	starter := services.Ensure_Service(&server.services, "StarterPlayer")
	sc := classes.Find_First_Child(starter, "StarterCharacterScripts")
	classes.Script_Set_Source(
		cast(^classes.Script)classes.Find_First_Child(sc, "CharacterServer"),
		`local m=script.Parent:FindFirstChild("ServerMarker"); if m then m.Value += 1 end`,
	)
	classes.LocalScript_Set_Source(
		cast(^classes.LocalScript)classes.Find_First_Child(sc, "CharacterClient"),
		`local m=script.Parent:FindFirstChild("ClientMarker"); if m then m.Value += 1 end`,
	)

	run_chunk(
		&server_vm,
		`assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39573))`,
		"start server",
	)
	run_chunk(
		&client_vm,
		`assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39573))`,
		"start client",
	)

	for _ in 0 ..< 360 {
		engine_runtime.Environment_Update_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Update_Step(&client, &client_vm, 1.0 / 60.0)
	}

	run_chunk(
		&server_vm,
		`
local player = game:GetService("Players"):GetPlayers()[1]
assert(player and player.Character, "joining player should auto-spawn custom StarterCharacter")
local c = player.Character
assert(c.CustomBody and c.CustomBody.HatAttachment, "custom mesh + Attachment missing")
assert(c.VisualWeld.Part0 == c.HumanoidRootPart and c.VisualWeld.Part1 == c.CustomBody, "weld refs not remapped on server")
assert(c.CharacterServer and c.CharacterClient, "StarterCharacterScripts not inserted")
assert(c.ServerMarker.Value == 1, "server character script didn't run once")
`,
		"server verification",
	)

	run_chunk(
		&client_vm,
		`
local player = game:GetService("Players").LocalPlayer
assert(player and player.Character, "custom character not replicated")
local c = player.Character
assert(c.CustomBody and c.CustomBody.HatAttachment, "custom mesh/attachment missing on client")
assert(c.VisualWeld and c.CharacterClient, "weld or character LocalScript missing on client")
assert(c.ClientMarker.Value == 1, "character LocalScript didn't run once on client")
`,
		"client verification",
	)

	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("STARTER_CHARACTER_NETWORK_SMOKE_PASSED")
}
