package main

import "core:fmt"
import "core:time"

import assetstore "../src/engine/assetstore"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

TEST_ASSET_ONE_BYTES :: 4_199_108
TEST_ASSET_TWO_BYTES :: 1_750_032
TEST_ASSET_THREE_BYTES :: 6_500_000
TEST_INITIAL_REPLICATION_DEADLINE :: 25 * time.Second

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.RunInternal(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("initial replication smoke script failed")
	}
}

make_asset_bytes :: proc(count: int, seed: u8) -> []u8 {
	bytes := make([]u8, count)
	for i in 0 ..< count {bytes[i] = u8(i % 251) + seed}
	return bytes
}

main :: proc() {
	assetstore.Clear()
	defer assetstore.Clear()

	first_id := assetstore.Register(
		make_asset_bytes(TEST_ASSET_ONE_BYTES, 1),
		"meshes/initial-smoke-a.obj",
		.Mesh,
	)
	second_id := assetstore.Register(
		make_asset_bytes(TEST_ASSET_TWO_BYTES, 2),
		"meshes/initial-smoke-b.obj",
		.Mesh,
	)
	third_id := assetstore.Register(
		make_asset_bytes(TEST_ASSET_THREE_BYTES, 3),
		"meshes/initial-smoke-c.obj",
		.Mesh,
	)
	assert(first_id != "" && second_id != "" && third_id != "")
	defer delete(third_id)
	defer delete(first_id)
	defer delete(second_id)

	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm, nil, .Server)
	engine_runtime.Environment_Init(&client, &client_vm, nil, .Client)
	_ = services.Ensure_Service(&server.services, "ScriptContext")
	_ = services.Ensure_Service(&client.services, "ScriptContext")

	run_script(
		&server_vm,
		`local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", {"CanQuery"}))
local terrain = game:GetService("Terrain")
terrain:SetCells(Region3int16.new(Vector3int16.new(-50, -3, -50), Vector3int16.new(50, 3, 50)), Enum.Material.Grass)
local floor = Instance.new("Part", workspace)
floor.Size = Vector3.new(300, 1, 300)
floor.Position = Vector3.new(0, 16, 0)
floor.Anchored = true
local template = Instance.new("ScreenGui", game:GetService("ServerStorage"))
template.Name = "JoinHud"
local code = Instance.new("LocalScript", template)
code.Source = 'script.Parent:SetAttribute("JoinHudStarted", true)'
game:GetService("Players").PlayerAdded:Connect(function(player)
    template:Clone().Parent = player.PlayerGui
end)
assert(r:StartServer("127.0.0.1", 39847))`,
		"large_asset_server",
	)
	run_script(
		&client_vm,
		`local r = game:GetService("ReplicatorService")
assert(r:RegisterSchema("Part", {"CanQuery"}))
assert(r:ConnectClient("127.0.0.1", 39847))`,
		"large_asset_client",
	)

	server_rep := cast(^services.ReplicatorService)services.Find_Service(&server.services, "ReplicatorService").object
	client_rep := cast(^services.ReplicatorService)services.Find_Service(&client.services, "ReplicatorService").object
	assert(server_rep != nil && client_rep != nil)

	started := time.tick_now()
	for time.tick_since(started) < TEST_INITIAL_REPLICATION_DEADLINE {
		engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&client, &client_vm, 1.0 / 60.0)
		engine_runtime.Environment_Update_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Update_Step(&client, &client_vm, 1.0 / 60.0)
		if client_rep.asset_table_complete &&
		   client_rep.terrain_table_complete &&
		   client_rep.scene_ready &&
		   client_rep.replication_finished {break}
		time.sleep(3 * time.Millisecond)
	}
	elapsed := time.tick_since(started)
	fmt.printf(
		"Initial replication: %.2f s, sent %d assets, received %d bytes, rejected %d\n",
		f64(elapsed) / f64(time.Second),
		server_rep.assets_sent,
		client_rep.asset_bytes_received,
		client_rep.asset_rejections,
	)
	assert(client_rep.handshake_complete, "client handshake must finish")
	assert(
		client_rep.asset_table_complete,
		"large initial asset table must finish within deadline",
	)
	assert(server_rep.assets_sent == 3, "all synthetic assets must be sent")
	assert(client_rep.assets_received == 3, "client must receive all three assets")
	assert(
		client_rep.asset_bytes_received ==
		TEST_ASSET_ONE_BYTES + TEST_ASSET_TWO_BYTES + TEST_ASSET_THREE_BYTES,
	)
	assert(client_rep.asset_rejections == 0, "asset data must not be rejected")
	assert(client_rep.terrain_table_complete && client_rep.terrain_cells_received == 60000)
	assert(client_rep.terrain_rejections == 0)
	assert(client_rep.scene_ready && client_rep.replication_finished)
	for _ in 0 ..< 30 {
		engine_runtime.Environment_Update_Step(&client, &client_vm, 1.0 / 60.0)
	}
	run_script(
		&client_vm,
		`
local p = game:GetService("Players").LocalPlayer
assert(p and p.Character and p.Character:FindFirstChild("HumanoidRootPart"))
assert(p.PlayerGui:FindFirstChild("JoinHud"))
local hud = p.PlayerGui.JoinHud
local script = hud:FindFirstChildOfClass("LocalScript")
assert(script and #script.Source > 0, "GUI LocalScript source missing")
assert(hud:GetAttribute("JoinHudStarted") == true, "GUI LocalScript did not start")
`,
		"large_asset_client_ready",
	)
	fmt.println("INITIAL_REPLICATION_LARGE_ASSET_SMOKE_PASSED")
}
