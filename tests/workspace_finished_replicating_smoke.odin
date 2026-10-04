
package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(name)
		fmt.eprintln(err)
		delete(err)
		panic("workspace finished replicating smoke failed")
	}
}

step_pair :: proc(
	server: ^engine_runtime.Environment,
	server_vm: ^vm.VM,
	client: ^engine_runtime.Environment,
	client_vm: ^vm.VM,
	frames: int,
) {
	for _ in 0 ..< frames {
		engine_runtime.Environment_Render_Step(server, server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(client, client_vm, 1.0 / 60.0)
	}
}

main :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)

	// A scene with enough Parts that it cannot all arrive in the first snapshot,
	// so the signal firing is meaningful rather than trivially true on frame one.
	run_script(
		&server_vm,
		`
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39229))
local spawn = Instance.new("Part", workspace)
spawn.Name = "Spawn"
spawn.Size = Vector3.new(500, 1, 500)
spawn.CFrame = CFrame.new(0, 4, 0)
spawn.Anchored = true
for index = 1, 600 do
    local part = Instance.new("Part", workspace)
    part.Name = "MapPart" .. tostring(index)
    part.CFrame = CFrame.new(index * 3, 0, 0)
    part.Anchored = true
end
`,
		"finished_server_start",
	)
	run_script(
		&client_vm,
		`
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39229))
workspace.FinishedReplicating:Connect(function()
    fired_count = (fired_count or 0) + 1
    -- By the time this fires the whole scene must be present.
    fired_children = #workspace:GetChildren()
end)
`,
		"finished_client_connect",
	)

	step_pair(&server, &server_vm, &client, &client_vm, 300)

	run_script(
		&client_vm,
		`
assert(fired_count ~= nil, "workspace.FinishedReplicating never fired")
assert(fired_count == 1, "the signal fired more than once: " .. tostring(fired_count))
assert(
    game:GetService("ReplicatorService"):GetStats().replicationFinished,
    "replicationFinished was not set"
)
`,
		"finished_client_fired",
	)

	// It must stay fired: a later frame must not re-trigger the signal.
	step_pair(&server, &server_vm, &client, &client_vm, 120)
	run_script(
		&client_vm,
		`
assert(fired_count == 1, "the signal re-fired after the scene settled: " .. tostring(fired_count))
`,
		"finished_client_once",
	)

	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "finished_client_stop")
	step_pair(&server, &server_vm, &client, &client_vm, 30)
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "finished_server_stop")
	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("WORKSPACE_FINISHED_REPLICATING_SMOKE_PASSED")
}
