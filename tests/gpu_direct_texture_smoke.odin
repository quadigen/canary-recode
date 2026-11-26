package main

import k "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:time"
import sdl "vendor:sdl3"

run :: proc(script_vm: ^vm.VM, source: string) {
	ok, err := vm.Run(script_vm, source, "material_shader_render_smoke")
	assert(ok, err)
}

render_assets_pending :: proc(env: ^engine_runtime.Environment) -> bool {
	for object in classes.Find_Class(&env.classes, "MaterialVariant").instances {
		if !object.destroyed &&
		   (cast(^classes.MaterialVariant)object).compile_job != nil {return true}
	}
	for object in classes.Find_Class(&env.classes, "PostProcess").instances {
		if !object.destroyed && (cast(^classes.PostProcess)object).compile_job != nil {return true}
	}
	terrain := cast(^services.Terrain)services.Ensure_Service(&env.services, "Terrain")
	return terrain.mesh_batch != nil || len(terrain.dirty_queue) != 0
}

capture :: proc(
	env: ^engine_runtime.Environment,
	script_vm: ^vm.VM,
	x: i32 = 160,
	y: i32 = 120,
) -> [4]u8 {
	filament := env.renderer.Filament
	compositor := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(filament)
	result: [4]u8
	for frame in 0 ..< 600 {
		services.Prepare_3D(&env.services, env.renderer)
		base := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(compositor)
		assert(base != nil)
		k.Kine_Skia_Surface_Clear(base, 20, 30, 40, 255)
		engine_runtime.Environment_Render_2D(env, script_vm, base, 320, 240, 1.0 / 60.0)
		engine_runtime.Environment_Render_3D(env, script_vm, 1.0 / 60.0)
		k.Kine_Filament_RenderFrame(filament, 1.0 / 60.0)
		overlay := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginOverlay(compositor)
		assert(overlay != nil)
		engine_runtime.Environment_Render_Overlay(env, script_vm, overlay, 320, 240, 1.0 / 60.0)
		k.Kine_Skia_Surface_GetPixel(overlay, x, y, &result[0], &result[1], &result[2], &result[3])
		assert(k.Kine_VulkanCompositor_EndFrame(compositor) != 0)
		if frame >= 2 && !render_assets_pending(env) {
			fmt.println("Shader pixel:", result)
			return result
		}
		time.sleep(time.Millisecond)
	}
	panic("Timed out waiting for material or terrain preparation")
}

main :: proc() {
	assert(sdl.Init({.VIDEO})); defer sdl.Quit()
	window := sdl.CreateWindow(
		"Direct compute texture smoke",
		320,
		240,
		sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN,
	)
	assert(window != nil); defer sdl.DestroyWindow(window)
	filament := k.Kine_Filament_CreateForVulkanCompositorWindow(window, 320, 240)
	assert(filament != nil); defer k.Kine_Filament_Destroy(filament)
	renderer_object := renderer.RendererObject {
		Filament = filament,
	}
	script_vm := vm.New(); env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm, &renderer_object)
	defer {vm.Close(&script_vm); engine_runtime.Environment_Destroy(&env)}
	run(
		&script_vm,
		`
variant=Instance.new("MaterialVariant",workspace);variant.Name="Computed"
variant.Source=[[material { name: "ComputeOutput", shadingModel: unlit, requires: [uv0], instanced: true,
parameters: [{type:sampler2d,name:computedMap}] }
fragment { void material(inout MaterialInputs material) {
prepareMaterial(material);material.baseColor=texture(materialParams_computedMap,getUV0());
} }]]
local part=Instance.new("Part",workspace);part.Size=Vector3.new(3,3,3);part.MaterialVariant="Computed"
workspace.CurrentCamera.CFrame=CFrame.new(0,0,8);workspace.CurrentCamera.FieldOfView=45
for _,effect in game:GetService("Lighting"):GetChildren() do if effect:IsA("LightingEffect") then effect.Enabled=false end end
compute=Instance.new("GPUCompute")
redShader=[[#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(rgba8,set=0,binding=0) uniform writeonly image2D outputImage;
void main(){ivec2 p=ivec2(gl_GlobalInvocationID.xy);if(all(lessThan(p,imageSize(outputImage))))imageStore(outputImage,p,vec4(1,0,0,1));}]]
greenShader=string.gsub(redShader,"vec4%(1,0,0,1%)","vec4(0,1,0,1)")
`,
	)
	shader: ^k.KineFilamentShader
	for _ in 0 ..< 5000 {
		shader, _ = classes.MaterialVariant_Resolve(&env.classes, "Computed", filament)
		if shader != nil {break}; time.sleep(time.Millisecond)
	}
	assert(shader != nil, "compute target material did not compile")
	run(
		&script_vm,
		`
local ok,err=compute:DispatchTexture(variant,"computedMap",redShader,64,64);assert(ok,err)
local bad,badErr=compute:DispatchTexture(variant,"missingMap",redShader,64,64);assert(not bad and badErr)
local invalid=string.gsub(redShader,"local_size_x=8","local_size_x=4")
local rejected,why=compute:DispatchTexture(variant,"computedMap",invalid,64,64);assert(not rejected and why)
`,
	)
	red := capture(&env, &script_vm)
	assert(red[0] > red[1] + 50 && red[0] > red[2] + 50, "GPU output was not sampled red")
	run(
		&script_vm,
		`local ok,err=compute:DispatchTexture(variant,"computedMap",greenShader,64,64);assert(ok,err)`,
	)
	green := capture(&env, &script_vm)
	assert(
		green[1] > green[0] + 50 && green[1] > green[2] + 50,
		"GPU output did not update to green",
	)
	run(
		&script_vm,
		`
local before=compute:GetCacheStats()
local ok,err=compute:DispatchTexture(variant,"computedMap",greenShader,64,64);assert(ok,err)
local after=compute:GetCacheStats();assert(after.Hits>before.Hits)
assert(after.DirectTextureDispatches==3 and after.PixelReadbackBytes==0 and after.PixelUploadBytes==0)
assert(after.DirectTextureBytes==64*64*4)
local source=[[#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) buffer Data {float values[];};
void main(){values[gl_GlobalInvocationID.x]=1.0;}]]
local tickets={};for i=1,16 do tickets[i]=assert(compute:QueuePipeline(source,1)) end
local overflow,reason=compute:QueuePipeline(source,1);assert(not overflow and reason)
assert(compute:GetWarmupPendingCount()==16)
local warmed=compute:WarmupPipelines(1);assert(#warmed==1 and warmed[1].Ticket==tickets[1] and warmed[1].Pipeline)
assert(compute:GetWarmupPendingCount()==15)
print("GPU_DIRECT_STATS",after.DirectTextureDispatches,after.DirectTextureBytes,after.PixelReadbackBytes,after.PixelUploadBytes,after.Hits)
`,
	)
	fmt.println("GPU_DIRECT_TEXTURE_SMOKE_PASSED", red, green)
}
