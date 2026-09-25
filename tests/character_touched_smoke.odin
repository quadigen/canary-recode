package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_touched :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("character touched smoke failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm)
	run_touched(&script_vm, `
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39188))
local floor = Instance.new("Part", workspace)
floor.Name = "Floor"
floor.Size = vector.create(50, 1, 50)
floor.CFrame = CFrame.new(0, 4, 0)
floor.Anchored = true

local ball = Instance.new("Part", workspace)
ball.Name = "Ball"
ball.Size = vector.create(2, 2, 2)
ball.CFrame = CFrame.new(0, 20, 0)
ball.Anchored = false

local box = Instance.new("Part", workspace)
box.Name = "Box"
box.Size = vector.create(2, 2, 2)
box.CFrame = CFrame.new(0, 30, 0)
box.Anchored = false

local hits = { floor = 0, ball = 0, box = 0 }
_G.hits = hits
floor.Touched:Connect(function(other)
    assert(other == ball or other == box, "floor told about the right part")
    hits.floor += 1
end)
ball.Touched:Connect(function(other)
    assert(other == floor or other == box, "ball told about the right part")
    hits.ball += 1
end)
box.Touched:Connect(function(other) hits.box += 1 end)
`, "touched_setup")
	for _ in 0..<240 {
		engine_runtime.Environment_Render_Step(&env, &script_vm, 1.0 / 60.0)
	}
	run_touched(&script_vm, `
assert(_G.hits.floor >= 1, "floor received Touched")
assert(_G.hits.ball >= 1, "ball received Touched")
assert(_G.hits.box >= 1, "box received Touched")
`, "touched_assert")
	fmt.println("CHARACTER_TOUCHED_SMOKE_PASSED")
}