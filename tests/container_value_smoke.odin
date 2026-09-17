package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("Container/value smoke test failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	run_script(&script_vm, `
-- Folder
local folder = Instance.new("Folder")
folder.Name = "MyFolder"
assert(folder.ClassName == "Folder")
assert(folder:IsA("Folder"))
assert(folder:IsA("Instance"))
assert(folder.Name == "MyFolder")
assert(folder.Parent == nil)

-- Folder children
local child1 = Instance.new("Part", folder)
child1.Name = "Part1"
local child2 = Instance.new("Part", folder)
child2.Name = "Part2"
assert(#folder:GetChildren() == 2)
assert(folder:GetChildren()[1] == child1)
assert(folder:GetChildren()[2] == child2)
assert(child1:IsDescendantOf(folder))
assert(folder:IsAncestorOf(child2))
assert(child1:GetFullName() == "MyFolder.Part1")

-- Destroy folder
folder:Destroy()
assert(#folder:GetChildren() == 0)
assert(child1.Parent == nil)
assert(child2.Parent == nil)

-- BoolValue
local bv = Instance.new("BoolValue")
bv.Name = "TestBool"
bv.Value = true
assert(bv.ClassName == "BoolValue")
assert(bv.Value == true)
bv.Value = false
assert(bv.Value == false)
assert(bv:IsA("BoolValue"))
assert(bv:IsA("ValueBase"))
assert(bv:IsA("Instance"))

-- NumberValue
local nv = Instance.new("NumberValue")
nv.Name = "TestNumber"
nv.Value = 42.5
assert(nv.ClassName == "NumberValue")
assert(nv.Value == 42.5)
nv.Value = -3.14
assert(nv.Value == -3.14)
assert(nv:IsA("NumberValue"))
assert(nv:IsA("ValueBase"))
assert(nv:IsA("Instance"))

-- Nested folder hierarchy
local root = Instance.new("Folder", workspace)
root.Name = "TestRoot"
local inner = Instance.new("Folder", root)
inner.Name = "Inner"
local deep = Instance.new("Folder", inner)
deep.Name = "Deep"
local leaf = Instance.new("Part", deep)
leaf.Name = "Leaf"

assert(leaf:GetFullName() == "game.Workspace.TestRoot.Inner.Deep.Leaf")
assert(root:FindFirstChild("Inner") == inner)
assert(inner:FindFirstChild("Deep") == deep)
assert(deep:FindFirstChild("Leaf") == leaf)
assert(root:IsDescendantOf(workspace))
assert(root:FindFirstChild("Inner"):FindFirstChild("Deep"):FindFirstChild("Leaf") == leaf)

local descendants = root:GetDescendants()
assert(#descendants == 3)
assert(descendants[1].Name == "Inner")
assert(descendants[2].Name == "Deep")
assert(descendants[3].Name == "Leaf")

-- Service traversal through workspace
assert(workspace:FindFirstChild("TestRoot") == root)

-- ModuleScript and Script
local module = Instance.new("ModuleScript")
module.Name = "TestModule"
assert(module.ClassName == "ModuleScript")
assert(module:IsA("ModuleScript"))
assert(module:IsA("Instance"))

local script = Instance.new("Script")
script.Name = "TestScript"
assert(script.ClassName == "Script")
assert(script:IsA("Script"))
assert(script:IsA("Instance"))

-- Value in GUI hierarchy
local gui = Instance.new("ScreenGui")
gui.Name = "ValueScreen"
local boolInGui = Instance.new("BoolValue", gui)
boolInGui.Name = "IsOpen"
boolInGui.Value = true
assert(gui:FindFirstChild("IsOpen") == boolInGui)
assert(boolInGui.Value == true)

-- Cloning
local original = Instance.new("Part")
original.Name = "Original"
original.Size = Vector3.new(1, 2, 3)
local cloned = original:Clone()
assert(cloned ~= original)
assert(cloned.Name == "Original")
assert(cloned:IsA("Part"))
original:Destroy()
assert(original.Parent == nil)

root:Destroy()
gui:Destroy()
`, "container_value_properties")

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("CONTAINER_VALUE_SMOKE_PASSED")
}
