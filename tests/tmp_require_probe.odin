package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

main :: proc() {
	script_vm := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm)
	src := `
local s = Instance.new("Script")
s.Source = "return 1"
local okScript, errScript = pcall(function() return require(s) end)
print("require(Script) ok=", okScript, " err=", tostring(errScript))
local m = Instance.new("ModuleScript")
m.Source = "return 7"
print("require(ModuleScript)=", require(m))
local n = Instance.new("ModuleScript")
n.Name = "Nm"
n.Source = "return script.Name"
print("mod script name=", require(n))
print("global require type=", type(require))
`
	ok, err := vm.Run(&script_vm, src, "probe")
	if !ok {fmt.eprintln(err)}
	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&env)
}
