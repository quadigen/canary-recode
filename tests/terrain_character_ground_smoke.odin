// Terrain had no Jolt body at all when a character controller swept against the
// world, so a character walked through visible ground and fell forever.
//
// The capsule is not a dynamic body the solver resolves: CharacterController_Tick
// sweeps the capsule shape and teleports the root to whatever it stops against.
// That sweep gathers its candidates from Physics_Candidate_Bodies, so terrain
// only became walkable ground once the terrain body was on that list. A Part
// floor hides this because Parts are on the list already.
package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

// A 200x4x200 slab selects cells whose centres fall inside it, which are two
// cells thick on y spanning -4..4, so its walkable top face is y = 4. The
// character capsule is 3x3x3, so resting on it puts the root centre near 7.
// The assertions below use 5 and 20 to leave room for a settling bounce while
// still failing a character that kept falling.

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(name)
		fmt.eprintln(err)
		delete(err)
		panic("terrain character ground smoke failed")
	}
}

step_pair :: proc(
	server: ^engine_runtime.Environment,
	server_vm: ^vm.VM,
	client: ^engine_runtime.Environment,
	client_vm: ^vm.VM,
	frames: int,
) {
	for _ in 0..<frames {
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

	// Terrain is the only floor in this world. There is deliberately no Part
	// anywhere near the spawn, so anything that stands on the ground is standing
	// on terrain and nothing else.
	run_script(&server_vm, `
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39195))
assert(IsServer and not IsClient)

local Terrain = game:GetService("Terrain")
Terrain:Clear()
Terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(200, 4, 200), Enum.Material.Grass)
assert(Terrain:CountCells() > 0, "the terrain slab was not filled")
`, "terrain_character_server_start")

	run_script(&client_vm, `
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39195))
assert(IsClient and not IsServer)
`, "terrain_character_client_start")

	step_pair(&server, &server_vm, &client, &client_vm, 240)

	// The character is client-authoritative, so the client is where the sweep
	// runs and where a fall through the floor shows up.
	run_script(&client_vm, `
local player = game:GetService("Players").LocalPlayer
local character = player.Character
assert(character and character.RootPart, "the client never got a character")

local y = character.RootPart.Position.Y
assert(y > 5, "the character fell through the terrain, ending at y=" .. tostring(y))
assert(y < 20, "the character sank into the terrain, ending at y=" .. tostring(y))

-- Walking has to work too, which is the other half of "colliding with terrain":
-- a character stopped by the ground should still be able to move along it
-- rather than being pinned in place by the surface it is standing on.
game:GetService("CharacterService"):SetMoveDirection(Vector3.new(1, 0, 0))
`, "terrain_character_grounded")

	run_script(&client_vm, `
local character = game:GetService("Players").LocalPlayer.Character
start_x = character.RootPart.Position.X
`, "terrain_character_walk_start")

	step_pair(&server, &server_vm, &client, &client_vm, 60)

	run_script(&client_vm, `
local character = game:GetService("Players").LocalPlayer.Character
local x = character.RootPart.Position.X
assert(
	x > start_x + 1,
	"the character did not move along the terrain, x went from " ..
		tostring(start_x) .. " to " .. tostring(x)
)
local y = character.RootPart.Position.Y
assert(y > 5, "the character sank into the terrain while walking, ending at y=" .. tostring(y))
`, "terrain_character_walked")

	fmt.println("TERRAIN_CHARACTER_GROUND_SMOKE_PASSED")

	// The client goes down first and the server is given frames to notice, the
	// same teardown order the character replication suite uses. Dropping the
	// server out from under a live client tears down replicated instances the
	// client is still holding.
	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "terrain_character_client_stop")
	step_pair(&server, &server_vm, &client, &client_vm, 30)
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "terrain_character_stop")
	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
}
