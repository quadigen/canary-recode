package main

import assetstore "../src/engine/assetstore"
import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import vm "../src/engine/vm"
import "core:fmt"

run_script :: proc(script_vm: ^vm.VM, source: string) {
	ok, err := vm.Run(script_vm, source, "terrain_heightfield_smoke")
	defer delete(err)
	assert(ok, err)
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)
	defer {
		vm.Close(&script_vm)
		engine_runtime.Environment_Destroy(&environment)
		assetstore.Clear()
	}

	run_script(&script_vm, `
local terrain = game:GetService("Terrain")
local initialChildren = #workspace:GetChildren()
local function create(callback, spacing)
    return terrain:CreateHeightfield(Vector3.new(32, 4, -20), Vector2.new(48, 32),
        Enum.Material.Slate, callback, spacing)
end
assert(not pcall(create, function() error("height function failed") end))
assert(not pcall(create, function() return math.huge end))
assert(not pcall(create, function() return "not a height" end))
assert(not pcall(create, function() return 0 end, 0))
assert(not pcall(create, function() return 0 end, 0.01))
assert(#workspace:GetChildren() == initialChildren)

local calls = 0
local part = create(function(x, z)
    calls += 1
    local dx = math.max(math.abs(x) - 8, 0)
    local dz = math.max(math.abs(z) - 4, 0)
    local t = math.clamp(math.sqrt(dx * dx + dz * dz) / 8, 0, 1)
    return 12 * (1 - t * t * t * (t * (6 * t - 15) + 10))
end)
assert(calls == 49 * 33)
assert(part:IsA("MeshPart") and part.Anchored and part.Parent == workspace)
assert(part.Material == Enum.Material.Slate and part.CollisionFidelity == Enum.CollisionFidelity.TriangleMesh)
assert(terrain:CountCells() == 0)

saved = Instance.new("Model", workspace)
part.Parent = saved

function checkHeightfield(model)
    local heightfield = model:FindFirstChild("Heightfield")
    assert(heightfield.CollisionFidelity == Enum.CollisionFidelity.TriangleMesh)
    local function sample(x, z, expectedY)
        local hit = workspace:Raycast(Vector3.new(x, 32, z), Vector3.new(0, -40, 0))
        assert(hit and hit.Instance == heightfield)
        assert(math.abs(hit.Position.Y - expectedY) < 0.05, tostring(hit.Position))
        return hit.Normal
    end
    assert(sample(32, -20, 16).Y > 0.99)
    assert(sample(44, -20, 10).X > 0.5)
    assert(sample(52, -20, 4).Y > 0.99)
    assert(sample(32, -12, 10).Z > 0.5)
end
`)
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	run_script(&script_vm, "checkHeightfield(saved)")

	vm.GetGlobal(script_vm.L, "saved")
	root := classes.Object_From_Argument(script_vm.L, -1)
	vm.Pop(script_vm.L)
	parent := root.parent
	data, save_err := serializer.Serialize(&environment.classes, script_vm.L, root)
	assert(serializer.Error_Is_None(save_err))
	defer delete(data)
	run_script(&script_vm, "saved:Destroy()")
	assetstore.Clear()

	loaded, load_err := serializer.Deserialize(&environment.classes, script_vm.L, parent, data)
	assert(serializer.Error_Is_None(load_err) && loaded != nil)
	assert(assetstore.Count() == 1)
	classes.Push_Object(script_vm.L, loaded)
	vm.SetGlobalFromStack(&script_vm, "restored")
	engine_runtime.Environment_Update_Step(&environment, &script_vm, 1.0 / 60.0)
	run_script(&script_vm, "checkHeightfield(restored)")
	fmt.println("TERRAIN_HEIGHTFIELD_SMOKE_PASSED")
}
