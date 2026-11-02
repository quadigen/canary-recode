


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


	run_script(
		&server_vm,
		`
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39195))
assert(IsServer and not IsClient)

local Terrain = game:GetService("Terrain")
Terrain:Clear()
Terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(200, 4, 200), Enum.Material.Grass)
assert(Terrain:CountCells() > 0, "the terrain slab was not filled")
`,
		"terrain_character_server_start",
	)

	run_script(
		&client_vm,
		`
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39195))
assert(IsClient and not IsServer)
`,
		"terrain_character_client_start",
	)

	step_pair(&server, &server_vm, &client, &client_vm, 240)


	run_script(
		&client_vm,
		`
local player = game:GetService("Players").LocalPlayer
local character = player.Character
assert(character and character.RootPart, "the client never got a character")

local y = character.RootPart.Position.Y
assert(y > 4, "the character fell through the terrain, ending at y=" .. tostring(y))
assert(y < 7, "the character sank into the terrain, ending at y=" .. tostring(y))

-- Walking has to work too, which is the other half of "colliding with terrain":
-- a character stopped by the ground should still be able to move along it
-- rather than being pinned in place by the surface it is standing on.
game:GetService("CharacterService"):SetMoveDirection(Vector3.new(1, 0, 0))
`,
		"terrain_character_grounded",
	)

	run_script(
		&client_vm,
		`
local character = game:GetService("Players").LocalPlayer.Character
start_x = character.RootPart.Position.X
`,
		"terrain_character_walk_start",
	)

	step_pair(&server, &server_vm, &client, &client_vm, 60)

	run_script(
		&client_vm,
		`
local character = game:GetService("Players").LocalPlayer.Character
local x = character.RootPart.Position.X
assert(
	x > start_x + 1,
	"the character did not move along the terrain, x went from " ..
		tostring(start_x) .. " to " .. tostring(x)
)
local y = character.RootPart.Position.Y
assert(y > 4, "the character sank into the terrain while walking, ending at y=" .. tostring(y))
`,
		"terrain_character_walked",
	)

	fmt.println("TERRAIN_CHARACTER_GROUND_SMOKE_PASSED")


	run_script(
		&client_vm,
		`game:GetService("ReplicatorService"):Stop()`,
		"terrain_character_client_stop",
	)
	step_pair(&server, &server_vm, &client, &client_vm, 30)
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "terrain_character_stop")
	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
}
