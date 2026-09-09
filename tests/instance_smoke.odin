package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

main :: proc() {
	script_vm := vm.New()
	vm.PushNumber(script_vm.L, 12.5)
	vm.PushValue(script_vm.L, -1)
	assert(vm.StackTop(script_vm.L) == 2)
	assert(vm.ArgNumber(script_vm.L, -1) == 12.5)
	vm.Pop(script_vm.L, 2)

	vm.NewTable(script_vm.L, 0, 1)
	vm.PushString(script_vm.L, "value")
	vm.SetField(script_vm.L, -2, "key")
	assert(vm.GetField(script_vm.L, -1, "key") == .String)
	assert(vm.ArgString(script_vm.L, -1) == "value")
	vm.Pop(script_vm.L, 2)

	vm.AddGlobal_Number(&script_vm, "NativeNumber", 42)
	native_number, has_native_number := vm.GetGlobalNumber(&script_vm, "NativeNumber")
	assert(has_native_number && native_number == 42)

	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	source := `
local root = Instance.new("Instance")
root.Name = "Root"

local part = Instance.new("Part", root)
part.Name = "Block"
part.Anchored = true
part.Transparency = 25

assert(part.ClassName == "Part")
assert(part.Name == "Block")
assert(part.Anchored == true)
assert(part.Transparency == 25)
assert(part:IsA("Part"))
assert(part:IsA("Instance"))
assert(part:IsA("Object"))
assert(part:IsDescendantOf(root))
assert(root:IsAncestorOf(part))
assert(root:FindFirstChild("Block") == part)
assert(root:GetChildren()[1] == part)
assert(root:GetDescendants()[1] == part)
assert(part:GetFullName() == "Root.Block")

local detachedMethod = part.IsA
assert(detachedMethod(part, "Instance"))

assert(game:GetService("Workspace") == workspace)
assert(game:FindService("Missing") == nil)
assert(workspace:IsA("Service"))
assert(_KINEMIUM_VERSION == "0.1.0-odin")
assert(NativeNumber == 42)

local ok = pcall(function()
    Instance.new("Workspace")
end)
assert(not ok)

root:Destroy()
assert(#root:GetChildren() == 0)
assert(part.Parent == nil)
`

	ok, err := vm.Run(&script_vm, source, "instance_smoke")
	if !ok {
		fmt.eprintln(err)
		vm.Close(&script_vm)
		engine_runtime.Environment_Destroy(&environment)
		panic("instance smoke test failed")
	}

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("INSTANCE_SYSTEM_SMOKE_PASSED")
}
