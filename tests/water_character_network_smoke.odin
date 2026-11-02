package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.Run(v, source, "water_character_network_smoke")
	assert(ok, err)
}

main :: proc() {
	sv, cv := vm.New(), vm.New()
	server, client: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &sv)
	engine_runtime.Environment_Init(&client, &cv)
	defer {
		vm.Close(&cv); vm.Close(&sv)
		engine_runtime.Environment_Destroy(&client); engine_runtime.Environment_Destroy(&server)
	}
	run(
		&sv,
		`
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1",39494))
local pool = Instance.new("Part",workspace)
pool.Name = "Pool"; pool.Anchored = true
pool.Material = Enum.Material.Water
pool.Size = Vector3.new(80,20,80); pool.CFrame = CFrame.new(0,-6,0)
`,
	)
	run(&cv, `assert(game:GetService("ReplicatorService"):ConnectClient("127.0.0.1",39494))`)
	for _ in 0 ..< 360 {
		engine_runtime.Environment_Render_Step(&server, &sv, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&client, &cv, 1.0 / 60.0)
	}
	run(
		&cv,
		`
local char = game:GetService("Players").LocalPlayer.Character
assert(char and char.RootPart)
local y = char.RootPart.CFrame.Position.Y
assert(y > 1 and y < 6,"networked player did not float: "..tostring(y))
char:PivotTo(CFrame.new(0,-5,0))
`,
	)
	for _ in 0 ..< 240 {
		engine_runtime.Environment_Render_Step(&server, &sv, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&client, &cv, 1.0 / 60.0)
	}
	run(
		&cv,
		`
local y = game:GetService("Players").LocalPlayer.Character.RootPart.CFrame.Position.Y
assert(y > 1 and y < 6,"submerged player did not rise: "..tostring(y))
`,
	)
	run(
		&sv,
		`
local y = game:GetService("Players"):GetPlayers()[1].Character.RootPart.CFrame.Position.Y
assert(y > 1 and y < 6,"server did not receive floating character: "..tostring(y))
game:GetService("Players"):GetPlayers()[1].Character.Humanoid:TakeDamage(100)
`,
	)
	for _ in 0 ..< 120 {
		engine_runtime.Environment_Render_Step(&server, &sv, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&client, &cv, 1.0 / 60.0)
	}
	run(
		&sv,
		`
local y = game:GetService("Players"):GetPlayers()[1].Character.RootPart.CFrame.Position.Y
assert(y > -1 and y < 7,"ragdoll did not float: "..tostring(y))
`,
	)
	run(&cv, `game:GetService("ReplicatorService"):Stop()`)
	run(&sv, `game:GetService("ReplicatorService"):Stop()`)
	fmt.println("WATER_CHARACTER_NETWORK_SMOKE_PASSED")
}
