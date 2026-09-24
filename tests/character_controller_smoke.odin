package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_cc :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("character controller smoke failed")
	}
}

cc_step :: proc(env: ^engine_runtime.Environment, script_vm: ^vm.VM, frames: int) {
	for _ in 0..<frames {
		engine_runtime.Environment_Render_Step(env, script_vm, 1.0 / 60.0)
	}
}

main :: proc() {
	script_vm := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm)
	run_cc(&script_vm, `
assert(game:GetService("ReplicatorService"):StartServer("127.0.0.1", 39187))
local m = Instance.new("Model", workspace)
Instance.new("StateMachine", m)
Instance.new("CharacterAnimator", m)
Instance.new("CharacterInput", m)
Instance.new("CharacterCamera", m)
assert(m:FindFirstChildOfClass("StateMachine"))
assert(m:FindFirstChildOfClass("CharacterAnimator"))
assert(m:FindFirstChildOfClass("CharacterInput"))
assert(m:FindFirstChildOfClass("CharacterCamera"))
m:Destroy()
`, "character_controller_part1")
	cc_step(&env, &script_vm, 30)
}