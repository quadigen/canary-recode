
package main

import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
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
		engine_runtime.Environment_Update_Step(server, server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(server, server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Update_Step(client, client_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(client, client_vm, 1.0 / 60.0)
	}
}

main :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm, nil, .Server)
	engine_runtime.Environment_Init(&client, &client_vm, nil, .Client)

	// A scene with enough Parts that it cannot all arrive in the first snapshot,
	// so the signal firing is meaningful rather than trivially true on frame one.
	run_script(
		&server_vm,
		`
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39229))
game:GetService("ReplicatorService").BandwidthBudget = 16 * 1024
local hud = Instance.new("ScreenGui", game:GetService("StarterGui"))
hud.Name = "Hud"
for index = 1, 24 do
    local panel = Instance.new("Frame", hud)
    panel.Name = "Panel" .. index
    panel.Size = UDim2.fromOffset(300, 400)
    panel.Position = UDim2.new(0, 8, 1, -8)
    panel.BackgroundTransparency = 0.5
    local preview = Instance.new("ViewportFrame", panel)
    preview.Size = UDim2.fromScale(1, 0.7)
end
local bootstrap = Instance.new("LocalScript", hud)
bootstrap.Name = "Bootstrap"
bootstrap.Source = [[
    for index = 1, 24 do
        local panel = script.Parent["Panel" .. index]
        assert(panel.Size.X.Offset == 300 and panel.Size.Y.Offset == 400)
        local preview = panel.ViewportFrame
        local camera = Instance.new("Camera", preview)
        preview.CurrentCamera = camera
    end
    _G.previewRuns = (_G.previewRuns or 0) + 1
]]
local playerScript = Instance.new("LocalScript", game:GetService("StarterPlayer").StarterPlayerScripts)
playerScript.Name = "PlayerBootstrap"
playerScript.Source = "_G.playerRuns = (_G.playerRuns or 0) + 1"
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
    local hud = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("Hud")
    finished_gui_ok = hud ~= nil and #hud:GetChildren() == 25
    if hud then
        for index = 1, 24 do
            local panel = hud:FindFirstChild("Panel" .. index)
            finished_gui_ok = finished_gui_ok and panel ~= nil
                and panel.Size == UDim2.fromOffset(300, 400)
                and panel.Position == UDim2.new(0, 8, 1, -8)
                and panel.BackgroundTransparency == 0.5
                and panel.ViewportFrame.Size == UDim2.fromScale(1, 0.7)
        end
        finished_gui_ok = finished_gui_ok and #hud.Bootstrap.Source > 0
    end
end)
`,
		"finished_client_connect",
	)

	step_pair(&server, &server_vm, &client, &client_vm, 300)
	server_replication := cast(^services.ReplicatorService)services.Ensure_Service(&server.services, "ReplicatorService")
	client_replication := cast(^services.ReplicatorService)services.Ensure_Service(&client.services, "ReplicatorService")
	join_batches := server_replication.diag_kind_counts[services.Replication_Kind_Join_Batch]
	assert(join_batches > 0 && client_replication.malformed_packets == 0)

	run_script(
		&client_vm,
		`
assert(fired_count ~= nil, "workspace.FinishedReplicating never fired")
assert(fired_count == 1, "the signal fired more than once: " .. tostring(fired_count))
assert(finished_gui_ok, "PlayerGui was cloned before its initial properties and scripts arrived")
assert(_G.previewRuns == 1 and _G.playerRuns == 1, "client scripts must start with complete sources")
local hud = game:GetService("Players").LocalPlayer.PlayerGui.Hud
assert(hud.Panel1.ViewportFrame.CurrentCamera ~= nil, "client script did not initialize the viewport")
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

	run_script(&server_vm, `
game:GetService("StarterGui").Hud.Panel1.BackgroundTransparency = 0.25
`, "finished_server_update")
	step_pair(&server, &server_vm, &client, &client_vm, 60)
	run_script(&client_vm, `
assert(game:GetService("StarterGui").Hud.Panel1.BackgroundTransparency == 0.25)
`, "finished_client_update")
	run_script(&server_vm, `
game:GetService("StarterGui").Hud.Panel1.BackgroundTransparency = 0.5
`, "finished_server_restore")
	step_pair(&server, &server_vm, &client, &client_vm, 60)

	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "finished_client_stop")
	run_script(&client_vm, `
local stats = game:GetService("ReplicatorService"):GetStats()
assert(not stats.sceneReady and not stats.replicationFinished, "Stop must reset initial scene barriers")
`, "finished_client_reset")
	step_pair(&server, &server_vm, &client, &client_vm, 30)
	client_replication.client_capabilities &= ~services.Replication_Capability_Join_Batch
	run_script(&client_vm, `
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39229))
`, "finished_client_reconnect")
	step_pair(&server, &server_vm, &client, &client_vm, 300)
	assert(server_replication.diag_kind_counts[services.Replication_Kind_Join_Batch] == join_batches)
	run_script(&client_vm, `
assert(fired_count == 2 and finished_gui_ok, "reconnecting must wait for complete GUI properties again")
assert(_G.previewRuns == 2 and _G.playerRuns == 2,
    "reconnecting must initialize new client scripts once: previews=" .. tostring(_G.previewRuns) .. " players=" .. tostring(_G.playerRuns))
game:GetService("ReplicatorService"):Stop()
`, "finished_client_reconnected")
	step_pair(&server, &server_vm, &client, &client_vm, 30)
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "finished_server_stop")
	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("WORKSPACE_FINISHED_REPLICATING_SMOKE_PASSED")
}
