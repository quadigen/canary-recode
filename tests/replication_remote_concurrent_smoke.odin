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
		panic("concurrent remote regression failed")
	}
}

step_all :: proc(server, a, b: ^engine_runtime.Environment, server_vm, a_vm, b_vm: ^vm.VM) {
	engine_runtime.Environment_Render_Step(server, server_vm, 1.0 / 60.0)
	engine_runtime.Environment_Render_Step(a, a_vm, 1.0 / 60.0)
	engine_runtime.Environment_Render_Step(b, b_vm, 1.0 / 60.0)
	time.sleep(time.Millisecond)
}

main :: proc() {
	server_vm := vm.New()
	a_vm := vm.New()
	b_vm := vm.New()
	server: engine_runtime.Environment
	a: engine_runtime.Environment
	b: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm, nil, .Server)
	engine_runtime.Environment_Init(&a, &a_vm, nil, .Client)
	engine_runtime.Environment_Init(&b, &b_vm, nil, .Client)

	run_luau(&server_vm, `
local remote = Instance.new("RemoteFunction", game:GetService("ReplicatedStorage"))
remote.Name = "ConcurrentPing"
remote.OnServerInvoke = function(player, value)
    return "pong:" .. tostring(player.UserId) .. ":" .. tostring(value)
end
local spawn = Instance.new("SpawnLocation", workspace)
spawn.Name = "ConcurrentSpawn"
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39207))
`, "concurrent_server")

	run_luau(&a_vm, `assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39207))`, "concurrent_client_a")
	run_luau(&b_vm, `assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39207))`, "concurrent_client_b")

	for _ in 0..<160 {step_all(&server, &a, &b, &server_vm, &a_vm, &b_vm)}

	invocations := `
local remote = assert(game:GetService("ReplicatedStorage"):FindFirstChild("ConcurrentPing"))
assert(workspace:FindFirstChild("ConcurrentSpawn"))
local userId = game:GetService("Players").LocalPlayer.UserId
finished = 0
failures = {}
for i = 1, 160 do
    coroutine.wrap(function()
        local response = remote:InvokeServer(i)
        if response == "pong:" .. tostring(userId) .. ":" .. tostring(i) then
            finished += 1
        else
            table.insert(failures, "invocation " .. i .. ": " .. tostring(response))
        end
    end)()
end
`
	run_luau(&a_vm, invocations, "concurrent_a_start")
	run_luau(&b_vm, invocations, "concurrent_b_start")
	for _ in 0..<140 {step_all(&server, &a, &b, &server_vm, &a_vm, &b_vm)}
	run_luau(&a_vm, `assert(finished == 160 and #failures == 0, "a completed " .. finished .. " with " .. #failures .. " failures: " .. tostring(failures[1]))`, "concurrent_a_verify")
	run_luau(&b_vm, `assert(finished == 160 and #failures == 0, "b completed " .. finished .. " with " .. #failures .. " failures: " .. tostring(failures[1]))`, "concurrent_b_verify")

	run_luau(&a_vm, `game:GetService("ReplicatorService"):Stop()`, "concurrent_a_stop")
	run_luau(&b_vm, `game:GetService("ReplicatorService"):Stop()`, "concurrent_b_stop")
	run_luau(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "concurrent_server_stop")
	vm.Close(&server_vm)
	vm.Close(&a_vm)
	vm.Close(&b_vm)
	engine_runtime.Environment_Destroy(&server)
	engine_runtime.Environment_Destroy(&a)
	engine_runtime.Environment_Destroy(&b)
	fmt.println("REPLICATION_REMOTE_CONCURRENT_PASSED")
}
