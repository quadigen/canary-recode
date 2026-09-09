package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	ok, err := vm.Run(&script_vm, `
assert(game.ClassName == "DataModel")
assert(game.Name == "game")
assert(workspace == game.Workspace)
assert(workspace == game:GetService("Workspace"))
assert(workspace.Parent == game)
assert(game:FindService("MissingService") == nil)
assert(not pcall(function() game:GetService("MissingService") end))

local children = game:GetChildren()
assert(#children == 7)
local expected = {
    Workspace = true,
    UserInputService = true,
    ExampleService = true,
    RunService = true,
    TaskScheduler = true,
    ScriptContext = true,
    StarterGui = true,
}
for _, service in children do
    assert(expected[service.Name])
    assert(service.Parent == game)
    expected[service.Name] = nil
end
assert(next(expected) == nil)

local example = game:GetService("ExampleService")
assert(example:GetService("Workspace") == workspace)
assert(example:GetService("RunService") == game.RunService)
assert(example:GetService("MissingService") == nil)
`, "data_model_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("DataModel smoke test failed")
	}

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("DATA_MODEL_SMOKE_PASSED")
}
