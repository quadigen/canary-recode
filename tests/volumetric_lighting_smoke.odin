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
	ok, err := vm.Run(script_vm, source, "volumetric_lighting_smoke")
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
	settled := 0
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
		if !render_assets_pending(env) {settled += 1} else {settled = 0}
		if settled >= 5 {
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
		"Volumetric lighting",
		320,
		240,
		sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN,
	)
	assert(window != nil); defer sdl.DestroyWindow(window)
	filament := k.Kine_Filament_CreateForVulkanCompositorWindow(window, 320, 240)
	assert(filament != nil); defer k.Kine_Filament_Destroy(filament)
	view := renderer.RendererObject {
		Filament = filament,
	}
	state := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &state, &view)
	defer {vm.Close(&state); engine_runtime.Environment_Destroy(&env)}
	run(
		&state,
		`
local l = game:GetService("Lighting")
for _,effect in l:GetChildren() do if effect:IsA("LightingEffect") then effect.Enabled=false end end
for _,name in {"VolumetricFogEffect", "ChromaticAberrationEffect", "FilmGrainEffect"} do
    local e=l:FindFirstChild(name)
    assert(e and not e.Enabled and e:IsA("LightingEffect"))
    local clone=e:Clone(); assert(clone:IsA(name)); clone:Destroy()
end
fog = l.VolumetricFogEffect
fog.StepCount=100; assert(fog.StepCount==64)
fog.StepCount=16
fog.Density=-2; assert(fog.Density==0)
fog.Density=0.5;fog.Height=10;fog.HeightFalloff=0;fog.NoiseStrength=0;fog.Scattering=0;fog.Color=Color3.new(1,0,0)
workspace.CurrentCamera.CameraType=Enum.CameraType.Scriptable
workspace.CurrentCamera.CFrame=CFrame.new(0,0,10)
local p=Instance.new("Part",workspace)
p.Anchored=true;p.Size=Vector3.new(4,4,2);p.Color=Color3.new(0,1,0)
`,
	)
	baseline := capture(&env, &state)
	run(&state, `fog.Enabled=true`)
	fogged := capture(&env, &state)
	fmt.println("FOG", baseline, fogged)
	assert(
		fogged[0] > baseline[0] + 15 && fogged[1] < baseline[1] - 10,
		"volumetric fog must affect pixels",
	)
	enabled: bool; values: [16]f32
	assert(
		k.Kine_Filament_GetAdvancedEffect(filament, 7, &enabled, &values[0], 16) &&
		enabled &&
		values[8] == 16,
	)
	run(&state, `fog.Enabled=false`)
	restored := capture(&env, &state)
	assert(
		abs(int(restored[0]) - int(baseline[0])) < 8 &&
		abs(int(restored[1]) - int(baseline[1])) < 8,
	)
	run(
		&state,
		`
local l=game:GetService("Lighting")
l.ChromaticAberrationEffect.Enabled=true;l.ChromaticAberrationEffect.Intensity=0.7
l.FilmGrainEffect.Enabled=true;l.FilmGrainEffect.Intensity=0.3
`,
	)
	_ = capture(&env, &state)
	assert(k.Kine_Filament_GetAdvancedEffect(filament, 8, &enabled, &values[0], 16) && enabled)
	assert(k.Kine_Filament_GetAdvancedEffect(filament, 9, &enabled, &values[0], 16) && enabled)
	run(
		&state,
		`
local l=game:GetService("Lighting")
l.ChromaticAberrationEffect.Enabled=false;l.FilmGrainEffect.Enabled=false
post=Instance.new("PostProcess",l)
post:SetUniform("testVector",Vector3.new(1,2,3))
assert(post:GetUniform("testVector")[3]==3)
post:SetUniform("testVector",Color3.new(1,0,0))
assert(post:GetUniform("testVector")[2]==0)
post:SetUniform("testVector",Vector2.new(4,5))
assert(post:GetUniform("testVector")[2]==5)
post:SetUniform("testVector",Vector3.new(1,2,3))
local m={1,0,0,0, 0,1,0,0, 0,0,1,0, 7,0,0,1}
post:SetUniform("customMatrix",m)
assert(post:GetUniform("customMatrix")[13]==7)
post:SetUniform("customMatrix3",{1,0,0,0,2,0,0,0,1})
assert(not pcall(function() post:SetUniform("time",5) end))
local image=game:GetService("AssetService"):CreateImage()
image:DrawRectangle(Vector2.zero,Vector2.one,Color3.new(1,0,0))
post:SetTexture("noiseTexture",image)
image:Destroy()
local clone=post:Clone()
assert(clone:GetUniform("customMatrix")[13]==7)
clone:Destroy()
post.Source=[[
material {name : "DepthSceneTest",shadingModel : unlit,requires : [uv0],depthWrite : false,depthCulling : false,culling : none,
parameters : [{type:sampler2d,name:inputTexture},{type:sampler2d,name:depthTexture},{type:float,name:nearPlane},
{type:float3,name:cameraPosition},{type:float2,name:resolution},{type:mat4,name:inverseViewMatrix},{type:float3,name:testVector},{type:mat4,name:customMatrix},{type:mat3,name:customMatrix3},{type:sampler2d,name:noiseTexture},{type:mat4,name:inverseViewProjectionMatrix}]}
fragment {void material(inout MaterialInputs material) {
prepareMaterial(material);vec2 uv=getUV0();
float depth=texture(materialParams_depthTexture,uv).r;
float distance=materialParams.nearPlane/max(depth,0.000001);
vec3 rgb=texture(materialParams_inputTexture,uv).rgb;
float valid=step(1.0,distance)*step(distance,30.0)*step(9.0,materialParams.cameraPosition.z)*step(300.0,materialParams.resolution.x)*step(9.0,materialParams.inverseViewMatrix[3].z)*step(2.9,materialParams.testVector.z)*step(6.9,materialParams.customMatrix[3].x)*step(1.9,materialParams.customMatrix3[1].y)*step(0.9,texture(materialParams_noiseTexture,vec2(0.5)).r)*step(0.001,abs(materialParams.inverseViewProjectionMatrix[0].x));
material.baseColor=vec4(mix(vec3(0,0,1),vec3(1,0,0),valid)+rgb*0.00001,1);
}}
]]
`,
	)
	center := capture(&env, &state)
	corner := capture(&env, &state, 8, 8)
	fmt.println("POST_DEPTH", center, corner)
	run(&state, `assert(post.Compiled,post.LastError)`)
	assert(
		center[0] > 180 && center[2] < 40 && corner[2] > 180 && corner[0] < 40,
		"depth and camera uniforms did not distinguish geometry from sky",
	)
	run(&state, `fog.Enabled=true`)
	center = capture(&env, &state)
	assert(center[0] > 180 && center[2] < 40, "shared depth path did not preserve geometry depth")
	run(&state, `post:Destroy();fog.Enabled=false`)
	_ = capture(&env, &state)
	run(
		&state,
		`
local lighting = game:GetService("Lighting")
for _, child in workspace:GetChildren() do
    if child:IsA("Part") then child:Destroy() end
end

local camera = workspace.CurrentCamera
camera.CFrame = CFrame.new(0, 2, 7)
camera.FieldOfView = 57

local sun = Instance.new("SunLightEffect", lighting)
sun.Elevation = 90
lighting.GlobalShadows = false

local function box(name, position, size)
    local part = Instance.new("Part", workspace)
    part.Name = name
    part.Anchored = true
    part.CastShadow = true
    part.Color = Color3.fromRGB(70, 65, 60)
    part.Position = position
    part.Size = size
    return part
end

box("CeilingLeft", Vector3.new(-10.9, 5, -8), Vector3.new(18.2, 0.35, 42))
box("CeilingRight", Vector3.new(10.9, 5, -8), Vector3.new(18.2, 0.35, 42))
box("BackWall", Vector3.new(0, 2.5, -15), Vector3.new(40, 5, 1))
box("Floor", Vector3.new(0, -0.2, -8), Vector3.new(40, 0.4, 42))
local rays = lighting.SunRaysEffect
rays.Intensity = 1
rays.DustAmount = 0
rays.MaxDistance = 24
rays.SampleCount = 32
rays.Enabled = false
`,
	)
	without_rays := capture(&env, &state)
	run(&state, `game:GetService("Lighting").SunRaysEffect.Enabled = true`)
	open_skylight := capture(&env, &state)
	assert(
		int(open_skylight[0]) > int(without_rays[0]) + 8,
		"the skylight must produce a visible shaft",
	)
	run(
		&state,
		`
local cover = Instance.new("Part", workspace)
cover.Anchored = true
cover.CastShadow = true
cover.Color = Color3.fromRGB(70, 65, 60)
cover.Position = Vector3.new(0, 5, -8)
cover.Size = Vector3.new(3.6, 0.35, 42)
`,
	)
	closed_skylight := capture(&env, &state)
	run(&state, `game:GetService("Lighting").SunRaysEffect.Enabled = false`)
	closed_without_rays := capture(&env, &state)
	assert(
		abs(int(closed_skylight[0]) - int(closed_without_rays[0])) < 3,
		"closing the skylight must block the volumetric shaft",
	)

	fmt.println("VOLUMETRIC_LIGHTING_SMOKE_PASSED")
}
