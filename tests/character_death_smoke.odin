// A character that dies used to keep standing there: health reaching zero flipped
// a state machine to "Dead" and nothing else. There was no ragdoll and no
// respawn, so a dead character stayed on the map forever.
//
// The lifecycle is now: health reaches zero -> the collision capsule is handed to
// the solver as a dynamic body and the visible parts follow it -> after
// RespawnTime the character is replaced by a fresh one at the Spawn part.
//
// Death and respawn are server decisions. This runs a real server and one client
// over a socket so the character is built by the ordinary spawn path, and it
// checks the ragdoll from Odin because the interesting part -- the capsule going
// from a body the controller teleports to one the solver integrates -- is engine
// state rather than something a script can see.
package main

import "core:fmt"
import "core:math"
import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(name)
		fmt.eprintln(err)
		delete(err)
		panic("character death smoke test failed")
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

physics_service :: proc(server: ^engine_runtime.Environment) -> ^services.Physics {
	descriptor := services.Find_Service(&server.services, "Physics")
	if descriptor == nil {return nil}
	return cast(^services.Physics)descriptor.object
}

// character_parts reaches into the live server state for the one player's
// character and returns its controller, collision capsule and root.
character_parts :: proc(
	server: ^engine_runtime.Environment,
) -> (
	player: ^services.Player,
	model: ^classes.CharacterModel,
	controller: ^classes.CharacterController,
	collision: ^classes.CollisionController,
	root: ^classes.Part,
) {
	descriptor := services.Ensure_Service(&server.services, "Players")
	if descriptor == nil {return}
	roster := cast(^services.Players)descriptor
	if roster == nil {return}
	for child in roster.children {
		if child == nil || child.destroyed || !classes.Is_A(child, "Player") {continue}
		player = cast(^services.Player)child
		break
	}
	if player == nil {return}
	model = player.character
	if model == nil || model.destroyed {return}
	controller = classes.CharacterController_From_Model(model)
	if controller == nil {return}
	collision = cast(^classes.CollisionController)classes.CharacterController_Find(
		controller,
		"CollisionController",
	)
	root = classes.CharacterModel_Root(model)
	return
}

main :: proc() {
	server_vm := vm.New()
	client_vm := vm.New()
	server: engine_runtime.Environment
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)
	engine_runtime.Environment_Init(&client, &client_vm)

	run_script(&server_vm, `
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39215))

-- A Spawn part well away from the origin, so "respawned on the Spawn part" is
-- distinguishable from "respawned at the default fallback".
spawn = Instance.new("Part", workspace)
spawn.Name = "Spawn"
spawn.Size = vector.create(20, 1, 20)
spawn.CFrame = CFrame.new(100, 60, 100)
spawn.Anchored = true

floor = Instance.new("Part", workspace)
floor.Name = "Floor"
floor.Size = vector.create(600, 1, 600)
floor.CFrame = CFrame.new(100, 0, 100)
floor.Anchored = true

-- Keep the death window short so the respawn is reachable in a test.
game:GetService("CharacterService").RespawnTime = 0.5
`, "death_server_start")
	run_script(&client_vm, `
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39215))
`, "death_client_start")
	step_pair(&server, &server_vm, &client, &client_vm, 240)

	// The character was placed from the Spawn part, not the default fallback.
	run_script(&server_vm, `
player = game:GetService("Players"):GetPlayers()[1]
assert(player, "no player joined")
assert(player.Character, "no character spawned")
root = player.Character.RootPart
assert(root, "no HumanoidRootPart")
assert(math.abs(root.CFrame.X - 100) < 1, "character X was " .. root.CFrame.X)
assert(math.abs(root.CFrame.Z - 100) < 1, "character Z was " .. root.CFrame.Z)
assert(root.CFrame.Y > 1, "the character fell through the floor")

humanoid = nil
for _, child in ipairs(player.Character:GetChildren()) do
    if child.ClassName == "Humanoid" then humanoid = child end
end
assert(humanoid, "no Humanoid in the character")
assert(humanoid.Health == 100, "a fresh character is not at full health")
`, "death_spawned")

	player, model, controller, collision, root := character_parts(&server)
	assert(player != nil && model != nil, "server state did not expose a character")
	assert(controller != nil && collision != nil, "the character has no controller capsule")
	assert(collision.ragdoll == false, "a living character is already ragdolling")

	// Let it settle on the floor so the settled state is the baseline, then lift it
	// back into the air. A body resting on flat ground settles the same whether the
	// solver or the controller owns it, so the ragdoll is shown by killing the
	// character while it is falling.
	step_pair(&server, &server_vm, &client, &client_vm, 120)
	run_script(&server_vm, `player:Teleport(CFrame.new(100, 200, 100))`, "death_lift")
	step_pair(&server, &server_vm, &client, &client_vm, 2)
	run_script(&server_vm, `humanoid.Health = 0`, "death_kill")
	step_pair(&server, &server_vm, &client, &client_vm, 6)

	player, model, controller, collision, root = character_parts(&server)
	assert(controller.ragdoll == true, "the character controller did not enter the ragdoll")
	assert(collision.ragdoll == true, "the collision capsule was not handed to the solver")

	// The visible root has to follow the body the solver is actually simulating,
	// or the character stands still while an invisible capsule falls away from it.
	// The copy runs ahead of the physics step, so the root trails the body by one
	// frame of motion -- close, and behind a body that is falling.
	physics := physics_service(&server)
	capsule, ok := services.Physics_Get_Character_Capsule_CFrame(physics, collision)
	assert(ok, "the ragdolling capsule has no transform")
	trail := capsule.y - root.cframe.y
	assert(
		math.abs(root.cframe.x - capsule.x) < 0.5 &&
			math.abs(root.cframe.z - capsule.z) < 0.5,
		"the root did not follow the simulated body horizontally",
	)
	assert(trail < 1.0, "the root did not follow the simulated body vertically")
	settled_y := root.cframe.y

	// A dead body is solver-owned, so it keeps falling under gravity instead of
	// being held where the walk left it.
	step_pair(&server, &server_vm, &client, &client_vm, 10)
	_, _, _, _, fallen := character_parts(&server)
	assert(
		fallen.cframe.y < settled_y - 0.5,
		"the dead body did not keep falling",
	)
	// Past RespawnTime the character is replaced by a live one at the Spawn part.
	step_pair(&server, &server_vm, &client, &client_vm, 240)
	run_script(&server_vm, `
player = game:GetService("Players"):GetPlayers()[1]
assert(player.Character, "the character was not respawned")
root = player.Character.RootPart
assert(root, "the respawned character has no HumanoidRootPart")
assert(math.abs(root.CFrame.X - 100) < 1, "respawn X was " .. root.CFrame.X)
assert(math.abs(root.CFrame.Z - 100) < 1, "respawn Z was " .. root.CFrame.Z)
assert(root.CFrame.Y > 1, "the respawned character fell through the floor")

humanoid = nil
for _, child in ipairs(player.Character:GetChildren()) do
    if child.ClassName == "Humanoid" then humanoid = child end
end
assert(humanoid, "the respawned character has no Humanoid")
assert(humanoid.Health == 100, "the respawned character is not at full health")
`, "death_respawned")

	// The replacement is a fresh body, back under the character controller.
	_, _, controller, collision, _ = character_parts(&server)
	assert(controller.ragdoll == false, "the replacement is still ragdolling")
	assert(collision.ragdoll == false, "the replacement capsule is still dynamic")

	// The replication transport owns a thread, so it has to be stopped on both
	// sides before the VMs are closed. Closing a client VM that still has a live
	// connection faults, which is why every socket smoke test here stops the
	// replicator first.
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "death_server_stop")
	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "death_client_stop")
	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("CHARACTER_DEATH_SMOKE_PASSED")
}

