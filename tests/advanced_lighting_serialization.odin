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
local root=Instance.new("Folder",workspace);root.Name="AdvancedEffectRoundTrip"
for _,name in {"ReflectionProbeEffect","SSGIEffect","FogEffect","ScreenSpaceConeTracingEffect","TemporalAntiAliasingEffect","DynamicResolutionEffect","ToneMappingEffect"} do
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
local root=workspace.AdvancedEffectRoundTrip
assert(root and #root:GetChildren()==7)
for _,effect in root:GetChildren() do assert(effect:IsA("LightingEffect") and effect.Enabled) end
assert(root.ReflectionProbeEffect.Position==Vector3.new(4,5,6))
assert(root.ReflectionProbeEffect.AutoPosition==false and root.ReflectionProbeEffect.Resolution==256)
assert(root.SSGIEffect.SampleCount==24 and root.SSGIEffect.Intensity==0.75)
assert(root.FogEffect.Color==Color3.new(0.25,0.5,0.75))
assert(root.ScreenSpaceConeTracingEffect.ShadowDistance==7)
assert(math.abs(root.TemporalAntiAliasingEffect.Feedback-0.3)<0.0001)
assert(math.abs(root.DynamicResolutionEffect.MinScale-0.8)<0.0001)
assert(root.ToneMappingEffect.Mode==2 and root.ToneMappingEffect.ExposureCompensation==0.5)
`,
		"advanced_effect_serialize_check",
	); assert(ok, err)
	fmt.println("ADVANCED_LIGHTING_SERIALIZATION_PASSED")
}
