
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
		panic("character void world drive smoke failed")
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

	// The entire world is one non-colliding Spawn marker: a void map.
	run_script(
		&server_vm,
		`
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39226))
local spawn = Instance.new("Part", workspace)
spawn.Name = "Spawn"
spawn.Size = Vector3.new(40, 1, 40)
spawn.CFrame = CFrame.new(0, 500, 0)
spawn.Anchored = true
spawn.CanCollide = false
spawn.CanQuery = false
`,
		"void_server_start",
	)
	run_script(
		&client_vm,
		`
assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1", 39226))
`,
		"void_client_start",
	)

	step_pair(&server, &server_vm, &client, &client_vm, 60)
	run_script(
		&client_vm,
		`
game:GetService("CharacterService"):SetMoveDirection(Vector3.new(1, 0, 0))
local character = game:GetService("Players").LocalPlayer.Character
assert(character and character.RootPart, "the client never got a character")
drive_start_x = character.RootPart.Position.X
`,
		"void_client_drive_start",
	)

	// Comfortably past CHARACTER_SCENE_HOLD_FRAMES.
	step_pair(&server, &server_vm, &client, &client_vm, 240)
	run_script(
		&client_vm,
		`
local character = game:GetService("Players").LocalPlayer.Character
local x = character.RootPart.Position.X
assert(
	x > drive_start_x + 1,
	"the character could not be driven with no ground beneath it: x went from " ..
		tostring(drive_start_x) .. " to " .. tostring(x)
)
`,
		"void_client_drove",
	)

	run_script(&client_vm, `game:GetService("ReplicatorService"):Stop()`, "void_client_stop")
	step_pair(&server, &server_vm, &client, &client_vm, 30)
	run_script(&server_vm, `game:GetService("ReplicatorService"):Stop()`, "void_server_stop")
	vm.Close(&client_vm)
	vm.Close(&server_vm)
	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&server)
	fmt.println("CHARACTER_VOID_WORLD_DRIVE_SMOKE_PASSED")
}
