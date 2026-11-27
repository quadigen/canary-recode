package main

import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

Peer :: struct {
	env:       engine_runtime.Environment,
	script_vm: vm.VM,
}

run_script :: proc(p: ^Peer, source, name: string) {
	ok, err := vm.Run(&p.script_vm, source, name)
	if !ok {fmt.eprintln(name, err); panic("unreliable remote smoke failed")}
}

rep :: proc(p: ^Peer) -> ^services.ReplicatorService {
	return(
		cast(^services.ReplicatorService)services.Ensure_Service(
			&p.env.services,
			"ReplicatorService",
		) \
	)
}

step :: proc(server, a, b: ^Peer, count: int) {
	for _ in 0 ..< count {
		peers := [?]^Peer{server, a, b}
		for p in peers {
			services.Replication_Step(rep(p), p.script_vm.L, 1.0 / 60.0)
		}
	}
}

main :: proc() {
	server, a, b: Peer
	peers := [?]^Peer{&server, &a, &b}
	for p in peers {
		p.script_vm = vm.New()
		engine_runtime.Environment_Init(&p.env, &p.script_vm)
	}
	run_script(
		&server,
		`
local loop = Instance.new("UnreliableRemoteEvent")
assert(loop:IsA("Instance") and not loop:IsA("RemoteEvent"))
local clone = loop:Clone()
assert(clone.ClassName == "UnreliableRemoteEvent")
clone:Destroy()
loop.OnServerEvent:Connect(function(player, v) assert(player == nil); localValue = v end)
loop:FireServer(123)
assert(localValue == 123)
loop:Destroy()
game:GetService("CharacterService").CharacterAutoLoads = false
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1",39363))
local rs = game:GetService("ReplicatedStorage")
local u = Instance.new("UnreliableRemoteEvent", rs)
u.Name = "Transient"
local r = Instance.new("RemoteEvent", rs)
r.Name = "Reliable"
receiveCount = 0
u.OnServerEvent:Connect(function(player, value, extra, last)
    assert(player:IsA("Player"))
    receiveCount += 1
    latestPlayer, latestValue = player, value
    if value == "input" then
        assert(extra.X == 2 and extra.Y == 3 and extra.Z == 4 and last == 9)
    end
end)
r.OnServerEvent:Connect(function(player, value) reliableValue = value end)
`,
		"server_setup",
	)
	for p in peers[1:] {run_script(p, `assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1",39363))`, "connect")}
	step(&server, &a, &b, 200)
	for p in peers[1:] {
		run_script(
			p,
			`
local rs = game:GetService("ReplicatedStorage")
assert(rs.Transient.ClassName == "UnreliableRemoteEvent")
assert(rs.Reliable.ClassName == "RemoteEvent")
seen = {}
rs.Transient.OnClientEvent:Connect(function(value) table.insert(seen, value) end)
`,
			"client_hook",
		)
	}
	run_script(
		&a,
		`
local rs = game:GetService("ReplicatedStorage")
rs.Transient:FireServer("input", Vector3.new(2,3,4), 9)
rs.Reliable:FireServer("reliable")
local ok, err = pcall(function() rs.Transient:FireServer(string.rep("x", 1000)) end)
assert(not ok and type(err) == "string" and string.find(err, "1000 bytes", 1, true))
local hugeArgs = table.create(257, true)
ok, err = pcall(function() rs.Transient:FireServer(table.unpack(hugeArgs)) end)
assert(not ok and type(err) == "string" and string.find(err, "256 arguments", 1, true))
`,
		"client_fire",
	)
	step(&server, &a, &b, 60)
	run_script(
		&server,
		`
assert(receiveCount == 1 and latestValue == "input" and reliableValue == "reliable")
local u = game:GetService("ReplicatedStorage").Transient
u:FireClient(latestPlayer, "target")
u:FireAllClients("broadcast")
local ok, err = pcall(function() u:FireAllClients(string.rep("x", 1000)) end)
assert(not ok and type(err) == "string" and string.find(err, "1000 bytes", 1, true))
`,
		"server_fire",
	)
	step(&server, &a, &b, 60)
	run_script(
		&a,
		`
local values = {}
for _, value in ipairs(seen) do values[value] = true end
assert(#seen == 2 and values.target and values.broadcast)
`,
		"target_verify",
	)
	run_script(&b, `assert(#seen == 1 and seen[1] == "broadcast")`, "broadcast_verify")
	assert(rep(&a).diag_kind_counts[services.Replication_Kind_Unreliable_Remote] == 1)
	assert(rep(&server).diag_kind_counts[services.Replication_Kind_Unreliable_Remote] == 3)
	for p in peers {assert(rep(p).malformed_packets == 0)}
	for p in peers[1:] {run_script(p, `game:GetService("ReplicatorService"):Stop()`, "stop_client")}
	run_script(&server, `game:GetService("ReplicatorService"):Stop()`, "stop_server")
	for p in peers {
		vm.Close(&p.script_vm)
		engine_runtime.Environment_Destroy(&p.env)
	}
	fmt.println("REPLICATION_UNRELIABLE_REMOTE_SMOKE_PASSED")
}
