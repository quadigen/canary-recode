// workspace.FinishedReplicating must be a pure notification. The moment it
// fires the client owns the full map, and the local character must keep working
// exactly as it did during streaming: gravity, collision against replicated
// Parts, and jumping.
//
// This is the regression test for a client that cannot stand on the world it
// just received. There were two independent causes, and both are exercised here.
//
// First, the client refuses to give a replicated Part a physics body until that
// Part's first authoritative transform arrives. A Part the physics sync walked
// before its transform landed was skipped and, because a property update moves
// no structural epoch, was never revisited, so it stayed permanently bodyless:
// invisible to the client's physics no matter how complete the map looked.
//
// Second, and worse, the client built its character as soon as the character
// replicated -- long before the map underneath it existed. That started the
// character integrating gravity against a floor that had not arrived, so it fell
// out of the world while the map was still streaming. On a real map that put the
// character tens of studs below the terrain with nothing left to catch it, and it
// fell forever. Note that workspace.FinishedReplicating is not a usable gate for
// this: it reports that the scene was *sent*, and it lands while the physics
// bodies for that scene are still being built. The gate is the scene-ready
// barrier, which the server only sends once the spawn platform, the character's
// parts, the geometry under it, and the terrain have all arrived.
//
// The bandwidth budget is squeezed so the first-state pass is spread over many
// snapshots while the spawn pass completes early. That is the shape any real
// large map has, and it is what leaves Parts stranded mid-stream and the ground
// arriving late.
package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(name)
		fmt.eprintln(err)
		delete(err)
		panic("character finished replicating smoke failed")
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
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)

	run_script(&server_vm, `
local replicator = game:GetService("ReplicatorService")
-- A budget this small cannot carry a first state for every Part in one
-- snapshot, so the Parts whose initial state is deferred are exactly the ones
-- that used to end up with no body at all.
replicator.BandwidthBudget = 6 * 1024
assert(replicator:StartServer("127.0.0.1", 39230))
local floor = Instance.new("Part", workspace)
floor.Name = "Floor"
floor.Size = Vector3.new(600, 1, 600)
floor.CFrame = CFrame.new(0, 0, 0)
floor.Anchored = true
local wall = Instance.new("Part", workspace)
wall.Name = "Wall"
wall.Size = Vector3.new(2, 24, 80)
wall.CFrame = CFrame.new(70, 12, 0)
wall.Anchored = true
local marker = Instance.new("Part", workspace)
marker.Name = "Spawn"
marker.Size = Vector3.new(20, 1, 20)
marker.CFrame = CFrame.new(0, 4, 0)
marker.Anchored = true
marker.CanCollide = false
marker.CanQuery = false
for index = 1, 1200 do
    local part = Instance.new("Part", workspace)
    part.Name = "MapPart" .. tostring(index)
    part.Size = Vector3.new(2, 2, 2)
    part.CFrame = CFrame.new(0, 300 + index * 4, 0)
    part.Anchored = true
end
`, "finished_char_server_start")
	run_script(&client_vm, `
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39230))
workspace.FinishedReplicating:Connect(function()
    finished_count = (finished_count or 0) + 1
end)
`, "finished_char_client_start")

	// Stream the map, sampling the whole way. The dip this guards against happens
	// *during* streaming: a client that builds its character before the ground
	// arrives starts integrating gravity against a floor that is not there yet, and
	// by the time the map is complete the character is far below the world with
	// nothing left to catch it. Sampling only after the barrier cannot see that,
	// which is exactly how a character that fell 13 studs on a real map passed here.
	streaming_client_init := `
local players = game:GetService("Players")
local lp = players.LocalPlayer
local char = lp and lp.Character
local stats = game:GetService("ReplicatorService"):GetStats()
if not stats.sceneReady then
    if char ~= nil then
        streaming_built_early = true
    end
    if char ~= nil then
        local root = char:FindFirstChild("HumanoidRootPart")
        if root ~= nil then
            streaming_min_y = math.min(streaming_min_y or math.huge, root.Position.Y)
        end
    end
end
`
	for _ in 0 ..< 20 {
		step_pair(&server, &server_vm, &client, &client_vm, 20)
		run_script(&client_vm, streaming_client_init, "finished_char_client_stream_sample")
	}
	run_script(&client_vm, `
assert(
    not streaming_built_early,
    "the client built its character before the scene was ready, so it simulated " ..
        "against a floor that had not arrived yet"
)
assert(
    streaming_min_y == nil or streaming_min_y > 5,
    "the character fell while the map was still streaming, min y=" .. tostring(streaming_min_y)
)
assert(
    finished_count == 1,
    "workspace.FinishedReplicating did not fire exactly once: " .. tostring(finished_count)
)
local character = game:GetService("Players").LocalPlayer.Character
assert(character and character.RootPart, "the client never got a character")
`, "finished_char_client_finished")

	// The whole map is here, so every collidable Part must have a body. A Part
	// that replicated but never got one is invisible to the client's physics.
	run_script(&client_vm, `
local physics = game:GetService("Physics")
local parts, collidable = 0, 0
for _, instance in ipairs(workspace:GetDescendants()) do
    if instance:IsA("Part") then
        parts = parts + 1
        if instance.CanCollide then collidable = collidable + 1 end
    end
end
finished_parts = parts
finished_bodies = physics.BodyCount
assert(
    physics.BodyCount >= collidable - 4,
    "the client never built bodies for the replicated map: " .. tostring(physics.BodyCount) ..
        " bodies for " .. tostring(collidable) .. " collidable Parts"
)
`, "finished_char_client_bodies")

	// Nothing should be frozen: the character must settle onto the floor and
	// stay there rather than hanging in the air with gravity suspended.
	run_script(&client_vm, `
local character = game:GetService("Players").LocalPlayer.Character
finished_ground_y = character.RootPart.Position.Y
`, "finished_char_client_sample_ground")
	step_pair(&server, &server_vm, &client, &client_vm, 60)
	run_script(&client_vm, `
local character = game:GetService("Players").LocalPlayer.Character
finished_settled_y = character.RootPart.Position.Y
assert(
    finished_settled_y > 0.5,
    "the character is not standing on the replicated map after it finished replicating, y=" ..
        tostring(finished_settled_y)
)
assert(
    math.abs(finished_settled_y - finished_ground_y) < 1,
    "the character did not settle, it is still moving: y=" .. tostring(finished_ground_y) ..
        " -> " .. tostring(finished_settled_y)
)
`, "finished_char_client_settled")

	// Jump, after the barrier.
	run_script(&client_vm, `
game:GetService("CharacterService"):Jump()
`, "finished_char_client_do_jump")
	step_pair(&server, &server_vm, &client, &client_vm, 14)
	run_script(&client_vm, `
local character = game:GetService("Players").LocalPlayer.Character
finished_peak_y = character.RootPart.Position.Y
assert(
    finished_peak_y > finished_settled_y + 1,
    "the character could not jump after the map finished replicating: y=" ..
        tostring(finished_settled_y) .. " peak y=" .. tostring(finished_peak_y)
)
`, "finished_char_client_jumped")

	// Land again.
	step_pair(&server, &server_vm, &client, &client_vm, 120)
	run_script(&client_vm, `
local character = game:GetService("Players").LocalPlayer.Character
local y = character.RootPart.Position.Y
assert(
    y > 0.5 and math.abs(y - finished_settled_y) < 2,
    "the character did not land back on the replicated floor, y=" .. tostring(y)
)
`, "finished_char_client_landed")

	// And collide: walking into the replicated wall must stop the character.
	run_script(&client_vm, `
game:GetService("CharacterService"):SetMoveDirection(Vector3.new(1, 0, 0))
`, "finished_char_client_walk")
	step_pair(&server, &server_vm, &client, &client_vm, 480)
	run_script(&client_vm, `
game:GetService("CharacterService"):SetMoveDirection(Vector3.new(0, 0, 0))
local character = game:GetService("Players").LocalPlayer.Character
local x = character.RootPart.Position.X
assert(
    x < 70,
    "the character walked through the replicated wall after the map finished replicating, x=" ..
        tostring(x)
)
assert(
    x > 60,
    "the character never reached the replicated wall after the map finished replicating, x=" ..
        tostring(x)
)
`, "finished_char_client_blocked")

	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "finished_char_client_stop")
	step_pair(&server, &server_vm, &client, &client_vm, 30)
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "finished_char_server_stop")
	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("CHARACTER_FINISHED_REPLICATING_SMOKE_PASSED")
}