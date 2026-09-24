package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("replication remote failed")
	}
}

step_network :: proc(environment: ^engine_runtime.Environment, script_vm: ^vm.VM) {
	descriptor := services.Find_Service(&environment.services, "ReplicatorService")
	services.Replication_Step(cast(^services.ReplicatorService)descriptor.object, script_vm.L, 1.0 / 60.0)
}

main :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)

	// ---- loopback tests (.Stopped mode, no network) -------------------------
	run_script(&server_vm, `
local re = Instance.new("RemoteEvent")
local fired = nil
re.OnServerEvent:Connect(function(player, arg)
    fired = { player, arg }
end)
re:FireServer("loop")
assert(fired ~= nil and fired[1] == nil and fired[2] == "loop")
local rf = Instance.new("RemoteFunction")
rf.OnServerInvoke = function(player, x) return x * 2, "extra" end
local a, b = rf:InvokeServer(21)
assert(a == 42 and b == "extra")
rf.OnServerInvoke = nil
local ok, err = rf:InvokeServer(21)
assert(ok == nil and type(err) == "string")
local rec = Instance.new("RemoteEvent")
local clientFired = nil
rec.OnClientEvent:Connect(function(arg)
    clientFired = arg
end)
rec:FireAllClients("toClient")
assert(clientFired == "toClient")
local wok = nil
coroutine.wrap(function() wok = rec.OnClientEvent:Wait() end)()
rec:FireAllClients("waitTest")
assert(wok == "waitTest", "wait got " .. tostring(wok))
re:Destroy()
rf:Destroy()
rec:Destroy()
`, "remote_loopback")

	// ---- server setup -------------------------------------------------------
	run_script(&server_vm, `
local r = game:GetService("ReplicatorService")
assert(r:StartServer("127.0.0.1", 39184))
local ping = Instance.new("RemoteEvent")
ping.Name = "Ping"
ping.Parent = game:GetService("ReplicatedStorage")
local dd = Instance.new("RemoteFunction")
dd.Name = "Double"
dd.OnServerInvoke = function(player, x) return x * 2 end
dd.Parent = game:GetService("ReplicatedStorage")
ping.OnServerEvent:Connect(function(player, msg, n)
    serverEventSeen = tostring(player.ClassName) .. ":" .. msg .. ":" .. tostring(n)
end)
`, "remote_server_setup")

	run_script(&client_vm, `
local r = game:GetService("ReplicatorService")
assert(r:ConnectClient("127.0.0.1", 39184))
`, "remote_client_setup")

	for _ in 0..<180 {
		engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&client, &client_vm, 1.0 / 60.0)
	}

	// ---- client hooks onto the replicated remotes ---------------------------
	run_script(&client_vm, `
local rs = game:GetService("ReplicatedStorage")
local ping = assert(rs:FindFirstChild("Ping"), "Ping not replicated")
local dd = assert(rs:FindFirstChild("Double"), "Double not replicated")
assert(ping.ClassName == "RemoteEvent")
assert(dd.ClassName == "RemoteFunction")
ping.OnClientEvent:Connect(function(msg)
    clientEventSeen = msg
end)
dd.OnClientInvoke = function(x) return x + 1 end
`, "remote_client_hooks")

	// ---- RemoteEvent: FireServer client -> server ----------------------------
	run_script(&client_vm, `
game:GetService("ReplicatedStorage"):FindFirstChild("Ping"):FireServer("hello", 42)
`, "remote_fire_server")
	for _ in 0..<3 {
		step_network(&client, &client_vm)
		step_network(&server, &server_vm)
	}
	run_script(&server_vm, `
assert(serverEventSeen == "Player:hello:42")
assert(game:GetService("Players"):GetPlayers()[1].UserId > 0)
`, "remote_fire_server_verify")

	// ---- RemoteEvent: FireClient server -> client (targeted) -----------------
	run_script(&server_vm, `
local ping = game:GetService("ReplicatedStorage"):FindFirstChild("Ping")
ping:FireClient(game:GetService("Players"):GetPlayers()[1], "world")
`, "remote_fire_client")
	for _ in 0..<3 {
		step_network(&server, &server_vm)
		step_network(&client, &client_vm)
	}
	run_script(&client_vm, `
assert(clientEventSeen == "world")
`, "remote_fire_client_verify")

	// ---- RemoteFunction: InvokeServer client -> server -----------------------
	run_script(&client_vm, `
coroutine.wrap(function()
    local a, b = game:GetService("ReplicatedStorage"):FindFirstChild("Double"):InvokeServer(5)
    received0 = { a, b }
    ok, err = a, b
end)()
`, "remote_invoke_server_start")
	for _ in 0..<3 {
		step_network(&client, &client_vm)
		step_network(&server, &server_vm)
		step_network(&client, &client_vm)
	}
	run_script(&client_vm, `
assert(received0 and received0[1] == 10, "received0=" .. tostring(received0 and received0[1]) .. " ok=" .. tostring(ok))
assert(ok == 10 and err == nil)
`, "remote_invoke_server_verify")

	// ---- RemoteFunction: no handler on the server ----------------------------
	run_script(&server_vm, `
game:GetService("ReplicatedStorage"):FindFirstChild("Double").OnServerInvoke = nil
`, "remote_invoke_server_clear")
	run_script(&client_vm, `
coroutine.wrap(function()
    ok, err = game:GetService("ReplicatedStorage"):FindFirstChild("Double"):InvokeServer(5)
end)()
`, "remote_invoke_server_nohandler_start")
	for _ in 0..<3 {
		step_network(&client, &client_vm)
		step_network(&server, &server_vm)
		step_network(&client, &client_vm)
	}
	run_script(&client_vm, `
assert(ok == nil, "expected nil, got " .. tostring(ok))
assert(type(err) == "string" and #err > 0)
`, "remote_invoke_server_nohandler_verify")

	// ---- RemoteFunction: InvokeClient server -> client -----------------------
	run_script(&server_vm, `
game:GetService("ReplicatedStorage"):FindFirstChild("Double").OnServerInvoke = function(player, x) return x * 2 end
coroutine.wrap(function()
    ok, err = game:GetService("ReplicatedStorage"):FindFirstChild("Double"):InvokeClient(game:GetService("Players"):GetPlayers()[1], 3)
end)()
`, "remote_invoke_client_start")
	for _ in 0..<3 {
		step_network(&server, &server_vm)
		step_network(&client, &client_vm)
		step_network(&server, &server_vm)
	}
run_script(&server_vm, `
local stats = game:GetService("ReplicatorService"):GetStats()
assert(ok == 4, "expected 4, got " .. tostring(ok))
assert(err == nil, tostring(err))
assert(stats.bytesReceived > 0, "bytes=" .. tostring(stats.bytesReceived))
assert(stats.malformedPackets == 0, "malformed=" .. tostring(stats.malformedPackets))
`, "remote_invoke_client_verify")
run_script(&client_vm, `
local stats = game:GetService("ReplicatorService"):GetStats()
assert(stats.bytesReceived > 0, "bytes=" .. tostring(stats.bytesReceived))
assert(stats.malformedPackets == 0, "malformed=" .. tostring(stats.malformedPackets))
`, "remote_client_packet_health")

	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "remote_client_stop")
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "remote_server_stop")

	vm.Close(&server_vm)
	vm.Close(&client_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&client)
	fmt.println("REPLICATION_REMOTE_SMOKE_PASSED")
}