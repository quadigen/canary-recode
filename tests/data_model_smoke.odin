package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	visible_count := 0
	for service in environment.services.services {
		assert(service.object != nil)
		assert(service.object.parent == &environment.services.data_model.object)
		assert(service.object.name == service.name)
		if vm.SecurityRequirementIsNone(service.security) {visible_count += 1}
	}
	vm.AddGlobal_Number(&script_vm, "expectedVisibleServices", f64(visible_count))
	vm.AddGlobal_Number(&script_vm, "expectedAllServices", f64(len(environment.services.services)))

	ok, err := vm.Run(
		&script_vm,
		`
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
for index, service in ipairs(children) do
    if not service:IsA("Service") then
        assert(service.Name == "ProfilerOverlay" and service:IsA("Script") and service.Parent == game)
        continue
    end
    visited += 1
    assert(service.Parent == game, "incorrect parent at index " .. index .. " for " .. tostring(service) .. "/" .. tostring(service.Name) .. ": " .. tostring(service.Parent))
    assert(not seen[service.Name], "duplicate service " .. tostring(service.Name))
    seen[service.Name] = true
    assert(game:GetService(service.Name) == service, "identity mismatch for " .. tostring(service.Name))
    foundWorkspace = foundWorkspace or service == workspace
end
assert(visited == expectedVisibleServices, "visible count: " .. visited .. " expected " .. expectedVisibleServices)
assert(foundWorkspace)
assert(seen.CoreGui and seen.StarterGui)
assert(not seen.ScriptContext and not seen.PlaytestService and not seen.ExportService)
assert(seen.StudioThemeService)
local filesystem = game:GetService("Filesystem")
assert(filesystem.Name == "Filesystem" and filesystem.Parent == game)
assert(filesystem.MissingProperty == nil)
-- Compare descendant enumeration to an independently recursive child walk.
local expectedDescendants = {}
local function walk(parent)
    for _, child in ipairs(parent:GetChildren()) do
        assert(child.Parent == parent)
        assert(not expectedDescendants[child], "duplicate child in hierarchy")
        expectedDescendants[child] = true
        walk(child)
    end
end
walk(game)
for _, descendant in ipairs(game:GetDescendants()) do
    assert(expectedDescendants[descendant], "unexpected or duplicate descendant: " .. tostring(descendant))
    expectedDescendants[descendant] = nil
end
assert(next(expectedDescendants) == nil, "descendants omitted from enumeration")
assert(workspace.CurrentCamera and workspace.CurrentCamera.Parent == workspace)

local example = game:GetService("ExampleService")
assert(example:GetService("Workspace") == workspace)
assert(example:GetService("RunService") == game.RunService)
assert(example:GetService("MissingService") == nil)
`,
		"data_model_smoke",
	)
	if !ok {fmt.eprintln(err); delete(err); panic("DataModel smoke test failed")}

	ok, err = vm.RunInternal(
		&script_vm,
		`
local count = 0
for _, service in ipairs(game:GetChildren()) do
    if not service:IsA("Service") then
        assert(service.Name == "ProfilerOverlay" and service:IsA("Script") and service.Parent == game)
        continue
    end
    count += 1
    assert(service.Parent == game, "incorrect parent for " .. tostring(service.Name) .. ": " .. tostring(service.Parent))
    assert(game:FindFirstChild(service.Name) == service)
    assert(game:GetService(service.Name) == service, "identity mismatch for " .. tostring(service.Name))
end
assert(count == expectedAllServices, "internal count: " .. count .. " expected " .. expectedAllServices)
assert(game.CoreGui ~= game.StarterGui)
assert(game.CoreGui.Name == "CoreGui")
assert(game:FindFirstChild("Workspace") == workspace)
`,
		"data_model_internal_smoke",
	)
	if !ok {fmt.eprintln(err); delete(err); panic("Internal DataModel smoke test failed")}

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("DATA_MODEL_SMOKE_PASSED")
}
