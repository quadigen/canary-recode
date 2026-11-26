package main

import assetstore "../src/engine/assetstore"
import classes "../src/engine/classes"
import rt "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:time"

run :: proc(state: ^vm.VM, source, name: string) {
	ok, err := vm.RunInternal(state, source, name)
	assert(ok, err)
}

step :: proc(server, client: ^rt.Environment, sv, cv: ^vm.VM, frames: int) {
	for _ in 0 ..< frames {
		rt.Environment_Update_Step(server, sv, 1.0 / 60)
		rt.Environment_Update_Step(client, cv, 1.0 / 60)
		time.sleep(3 * time.Millisecond)
	}
}

main :: proc() {
	assetstore.Clear()
	defer assetstore.Clear()
	id := assetstore.Register(make([]u8, 3 * 1024 * 1024), "custom-character-join-data", .Data)
	assert(id != "")
	defer delete(id)

	sv, cv := vm.New(), vm.New()
	server, client: rt.Environment
	rt.Environment_Init(&server, &sv, nil, .Server)
	rt.Environment_Init(&client, &cv, nil, .Client)
	_ = services.Ensure_Service(&server.services, "ScriptContext")
	_ = services.Ensure_Service(&client.services, "ScriptContext")
	run(
		&sv,
		`
local floor = Instance.new("Part", workspace)
floor.Name = "Spawn"
floor.Size = Vector3.new(600, 2, 600)
floor.Position = Vector3.new(2000, -1, 1000)
floor.Anchored = true
local starter = game:GetService("StarterPlayer")
local template = Instance.new("Model", starter)
template.Name = "StarterCharacter"
local root = Instance.new("Part", template)
root.Name = "HumanoidRootPart"
root.CFrame = CFrame.new(0, 20, 0)
root.Size = Vector3.new(2, 5, 2)
root.Anchored = true
root.CanCollide = false
local body = Instance.new("MeshPart", template)
body.Name = "CustomBody"
body.CFrame = CFrame.new(0, 17.5, 0)
body.Anchored = true
body.CanCollide = false
local attachment = Instance.new("Attachment", body)
attachment.Name = "Grip"
local weld = Instance.new("WeldConstraint", template)
weld.Part0 = root
weld.Part1 = body
local cc = Instance.new("CharacterController", template)
cc.WalkSpeed = 12
game:GetService("CharacterService").NativeInputEnabled = false
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39577))
`,
		"custom_server",
	)
	run(
		&cv,
		`assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39577))`,
		"custom_client",
	)
	sr := cast(^services.ReplicatorService)services.Find_Service(&server.services, "ReplicatorService").object
	cr := cast(^services.ReplicatorService)services.Find_Service(&client.services, "ReplicatorService").object
	for _ in 0 ..< 600 {
		step(&server, &client, &sv, &cv, 1)
		if len(sr.peers) > 0 &&
		   sr.peers[0].player != nil &&
		   sr.peers[0].player.character != nil {break}
	}
	assert(len(sr.peers) == 1 && sr.peers[0].player.character != nil)
	assert(!cr.scene_ready && sr.owned_states_accepted == 0)
	root := classes.CharacterModel_Root(sr.peers[0].player.character)
	entity := sr.entity_by_id[root.network_id]
	assert(
		entity.last_accepted_position == root.position,
		"ownership validation was not initialized at the spawn",
	)
	run(
		&sv,
		`game:GetService("Players"):GetPlayers()[1].Character:MoveTo(Vector3.new(2050, 7, 1000))`,
		"plot_teleport",
	)
	started := time.tick_now()
	for !cr.replication_finished && time.tick_since(started) < 15 * time.Second {
		step(&server, &client, &sv, &cv, 1)
		if !sr.peers[0].scene_ready_sent {assert(sr.owned_states_accepted == 0, "character upload before readiness")}
	}
	assert(cr.scene_ready && cr.replication_finished)
	step(&server, &client, &sv, &cv, 120)
	check := `
local p = game:GetService("Players"):GetPlayers()[1]
local c = p.Character
assert(c and c.CustomBody.Grip)
assert(c.CharacterController.WalkSpeed == 12, tostring(c.CharacterController.WalkSpeed))
assert(c.WeldConstraint.Part0 == c.HumanoidRootPart and c.WeldConstraint.Part1 == c.CustomBody)
assert(math.abs(c.HumanoidRootPart.Position.Y - 2.5) < 1.0, "custom root fell: " .. tostring(c.HumanoidRootPart.Position))
assert((c.HumanoidRootPart.CFrame:PointToObjectSpace(c.CustomBody.Position) - Vector3.new(0,-2.5,0)).Magnitude < 0.05, "visual mesh lost its local pose")
`
	run(&sv, check, "server_ground")
	run(&cv, check, "client_ground")
	run(
		&cv,
		`
local c = game:GetService("Players").LocalPlayer.Character
assert(math.abs(c.RootPart.Position.X - 2050) < 2, "server plot teleport lost")
game:GetService("CharacterService").NativeInputEnabled = false
game:GetService("CharacterService"):SetMoveDirection(Vector3.new(1, 0, 0))
`,
		"client_move",
	)
	step(&server, &client, &sv, &cv, 180)
	run(
		&cv,
		`game:GetService("CharacterService"):SetMoveDirection(Vector3.new(0, 0, 0))`,
		"client_stop",
	)
	step(&server, &client, &sv, &cv, 120)
	run(&sv, check, "server_moved_ground")
	run(&cv, check, "client_moved_ground")
	client_players := cast(^services.Players)services.Find_Service(&client.services, "Players").object
	client_root := classes.CharacterModel_Root(client_players.local_player.character)
	fmt.printf(
		"custom character server=%v client=%v accepted=%d rejected=%d\n",
		root.position,
		client_root.position,
		sr.owned_states_accepted,
		sr.owned_states_rejected,
	)
	assert(root.position.x > 2060, "server did not receive client movement")
	assert(
		abs(root.position.x - client_root.position.x) < 1.0,
		"client and server disagree on root",
	)
	assert(sr.owned_states_accepted > 0)
	fmt.println("CUSTOM_CHARACTER_POSE_NETWORK_SMOKE_PASSED")
}
