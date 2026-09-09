package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	source := `
local module = Instance.new("ModuleScript")
module.Name = "CounterModule"
module.Source = [[
    _G.moduleRuns = (_G.moduleRuns or 0) + 1
    return {owner = script, runs = _G.moduleRuns}
]]

local first = require(module)
local second = require(module)
assert(first == second)
assert(first.owner == module and first.runs == 1 and _G.moduleRuns == 1)
assert(script == nil)

module.Source = "return {owner = script, changed = true}"
local changed = require(module)
assert(changed ~= first and changed.owner == module and changed.changed)

local regularScript = Instance.new("Script")
regularScript.Source = "return script.ClassName"
assert(require(regularScript) == "Script")

local folder = Instance.new("Model")
local outer = Instance.new("ModuleScript", folder)
outer.Name = "Outer"
local inner = Instance.new("ModuleScript", folder)
inner.Name = "Inner"
inner.Source = "return script.Name"
outer.Source = [[
    local innerResult = require(script.Parent:FindFirstChild("Inner"))
    return {inner = innerResult, restored = script.Name}
]]
local nested = require(outer)
assert(nested.inner == "Inner" and nested.restored == "Outer")

local cycleA = Instance.new("ModuleScript", folder)
local cycleB = Instance.new("ModuleScript", folder)
cycleA.Name, cycleB.Name = "CycleA", "CycleB"
cycleA.Source = "return require(script.Parent:FindFirstChild('CycleB'))"
cycleB.Source = "return require(script.Parent:FindFirstChild('CycleA'))"
assert(not pcall(require, cycleA))

local instance = Instance.new("Part")
instance:SetAttribute("Health", 100)
instance:SetAttribute("Title", "Ready")
instance:SetAttribute("Tint", Color3.fromRGB(10, 20, 30))
instance:SetAttribute("Offset", vector.create(1, 2, 3))
assert(instance:GetAttribute("Health") == 100)
assert(instance:GetAttribute("Missing") == nil)
local attributes = instance:GetAttributes()
assert(attributes.Health == 100 and attributes.Title == "Ready")
assert(typeof(attributes.Tint) == "Color3" and attributes.Offset == vector.create(1, 2, 3))
instance:SetAttribute("Health", nil)
assert(instance:GetAttribute("Health") == nil)
assert(not pcall(function() instance:SetAttribute("bad name", 1) end))
assert(not pcall(function() instance:SetAttribute("RBXPrivate", 1) end))
assert(not pcall(function() instance:SetAttribute("Table", {}) end))
assert(not pcall(function() instance:SetAttribute("Object", Instance.new("Part")) end))

assert(typeof(instance.UniqueId) == "UniqueId")
assert(#tostring(instance.UniqueId) == 32)
assert(instance.UniqueId ~= Instance.new("Part").UniqueId)
assert(instance.UniqueId ~= UniqueId.new())
assert(not pcall(function() instance.UniqueId = UniqueId.new() end))

local basic = SecurityCapabilities.new(Enum.SecurityCapability.Basic)
local expanded = basic:Add(Enum.SecurityCapability.UI, Enum.SecurityCapability.Physics)
assert(typeof(basic) == "SecurityCapabilities")
assert(not basic:Contains(Enum.SecurityCapability.UI))
assert(expanded:Contains(Enum.SecurityCapability.Basic, Enum.SecurityCapability.UI))
assert(expanded:Remove(Enum.SecurityCapability.UI) == SecurityCapabilities.new(
    Enum.SecurityCapability.Basic,
    Enum.SecurityCapability.Physics
))
assert(SecurityCapabilities.fromCurrent():Contains(Enum.SecurityCapability.Network))
assert(SecurityCapabilities.new(Enum.SecurityCapability.UnreliableRemoteEvent):Contains(
    Enum.SecurityCapability.UnreliableRemoteEvent
))

instance.Capabilities = expanded
instance.Sandboxed = true
local child = Instance.new("Model", instance)
assert(instance.Capabilities == expanded)
assert(instance.IsInSandbox and child.IsInSandbox)
assert(not Instance.new("Model").IsInSandbox)
`

	ok, err := vm.Run(&script_vm, source, "instance_script_attribute_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("Instance Script/attribute smoke test failed")
	}

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("INSTANCE_SCRIPT_ATTRIBUTE_SMOKE_PASSED")
}
