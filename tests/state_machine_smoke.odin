package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_sm :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("state machine smoke failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm)
	run_sm(&script_vm, `
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39186))
local sm = Instance.new("StateMachine", workspace)
assert(sm:GetState() == "Idle")
local seen = {}
sm.StateChanged:Connect(function(old, new) seen[#seen + 1] = {old, new} end)
assert(sm:SetState("Running"))
assert(sm:GetState() == "Running")
assert(sm:SetState("Falling"))
assert(sm:GetState() == "Falling")
assert(sm:SetState("Falling") == false, "no event on same state")
assert(#seen == 2)
assert(seen[1][1] == "Idle" and seen[1][2] == "Running")
assert(seen[2][1] == "Running" and seen[2][2] == "Falling")
assert(sm.Name == "StateMachine" and sm.ClassName == "StateMachine")
local sibling = Instance.new("Part", workspace)
assert(sibling:IsA("Part"))
sm:Destroy()
`, "state_machine")
	for _ in 0..<30 {
		engine_runtime.Environment_Render_Step(&env, &script_vm, 1.0 / 60.0)
	}
}