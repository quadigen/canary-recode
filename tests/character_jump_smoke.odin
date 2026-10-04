// The client used to hold the character with a `continue` placed before
// CharacterController_Tick, which meant the controller's GroundDetector,
	// CollisionController and jump handling never ran. That presented as a
	// character that could not jump, could not collide, and sat at a fixed Y.
	// This asserts a character standing on a real collidable floor can jump: the
	// controller must own gravity, collision and jumping, with nothing in the
	// character service short-circuiting it.
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
		panic("character jump smoke failed")
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

	// A collidable floor the character is guaranteed to land on. It is deliberately
	// NOT the "Spawn" marker: the marker is a non-colliding position hint that
	// puts the character 4 studs up, so the character starts airborne above the
	// floor. That is the shape that made the old client-side ground probe
	// misreport "no support" and freeze the character instead of letting the
	// controller jump and collide.
	run_script(&server_vm, `
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39228))
local floor = Instance.new("Part", workspace)
floor.Name = "Floor"
floor.Size = Vector3.new(500, 1, 500)
floor.CFrame = CFrame.new(0, 4, 0)
floor.Anchored = true
local marker = Instance.new("Part", workspace)
marker.Name = "Spawn"
marker.Size = Vector3.new(20, 1, 20)
marker.CFrame = CFrame.new(0, 6, 0)
marker.Anchored = true
marker.CanCollide = false
marker.CanQuery = false
`, "jump_server_start")
	run_script(&client_vm, `
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39228))
`, "jump_client_start")

	// Let the character spawn, land and settle on the floor.
	step_pair(&server, &server_vm, &client, &client_vm, 180)
	run_script(&client_vm, `
local character = game:GetService("Players").LocalPlayer.Character
assert(character and character.RootPart, "the client never got a character")
jump_ground_y = character.RootPart.Position.Y
assert(jump_ground_y > 5, "the character was not standing on the floor, y=" .. tostring(jump_ground_y))
`, "jump_client_grounded")

	// Jump, and sample while airborne.
	run_script(&client_vm, `
game:GetService("CharacterService"):Jump()
`, "jump_client_do")
	step_pair(&server, &server_vm, &client, &client_vm, 12)
	run_script(&client_vm, `
local character = game:GetService("Players").LocalPlayer.Character
jump_peak_y = character.RootPart.Position.Y
`, "jump_client_sample")

	run_script(&client_vm, `
local character = game:GetService("Players").LocalPlayer.Character
local peak = jump_peak_y
assert(
	peak > jump_ground_y + 1,
	"the character did not jump: ground y=" .. tostring(jump_ground_y) ..
		" peak y=" .. tostring(peak)
)
`, "jump_client_rose")

	// And it must come back down onto the floor rather than falling through it.
	step_pair(&server, &server_vm, &client, &client_vm, 120)
	run_script(&client_vm, `
local character = game:GetService("Players").LocalPlayer.Character
local y = character.RootPart.Position.Y
assert(
	y > 5,
	"the character fell through the floor after jumping, y=" .. tostring(y)
)
`, "jump_client_landed")

	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "jump_client_stop")
	step_pair(&server, &server_vm, &client, &client_vm, 30)
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "jump_server_stop")
	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("CHARACTER_JUMP_SMOKE_PASSED")
}