package main

import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	source_vm := vm.New(); source: engine_runtime.Environment
	engine_runtime.Environment_Init(&source, &source_vm)
	defer {vm.Close(&source_vm); engine_runtime.Environment_Destroy(&source)}
	ok, err := vm.Run(
		&source_vm,
		`
local lighting = game:GetService("Lighting")
lighting.QualityPreset = Enum.QualityPreset.Ultra
lighting.DynamicResolution = true
lighting.ResolutionScale = 0.625
lighting.ShadowMapSize = 1024
local root=Instance.new("Folder",workspace);root.Name="AdvancedEffectRoundTrip"
for _,name in {"ReflectionProbeEffect","SSGIEffect","FogEffect","ScreenSpaceConeTracingEffect","TemporalAntiAliasingEffect","DynamicResolutionEffect","ToneMappingEffect","SkyLightEffect","LensFlareEffect","ColorGradingEffect","SunLightEffect","AmbientOcclusionDetailEffect","SunRaysEffect"} do
    local effect=Instance.new(name,root)
    assert(effect.Enabled and effect.CanReplicate)
end
root.ReflectionProbeEffect.Position=Vector3.new(4,5,6)
root.ReflectionProbeEffect.AutoPosition=false
root.ReflectionProbeEffect.Resolution=256
root.SSGIEffect.SampleCount=24;root.SSGIEffect.Intensity=0.75
root.FogEffect.Color=Color3.new(0.25,0.5,0.75)
root.ScreenSpaceConeTracingEffect.ShadowDistance=7
root.TemporalAntiAliasingEffect.Feedback=0.3
root.DynamicResolutionEffect.MinScale=0.8
root.ToneMappingEffect.Mode=2;root.ToneMappingEffect.ExposureCompensation=0.5
root.SkyLightEffect.Intensity = 0.5
root.LensFlareEffect.Starburst = false
root.LensFlareEffect.GhostCount = 3.9
root.ColorGradingEffect.Shadows = Color3.new(0.5, 0.75, 1)
assert(root.ColorGradingEffect:Clone().Shadows == root.ColorGradingEffect.Shadows)
assert(not root.LensFlareEffect:Clone().Starburst)
assert(not pcall(function() root.SkyLightEffect.Intensity = math.huge end))
assert(root.SkyLightEffect.Intensity == 0.5)
root.SunLightEffect.Azimuth = -270
root.SunLightEffect.Elevation = 30
root.SunLightEffect.Color = Color3.new(1, 0.5, 0.25)
root.AmbientOcclusionDetailEffect.BentNormals = false
root.AmbientOcclusionDetailEffect.FilterQuality = 2.75
assert(root.SunLightEffect.Azimuth == 90)
assert(root.AmbientOcclusionDetailEffect.FilterQuality == 2)
local rays = root.SunRaysEffect
rays.DustAmount = 0.75
rays.MaxDistance = 36
rays.SampleCount = 32.5
assert(rays.SampleCount == 32 and rays:Clone().DustAmount == 0.75)
assert(not pcall(function() rays.MaxDistance = math.huge end))
`,
		"advanced_effect_serialize_setup",
	); assert(ok, err)
	failure := serializer.Serialize_To_File(
		&source.classes,
		source_vm.L,
		&source.services.data_model.object,
		"build/advanced-effects.kine",
	)
	assert(
		serializer.Error_Is_None(failure),
		serializer.Error_String(failure),
	); serializer.Error_Delete(&failure)
	client_vm := vm.New(); client: engine_runtime.Environment
	engine_runtime.Environment_Init(&client, &client_vm)
	defer {vm.Close(&client_vm); engine_runtime.Environment_Destroy(&client)}
	assert(engine_runtime.Load_Map(&client, &client_vm, "build/advanced-effects.kine"))
	ok, err = vm.Run(
		&client_vm,
		`
local lighting = game:GetService("Lighting")
assert(lighting.QualityPreset == Enum.QualityPreset.Ultra)
lighting.QualityPreset = Enum.QualityPreset.Custom
assert(lighting.DynamicResolution and lighting.ResolutionScale == 0.625 and lighting.ShadowMapSize == 1024)
local root=workspace.AdvancedEffectRoundTrip
assert(root and #root:GetChildren()==13)
for _,effect in root:GetChildren() do assert(effect:IsA("LightingEffect") and effect.Enabled) end
assert(root.ReflectionProbeEffect.Position==Vector3.new(4,5,6))
assert(root.ReflectionProbeEffect.AutoPosition==false and root.ReflectionProbeEffect.Resolution==256)
assert(root.SSGIEffect.SampleCount==24 and root.SSGIEffect.Intensity==0.75)
assert(root.FogEffect.Color==Color3.new(0.25,0.5,0.75))
assert(root.ScreenSpaceConeTracingEffect.ShadowDistance==7)
assert(math.abs(root.TemporalAntiAliasingEffect.Feedback-0.3)<0.0001)
assert(math.abs(root.DynamicResolutionEffect.MinScale-0.8)<0.0001)
assert(root.ToneMappingEffect.Mode==2 and root.ToneMappingEffect.ExposureCompensation==0.5)
assert(root.SkyLightEffect.Intensity == 0.5)
assert(not root.LensFlareEffect.Starburst and root.LensFlareEffect.GhostCount == 3)
assert(root.ColorGradingEffect.Shadows == Color3.new(0.5, 0.75, 1))
assert(root.SunLightEffect.Azimuth == 90 and root.SunLightEffect.Elevation == 30)
assert(root.SunLightEffect.Color == Color3.new(1, 0.5, 0.25))
assert(root.AmbientOcclusionDetailEffect.FullResolution)
assert(not root.AmbientOcclusionDetailEffect.BentNormals)
assert(root.AmbientOcclusionDetailEffect.FilterQuality == 2)

assert(root.SunRaysEffect.DustAmount == 0.75)
assert(root.SunRaysEffect.MaxDistance == 36 and root.SunRaysEffect.SampleCount == 32)

local clockDirection = lighting:GetSunDirection()
local sun = root.SunLightEffect:Clone()
sun.Parent = lighting
local direction = lighting:GetSunDirection()
assert((direction - Vector3.new(0, 0.5, math.sqrt(3) / 2)).Magnitude < 0.0001)
sun.Enabled = false
assert(lighting:GetSunDirection() == clockDirection)
`,
		"advanced_effect_serialize_check",
	); assert(ok, err)
	fmt.println("ADVANCED_LIGHTING_SERIALIZATION_PASSED")
}
