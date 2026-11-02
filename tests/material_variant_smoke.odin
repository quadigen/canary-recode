package main

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

run :: proc(script_vm: ^vm.VM, source: string) {
	ok, err := vm.Run(script_vm, source, "material_variant_smoke")
	assert(ok, err)
}

main :: proc() {
	script_vm := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm)
	defer {vm.Close(&script_vm); engine_runtime.Environment_Destroy(&env)}
	run(
		&script_vm,
		`
root = Instance.new("Model", workspace)
variant = Instance.new("MaterialVariant", root)
variant.Name = "Copper"
assert(variant.Enabled and not variant.Compiled and variant.LastError == "")
assert(variant.HeightMap == "" and variant.HeightScale == 0 and variant.HeightMidlevel == 0.5)
assert(variant.ParallaxDepth == 0 and variant.NormalStrength == 1 and variant.AOStrength == 1)
assert(variant.DisplacementSubdivisions == 2)
variant.HeightScale = 0.25
variant.HeightMidlevel = 0.3
variant.ParallaxDepth = 0.15
variant.ParallaxSteps = 999
variant.NormalStrength = 0.75
variant.DisplacementSubdivisions = 99
variant.DisplacementBounds = 1.5
variant.AOStrength = 0.5
variant.EmissiveColor = Color3.new(1,0.5,0.25)
variant.EmissiveStrength = 2
variant.VertexSource = "material.worldPosition.y += 0.1;"
variant.FragmentSource = "material.baseColor.rgb *= 0.5;"
assert(variant.ParallaxSteps == 64 and variant.DisplacementSubdivisions == 4)
assert(not pcall(function() variant.HeightScale = math.huge end))
assert(string.find(variant.Source, "void material", 1, true))
variant.Color = Color3.new(0.75, 0.25, 0.125)
variant.Roughness = 0.25
variant.Metalness = 2
assert(variant.Roughness == 0.25 and variant.Metalness == 1)
variant:SetUniform("customVector", {1, 2, 3})
local v = variant:GetUniform("customVector")
assert(v[1] == 1 and v[3] == 3)
assert(variant:GetUniform("missing") == nil)
assert(not pcall(function() variant:SetUniform("bad", {}) end))
assert(not pcall(function() variant:SetUniform("bad", {1,2,3,4,5}) end))
assert(not pcall(function() variant.Compiled = true end))
part = Instance.new("Part", root)
part.MaterialVariant = "Copper"
local mesh = Instance.new("MeshPart", root)
mesh.MaterialVariant = "Copper"
assert(part:Clone().MaterialVariant == "Copper")
assert(mesh:Clone().MaterialVariant == "Copper")
game:GetService("Terrain").MaterialVariant = "Copper"
assert(game:GetService("Terrain").MaterialVariant == "Copper")
copy = variant:Clone()
assert(copy.Source == variant.Source and copy.Color == variant.Color)
assert(copy.FragmentSource == variant.FragmentSource and copy.VertexSource == variant.VertexSource)
assert(copy.HeightScale == 0.25 and copy.DisplacementBounds == 1.5 and copy.EmissiveStrength == 2)
assert(copy:GetUniform("customVector")[3] == 3)
variant.Source = string.rep("temporary source ", 100)
collectgarbage("collect")
assert(#variant.Source == 1700)
assert(copy.Source ~= variant.Source)
variant.Source = copy.Source
copy:Destroy()
effect = Instance.new("PostProcess", root)
assert(effect.Enabled)
effect.Source = string.rep("post source ", 100)
effect:SetUniform("strength", 0.5)
local clone = effect:Clone()
effect:Destroy()
collectgarbage("collect")
assert(#clone.Source == 1200 and clone:GetUniform("strength") == 0.5)
clone.Parent = root
`,
	)
	vm.GetGlobal(script_vm.L, "root")
	root := classes.Object_From_Argument(script_vm.L, -1)
	vm.Pop(script_vm.L)
	terrain := cast(^services.Terrain)services.Ensure_Service(&env.services, "Terrain")
	terrain_table: serializer.Kine_Terrain
	services.Terrain_Write_Kine_Table(terrain, &terrain_table)
	defer serializer.Kine_Terrain_Destroy(&terrain_table)
	data, err := serializer.Serialize(&env.classes, script_vm.L, root, terrain = &terrain_table)
	assert(serializer.Error_Is_None(err), "material serialization failed")
	defer delete(data)
	loaded_terrain: serializer.Kine_Terrain
	defer serializer.Kine_Terrain_Destroy(&loaded_terrain)
	loaded, load_err := serializer.Deserialize_From_Data(
		&env.classes,
		script_vm.L,
		nil,
		data,
		&loaded_terrain,
	)
	if !serializer.Error_Is_None(load_err) {fmt.eprintln(serializer.Error_String(load_err))}
	assert(serializer.Error_Is_None(load_err), "material deserialization failed")
	assert(loaded_terrain.material_variant == "Copper")
	assert(services.Terrain_Read_Kine_Table(terrain, nil, &loaded_terrain))
	classes.Push_Object(script_vm.L, loaded)
	vm.SetGlobalFromStack(&script_vm, "loaded")
	run(
		&script_vm,
		`
local v = loaded:FindFirstChild("Copper")
assert(v.Source == variant.Source)
assert(v.Color == variant.Color and v.Roughness == 0.25 and v.Metalness == 1)
assert(v.VertexSource == variant.VertexSource and v.FragmentSource == variant.FragmentSource)
assert(v.HeightScale == 0.25 and v.ParallaxSteps == 64 and v.DisplacementSubdivisions == 4)
assert(v.NormalStrength == 0.75 and v.AOStrength == 0.5 and v.EmissiveColor == variant.EmissiveColor)
assert(loaded:FindFirstChild("Part").MaterialVariant == "Copper")
assert(loaded:FindFirstChild("PostProcess").Enabled)
assert(not v.Compiled and v.LastError == "")
root:Destroy()
loaded:Destroy()
`,
	)
	classes.Step(&env.classes, script_vm.L, 0, phase = .Render_3D)
	fmt.println("MATERIAL_VARIANT_SMOKE_PASSED")
}
