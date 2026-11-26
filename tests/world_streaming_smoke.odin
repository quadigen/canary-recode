package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)
	ok, err := vm.RunInternal(
		&script_vm,
		`
local ws = workspace
assert(#ws:GetUnloadedRegions() == 0)
local region = Instance.new("Model", ws)
region.Name = "SectorA"
region:SetAttribute("Biome", "Desert")
local part = Instance.new("Part", region)
part.Name = "Arch"
part.Anchored = true
part.CanCollide = true
part.Size = Vector3.new(8, 10, 2)
part.Position = Vector3.new(72, 20, 18)
assert(not pcall(function() ws:UnloadRegion(ws) end))
assert(ws:UnloadRegion(region))
assert(ws:FindFirstChild("SectorA") == nil)
assert(#ws:GetUnloadedRegions() == 1 and ws:GetUnloadedRegions()[1] == "SectorA")
assert(not pcall(function() ws:UnloadRegion(region) end))
local conflict = Instance.new("Model", ws)
conflict.Name = "SectorA"
assert(not pcall(function() ws:LoadRegion("SectorA") end))
assert(#ws:GetUnloadedRegions() == 1)
conflict:Destroy()
local restored = ws:LoadRegion("SectorA")
assert(restored ~= nil and restored:IsA("Model"))
assert(restored.Name == "SectorA" and restored.Parent == ws)
assert(restored:GetAttribute("Biome") == "Desert")
local arch = restored:FindFirstChild("Arch")
assert(arch ~= nil and arch:IsA("Part"))
assert(arch.Anchored and arch.CanCollide)
assert(arch.Size == Vector3.new(8, 10, 2))
assert(arch.Position == Vector3.new(72, 20, 18))
assert(#ws:GetUnloadedRegions() == 0)
assert(not pcall(function() ws:LoadRegion("SectorA") end))
assert(ws:UnloadRegion(restored))
local restoredAgain = ws:LoadRegion("SectorA")
assert(restoredAgain ~= nil and restoredAgain:FindFirstChild("Arch") ~= nil)
restoredAgain:Destroy()
`,
		"world_streaming",
	)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("world region streaming smoke failed")
	}
	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("WORLD_STREAMING_SMOKE_PASSED")
}
