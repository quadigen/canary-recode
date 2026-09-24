package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	source := `
local ok, err
ok, err = pcall(function()
	local a = Instance.new("Script", game:GetService("Workspace"))
	a.Source = "x"
	print("SCRIPT_PARENT_AND_SOURCE ok")
end)
print("script: ", ok, err)
ok, err = pcall(function()
	local a = Instance.new("ModuleScript", game:GetService("ReplicatedStorage"))
	a.Source = "return 1"
	print("MODULE_OK")
end)
print("module: ", ok, err)
ok, err = pcall(function()
	local a = Instance.new("LocalScript", game:GetService("ReplicatedStorage"))
	a.Source = "print('x')"
	print("LOCAL_OK")
end)
print("local: ", ok, err)
ok, err = pcall(function()
	local a = Instance.new("Script")
	a.Source = "x"
	a.Parent = game:GetService("Workspace")
	print("SCRIPT_LATE_PARENT_OK")
end)
print("script-late-parent: ", ok, err)
`

	ok, err := vm.Run(&script_vm, source, "probe")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("probe failed")
	}

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("PROBE_DONE")
}