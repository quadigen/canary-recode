package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

main :: proc() {
    script_vm := vm.New()
    environment: engine_runtime.Environment
    engine_runtime.Environment_Init(&environment, &script_vm)

    visible_count := 0
    for service in environment.services.services {
        assert(service.object != nil)
        assert(service.object.parent == &environment.services.data_model.object)
        assert(service.object.name == service.name)
        if vm.SecurityRequirementIsNone(service.security) { visible_count += 1 }
    }
    vm.AddGlobal_Number(&script_vm, "expectedVisibleServices", f64(visible_count))
    vm.AddGlobal_Number(&script_vm, "expectedAllServices", f64(len(environment.services.services)))

    ok, err := vm.Run(&script_vm, `
assert(game.ClassName == "DataModel")
assert(game.Name == "game")
assert(workspace == game.Workspace)
assert(workspace == game:GetService("Workspace"))
assert(workspace.Parent == game)
assert(game:FindFirstChild("Workspace") == workspace)
assert(game:FindService("MissingService") == nil)
assert(not pcall(function() game:GetService("MissingService") end))

local children = game:GetChildren()
local visited = 0
local foundWorkspace = false
local seen = {}
for _, service in ipairs(children) do
    visited += 1
    assert(service.Parent == game)
    assert(not seen[service.Name])
    seen[service.Name] = true
    assert(game:GetService(service.Name) == service)
    foundWorkspace = foundWorkspace or service == workspace
end
assert(visited == expectedVisibleServices)
assert(foundWorkspace)
assert(seen.CoreGui and seen.StarterGui)
assert(not seen.ScriptContext and not seen.StudioThemeService)
local descendants = game:GetDescendants()
visited = 0
for _, descendant in ipairs(descendants) do
    visited += 1
end
-- Workspace also contains its default camera.
assert(visited == expectedVisibleServices + 1)

local example = game:GetService("ExampleService")
assert(example:GetService("Workspace") == workspace)
assert(example:GetService("RunService") == game.RunService)
assert(example:GetService("MissingService") == nil)
`, "data_model_smoke")
    if !ok { fmt.eprintln(err); delete(err); panic("DataModel smoke test failed") }

    ok, err = vm.RunInternal(&script_vm, `
local count = 0
for _, service in ipairs(game:GetChildren()) do
    count += 1
    assert(service.Parent == game)
    assert(game:FindFirstChild(service.Name) == service)
    assert(game:GetService(service.Name) == service)
end
assert(count == expectedAllServices)
assert(game.CoreGui ~= game.StarterGui)
assert(game.CoreGui.Name == "CoreGui")
assert(game:FindFirstChild("Workspace") == workspace)
`, "data_model_internal_smoke")
    if !ok { fmt.eprintln(err); delete(err); panic("Internal DataModel smoke test failed") }

    vm.Close(&script_vm)
    engine_runtime.Environment_Destroy(&environment)
    fmt.println("DATA_MODEL_SMOKE_PASSED")
}
