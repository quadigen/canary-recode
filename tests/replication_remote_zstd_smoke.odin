package main

import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:time"

run_luau :: proc(state: ^vm.VM, script, name: string) {
	ok, err := vm.Run(state, script, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("remote Zstd regression failed")
	}
}

step_all :: proc(
	server, compressed, legacy: ^engine_runtime.Environment,
	server_vm, compressed_vm, legacy_vm: ^vm.VM,
) {
	engine_runtime.Environment_Render_Step(server, server_vm, 1.0 / 60.0)
	engine_runtime.Environment_Render_Step(compressed, compressed_vm, 1.0 / 60.0)
	engine_runtime.Environment_Render_Step(legacy, legacy_vm, 1.0 / 60.0)
	time.sleep(time.Millisecond)
}

main :: proc() {
	server_vm := vm.New()
	compressed_vm := vm.New()
	legacy_vm := vm.New()
	server: engine_runtime.Environment
	compressed: engine_runtime.Environment
	legacy: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm, nil, .Server)
	engine_runtime.Environment_Init(&compressed, &compressed_vm, nil, .Client)
	engine_runtime.Environment_Init(&legacy, &legacy_vm, nil, .Client)

	legacy_replicator := cast(^services.ReplicatorService)services.Find_Service(
		&legacy.services,
		"ReplicatorService",
	).object
	legacy_replicator.client_capabilities &~= services.Replication_Capability_Remote_Zstd

	run_luau(&server_vm, `
local replicator = game:GetService("ReplicatorService")
replicator.BandwidthBudget = 2097152
local remote = Instance.new("RemoteEvent", game:GetService("ReplicatedStorage"))
remote.Name = "ZstdTestEvent"
remote.OnServerEvent:Connect(function(player, label, content)
    if label == "compressed" then
        assert(player.UserId == 1 and #content == 700000 and content == string.rep("A", 700000))
        serverCompressed = true
    elseif label == "random" then
        assert(player.UserId == 1 and #content == 8192)
        serverRandom = true
    elseif label == "legacy" then
        assert(player.UserId == 2 and content == "legacy payload")
        serverLegacy = true
    elseif label == "small" then
        assert(player.UserId == 1 and content == "ok")
        serverSmall = true
    elseif label == "overflow" then
        serverOverflow = true
    end
end)
local fn = Instance.new("RemoteFunction", game:GetService("ReplicatedStorage"))
fn.Name = "ZstdTestFunction"
fn.OnServerInvoke = function(player, value)
    assert(player.UserId == 1 and value == string.rep("Q", 300000))
    serverFunctionLargeRequest = true
    return string.rep("F", 650000), "done"
end
assert(replicator:StartServer("127.0.0.1", 39208))
`, "zstd_server")

	run_luau(
		&compressed_vm,
		`assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39208))`,
		"zstd_connect",
	)
	for _ in 0 ..< 60 {step_all(&server, &compressed, &legacy, &server_vm, &compressed_vm, &legacy_vm)}
	run_luau(
		&legacy_vm,
		`assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39208))`,
		"zstd_legacy_connect",
	)
	for _ in 0 ..< 190 {step_all(&server, &compressed, &legacy, &server_vm, &compressed_vm, &legacy_vm)}

	run_luau(&compressed_vm, `
local event = assert(game.ReplicatedStorage:FindFirstChild("ZstdTestEvent"))
assert(game.Players.LocalPlayer.UserId == 1)
event.OnClientEvent:Connect(function(label, content)
    assert(label == "compressed" and #content == 650000 and content == string.rep("B", 650000))
    clientCompressed = true
end)
event:FireServer("small", "ok")
assert(game:GetService("ReplicatorService"):GetStats().remoteZstdSent == 0)
event:FireServer("compressed", string.rep("A", 700000))
assert(game:GetService("ReplicatorService"):GetStats().remoteZstdSent >= 1)
local bytes = {}
math.randomseed(72651)
for i = 1, 8192 do bytes[i] = string.char(math.random(0,255)) end
local sent = game:GetService("ReplicatorService"):GetStats().remoteZstdSent
event:FireServer("random", table.concat(bytes))
assert(game:GetService("ReplicatorService"):GetStats().remoteZstdSent == sent)
local ok, err = pcall(function() event:FireServer("overflow", string.rep("X", 900000)) end)
assert(not ok and type(err) == "string")
coroutine.wrap(function()
    local content, suffix = game.ReplicatedStorage.ZstdTestFunction:InvokeServer(string.rep("Q", 300000))
    clientFunction = content == string.rep("F", 650000) and suffix == "done"
end)()
`, "zstd_compressed_send")

	run_luau(&legacy_vm, `
local event = assert(game.ReplicatedStorage:FindFirstChild("ZstdTestEvent"))
assert(game.Players.LocalPlayer.UserId == 2)
event.OnClientEvent:Connect(function(label, content)
    assert(label == "legacy" and #content == 480000 and content == string.rep("L", 480000))
    legacyReceived = true
end)
event:FireServer("legacy", "legacy payload")
assert(game:GetService("ReplicatorService"):GetStats().remoteZstdSent == 0)
`, "zstd_legacy_send")

	for _ in 0 ..< 50 {step_all(&server, &compressed, &legacy, &server_vm, &compressed_vm, &legacy_vm)}
	run_luau(&server_vm, `
assert(serverCompressed and serverRandom and serverLegacy and serverSmall and serverFunctionLargeRequest and not serverOverflow)
local players = game.Players:GetPlayers()
assert(#players == 2)
local remote = game.ReplicatedStorage.ZstdTestEvent
remote:FireClient(players[1], "compressed", string.rep("B", 650000))
remote:FireClient(players[2], "legacy", string.rep("L", 480000))
local stats = game:GetService("ReplicatorService"):GetStats()
assert(stats.remoteZstdReceived >= 2)
assert(stats.remoteZstdSent >= 1)
assert(stats.remoteZstdBytesSaved > 600000)
print("REMOTE_ZSTD_SERVER", stats.remoteZstdSent, stats.remoteZstdReceived, stats.remoteZstdBytesSaved)
`, "zstd_server_send")
	for _ in 0 ..< 60 {step_all(&server, &compressed, &legacy, &server_vm, &compressed_vm, &legacy_vm)}
	run_luau(&compressed_vm, `
assert(clientCompressed and clientFunction)
local stats = game:GetService("ReplicatorService"):GetStats()
assert(stats.remoteZstdReceived >= 2)
assert(stats.remoteZstdBytesSaved > 600000)
print("REMOTE_ZSTD_CLIENT", stats.remoteZstdSent, stats.remoteZstdReceived, stats.remoteZstdBytesSaved)
`, "zstd_client_verify")
	run_luau(&legacy_vm, `
assert(legacyReceived)
assert(game:GetService("ReplicatorService"):GetStats().remoteZstdReceived == 0)
`, "zstd_legacy_verify")

	run_luau(&compressed_vm, `game:GetService("ReplicatorService"):Stop()`, "zstd_stop_compressed")
	run_luau(&legacy_vm, `game:GetService("ReplicatorService"):Stop()`, "zstd_stop_legacy")
	run_luau(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "zstd_stop_server")
	vm.Close(&server_vm)
	vm.Close(&compressed_vm)
	vm.Close(&legacy_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&compressed)
	engine_runtime.Environment_Destroy(&legacy)
	fmt.println("REPLICATION_REMOTE_ZSTD_PASSED")
}
