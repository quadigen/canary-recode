package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("runtime API smoke test failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	run_script(&script_vm, `
assert(typeof(Enum.Material) == "Enum")
assert(typeof(Enum.Material.SmoothPlastic) == "EnumItem")
assert(tostring(Enum.Material) == "Enum.Material")
assert(tostring(Enum.Material.Wood) == "Enum.Material.Wood")
assert(Enum.Material.Wood.Name == "Wood")
assert(Enum.Material.Wood.Value == 1)
assert(Enum.Material.Wood.EnumType == Enum.Material)
assert(EnumItem.fromName(Enum.Material, "Wood") == Enum.Material.Wood)
assert(EnumItem.fromValue(Enum.Material, 1) == Enum.Material.Wood)
assert(#Enum.BorderMode:GetEnumItems() == 3)
assert(Enum.AccessoryType.Hat.Value == 1)

local part = Instance.new("Part")
assert(part.Material == Enum.Material.SmoothPlastic)
part.Material = Enum.Material.Neon
assert(part.Material == Enum.Material.Neon)
assert(not pcall(function() part.Material = Enum.BorderMode.Outline end))

local gui = Instance.new("GuiObject")
gui.Name = "AnimatedGui"
gui.BorderMode = Enum.BorderMode.Inset
assert(gui.BorderMode == Enum.BorderMode.Inset)
assert(gui.GuiState == Enum.GuiState.Idle)

local example = game:GetService("ExampleService")
assert(example == exampleService)
assert(example:Add(2, 3) == 5)
assert(example:Echo("hello") == "hello")
assert(example:MakeColor(0.25, 0.5, 0.75) == Color3.new(0.25, 0.5, 0.75))
assert(example.CallCount == 3)
assert(game:GetService("UserInputService").AccelerometerEnabled == false)

renderOrder = ""
renderSteps = 0
renderDelta = 0
renderGui = gui
local runService = game:GetService("RunService")
runService:BindToRenderStep("late", 20, function(deltaTime)
    renderOrder ..= "L"
    renderDelta = deltaTime
end)
runService:BindToRenderStep("gui", 10, function()
    renderOrder ..= "G"
    renderSteps += 1
    renderGui.ZIndex = renderGui.ZIndex + 1
end)
`, "runtime_api_setup")

	engine_runtime.Environment_Render_Step(&environment, &script_vm, 0.25)
	engine_runtime.Environment_Render_Step(&environment, &script_vm, 0.5)

	run_script(&script_vm, `
assert(renderOrder == "GLGL")
assert(renderSteps == 2 and renderGui.ZIndex == 2)
assert(math.abs(renderDelta - 0.5) < 1e-6)
game:GetService("RunService"):UnbindFromRenderStep("gui")
`, "runtime_api_verify")

	engine_runtime.Environment_Render_Step(&environment, &script_vm, 1.0)
	run_script(&script_vm, `
assert(renderOrder == "GLGLL")
assert(renderSteps == 2 and renderGui.ZIndex == 2)

snapshotOrder = ""
local runService = game:GetService("RunService")
runService:BindToRenderStep("remove-victim", 1, function()
    snapshotOrder ..= "R"
    runService:UnbindFromRenderStep("victim")
end)
runService:BindToRenderStep("victim", 2, function()
    snapshotOrder ..= "V"
end)
`, "runtime_api_unbind")

	engine_runtime.Environment_Render_Step(&environment, &script_vm, 1.0)
	engine_runtime.Environment_Render_Step(&environment, &script_vm, 1.0)
	run_script(&script_vm, `
assert(snapshotOrder == "RVR")
game:GetService("RunService"):UnbindFromRenderStep("remove-victim")
`, "runtime_api_snapshot")

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("RUNTIME_API_SMOKE_PASSED")
}
