package main

import k "../src/engine/bindings"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"
import sdl "vendor:sdl3"

WIDTH :: 384
HEIGHT :: 256
run :: proc(v: ^vm.VM, source: string) {ok, err := vm.Run(v, source, "advanced_lighting_smoke")
	assert(ok, err)}

capture :: proc(
	env: ^engine_runtime.Environment,
	v: ^vm.VM,
	view: ^renderer.RendererObject,
	path: string,
) -> []u8 {
	ctx := view.Filament
	width, height := int(view.ViewportRect[2]), int(view.ViewportRect[3])
	rect := view.ViewportRect
	k.Kine_Filament_SetViewport(ctx, rect[0], rect[1], rect[2], rect[3])
	compositor := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(ctx)
	pixels := make([]u8, width * height * 3)
	for frame in 0 ..< 4 {
		services.Prepare_3D(&env.services, view)
		base := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(
			compositor,
		); assert(base != nil)
		k.Kine_Skia_Surface_Clear(base, 20, 24, 30, 255)
		engine_runtime.Environment_Render_2D(env, v, base, i32(width), i32(height), 1.0 / 60.0)
		engine_runtime.Environment_Render_3D(env, v, 1.0 / 60.0)
		k.Kine_Filament_RenderFrame(ctx, 1.0 / 60.0)
		overlay := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginOverlay(
			compositor,
		); assert(overlay != nil)
		engine_runtime.Environment_Render_Overlay(
			env,
			v,
			overlay,
			i32(width),
			i32(height),
			1.0 / 60.0,
		)
		if frame == 3 {for y in 0 ..< height {for x in 0 ..< width {
					r, g, b, a: u8; k.Kine_Skia_Surface_GetPixel(overlay, i32(x), i32(y), &r, &g, &b, &a)
					offset :=
						(y * width + x) *
						3; pixels[offset] = r; pixels[offset + 1] = g; pixels[offset + 2] = b
				}}}
		assert(k.Kine_VulkanCompositor_EndFrame(compositor) != 0)
	}
	file, e := os.create(path); assert(e == nil); defer os.close(file)
	header := fmt.tprintf("P6\n%d %d\n255\n", width, height)
	_, _ = os.write(file, transmute([]u8)header); _, _ = os.write(file, pixels)
	return pixels
}

main :: proc() {
	assert(sdl.Init({.VIDEO})); defer sdl.Quit()
	window := sdl.CreateWindow(
		"Scene reflections and indirect lighting",
		WIDTH,
		HEIGHT,
		sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN,
	)
	assert(window != nil); defer sdl.DestroyWindow(window)
	ctx := k.Kine_Filament_CreateForVulkanCompositorWindow(window, WIDTH, HEIGHT)
	assert(ctx != nil); defer k.Kine_Filament_Destroy(ctx)
	view := renderer.RendererObject {
		HasViewportRect = true,
		ViewportRect    = {0, 0, WIDTH, HEIGHT},
	}
	v := vm.New(); env: engine_runtime.Environment
	fmt.println("ENV_INIT_BEGIN")
	engine_runtime.Environment_Init(&env, &v, &view)
	fmt.println("ENV_INIT_OK")
	view.Filament = ctx

	ray := cast(^services.Raytracer)services.Ensure_Service(&env.services, "Raytracer")
	ray.retry_wait = 1_000_000
	defer {vm.Close(&v); engine_runtime.Environment_Destroy(&env)}
	run(
		&v,
		`
local lighting=game:GetService("Lighting")
lighting.SSAOEffect.Quality=2;assert(type(lighting.SSAOEffect.Quality)=="number" and lighting.SSAOEffect.Quality==2)
lighting.SSAOEffect.AOType=1;assert(lighting.SSAOEffect.AOType==1)
for _,name in {"SSGIEffect","ReflectionProbeEffect","FogEffect","ScreenSpaceConeTracingEffect","TemporalAntiAliasingEffect","DynamicResolutionEffect","ToneMappingEffect"} do
    local effect=lighting:FindFirstChild(name)
    assert(effect and effect:IsA("LightingEffect"),name)
    assert(effect:Clone():IsA(name))
    local created=Instance.new(name);assert(created.Enabled==true);created:Destroy()
end
local ssgi=lighting.SSGIEffect
ssgi.Radius=-1;assert(ssgi.Radius==0.1);ssgi.Radius=3
ssgi.SampleCount=1000;assert(ssgi.SampleCount==64);ssgi.SampleCount=32
local cloned=ssgi:Clone();assert(cloned.SampleCount==32);cloned:Destroy()
lighting.ReflectionProbeEffect.Position=Vector3.new(1,2,3)
assert(lighting.ReflectionProbeEffect:Clone().Position==Vector3.new(1,2,3))
`,
	)
	fmt.println("CLASS_API_OK")
	if len(os.args) > 1 && os.args[1] == "sponza" {
		assert(sdl.SetWindowSize(window, 960, 640))
		k.Kine_Filament_Resize(ctx, 960, 640); view.ViewportRect = {0, 0, 960, 640}
		run(
			&v,
			`
workspace.CurrentCamera.CameraType=Enum.CameraType.Scriptable
workspace.CurrentCamera.CFrame=CFrame.lookAt(Vector3.new(9,1.7,0),Vector3.new(-7,2.4,0))
workspace.CurrentCamera.FieldOfView=70
local scene=Instance.new("MeshPart",workspace)
scene.Name="Sponza";scene.Anchored=true;scene.MeshId="build/sponza/Sponza.glb"
scene.Size=Vector3.new(2,2,2)
local variant=Instance.new("MaterialVariant",workspace)
variant.Name="SponzaMirror";variant.Roughness=0.06;variant.Metalness=1
local sphere=Instance.new("Part",workspace)
sphere.Name="ReflectionDemo";sphere.Shape=Enum.PartType.Ball;sphere.Anchored=true
sphere.Material=Enum.Material.Metal;sphere.MaterialVariant="SponzaMirror"
sphere.Size=Vector3.new(1.6,1.6,1.6);sphere.Position=Vector3.new(2.5,2.4,0)
`,
		)
		preset, preset_error := os.read_entire_file(
			"tools/sponza_lighting.luau",
			context.allocator,
		)
		assert(preset_error == nil); run(&v, string(preset)); delete(preset)
		image := capture(&env, &v, &view, "build/sponza/lighting.ppm"); delete(image)
		assert(k.Kine_Filament_GetReflectionProbeCaptureCount(ctx) > 0)
		ok, err := vm.RunInternal(
			&v,
			`assert(game:GetService("ExportService"):ExportToFile("build/sponza/Sponza-lighting.kine"))`,
			"save_sponza_lighting",
		)
		assert(ok, err)
		fmt.println("SPONZA_LIGHTING_RENDER_PASSED")
		return
	}

	run(
		&v,
		`local lighting=game:GetService("Lighting")
lighting.DynamicResolution=false
lighting.ClockTime=12
for _,effect in lighting:GetChildren() do if effect:IsA("LightingEffect") then effect.Enabled=false end end
local mirror=Instance.new("MaterialVariant",workspace)
mirror.Name="TestMirror";mirror.Roughness=0.04;mirror.Metalness=1
workspace.CurrentCamera.CameraType=Enum.CameraType.Scriptable
workspace.CurrentCamera.CFrame=CFrame.lookAt(Vector3.new(0,4,9),Vector3.new(0,2,0))
workspace.CurrentCamera.FieldOfView=60
local function box(name,size,pos,color)
    local p=Instance.new("Part",workspace);p.Name=name;p.Size=size;p.Position=pos;p.Anchored=true
    p.Material=Enum.Material.SmoothPlastic;p.Color=color;return p
end
box("Floor",Vector3.new(24,1,30),Vector3.new(0,-0.5,0),Color3.new(0.65,0.65,0.65))
box("RedWall",Vector3.new(1,8,20),Vector3.new(-5,3,0),Color3.new(1,0.05,0.03))
box("GreenWall",Vector3.new(1,8,20),Vector3.new(5,3,0),Color3.new(0.03,0.8,0.05))
box("BackWall",Vector3.new(10,8,1),Vector3.new(0,3,-10),Color3.new(0.65,0.65,0.65))
box("OffscreenGoldWall",Vector3.new(10,8,1),Vector3.new(0,3,13),Color3.new(1,0.55,0.02))
local sphere=box("Mirror",Vector3.new(3,3,3),Vector3.new(0,2,0),Color3.new(1,1,1))
sphere.Shape=Enum.PartType.Ball;sphere.Material=Enum.Material.Metal;sphere.MaterialVariant="TestMirror"
`,
	)
	baseline := capture(&env, &v, &view, "build/reflection_sky.ppm"); defer delete(baseline)
	run(
		&v,
		`
local p=game:GetService("Lighting").ReflectionProbeEffect
p.Enabled=true;p.Resolution=64;p.UpdateInterval=60;p.MaxDistance=100
`,
	)
	reflected := capture(&env, &v, &view, "build/reflection_scene.ppm"); defer delete(reflected)
	assert(k.Kine_Filament_GetReflectionProbeCaptureCount(ctx) > 0)
	changed := 0
	for y in 90 ..< 175 {for x in 150 ..< 235 {
			i := (y * WIDTH + x) * 3
			if abs(int(reflected[i]) - int(baseline[i])) +
				   abs(int(reflected[i + 1]) - int(baseline[i + 1])) +
				   abs(int(reflected[i + 2]) - int(baseline[i + 2])) >
			   12 {changed += 1}
		}}
	fmt.println("REFLECTION_CHANGED_PIXELS", changed)
	assert(
		changed > 300,
		"Metal must reflect actual scene geometry, including the wall behind the camera",
	)
	run(
		&v,
		`game:GetService("Lighting").SSGIEffect.Intensity=0
game:GetService("Lighting").SSGIEffect.Enabled=true`,
	)
	passthrough := capture(
		&env,
		&v,
		&view,
		"build/ssgi_passthrough.ppm",
	); defer delete(passthrough)
	passthrough_error, passthrough_samples := 0, 0
	for y in 185 ..< 245 {for x in 70 ..< 310 {
			i := (y * WIDTH + x) * 3
			for c in 0 ..< 3 {passthrough_error += abs(int(passthrough[i + c]) - int(reflected[i + c])); passthrough_samples += 1}
		}}
	fmt.println("SSGI_ZERO_INTENSITY_ERROR", f64(passthrough_error) / f64(passthrough_samples))
	assert(
		passthrough_error < 2 * passthrough_samples,
		"The GI pass must preserve the source image at zero intensity",
	)
	run(&v, `game:GetService("Lighting").SSGIEffect.Intensity=1`)
	bounced := capture(&env, &v, &view, "build/ssgi_scene.ppm"); defer delete(bounced)
	difference := 0
	for y in 180 ..< 250 {for x in 50 ..< 330 {for c in 0 ..< 3 {
				i := (y * WIDTH + x) * 3 + c
				if abs(int(bounced[i]) - int(passthrough[i])) > 2 {difference += 1}
			}}}
	fmt.println("SSGI_CHANGED_CHANNELS", difference)
	assert(
		difference > 200,
		"SSGI must add measured indirect light rather than just exposing properties",
	)
	enabled: bool; settings: [16]f32
	assert(k.Kine_Filament_GetAdvancedEffect(ctx, 1, &enabled, &settings[0], 16) && enabled)
	assert(settings[3] == 32)
	run(
		&v,
		`game:GetService("Lighting").SSGIEffect.Enabled=false
game:GetService("Lighting").ReflectionProbeEffect.Enabled=false`,
	)
	restored := capture(&env, &v, &view, "build/reflection_restored.ppm"); defer delete(restored)
	assert(k.Kine_Filament_GetAdvancedEffect(ctx, 1, &enabled, &settings[0], 16) && !enabled)
	run(
		&v,
		`
local l=game:GetService("Lighting")
l.FogEffect.Enabled=true;l.FogEffect.Density=0.02
l.ScreenSpaceConeTracingEffect.Enabled=true
l.TemporalAntiAliasingEffect.Enabled=true
l.DynamicResolutionEffect.Enabled=true
l.ToneMappingEffect.Enabled=true;l.ToneMappingEffect.Mode=2
`,
	)
	effects := capture(&env, &v, &view, "build/advanced_effects.ppm"); delete(effects)
	for effect in i32(2) ..< i32(7) {
		assert(
			k.Kine_Filament_GetAdvancedEffect(ctx, effect, &enabled, &settings[0], 16) && enabled,
		)
	}
	run(
		&v,
		`
local l=game:GetService("Lighting")
for _,name in {"FogEffect","ScreenSpaceConeTracingEffect","TemporalAntiAliasingEffect","DynamicResolutionEffect","ToneMappingEffect"} do l[name].Enabled=false end
l.SSGIEffect.Enabled=true;l.SSGIEffect.Intensity=0
`,
	)
	view.ViewportRect = {40, 30, 304, 196}
	inset := capture(&env, &v, &view, "build/ssgi_inset.ppm"); defer delete(inset)
	assert(
		abs(int(inset[0]) - 20) < 3 && abs(int(inset[1]) - 24) < 3 && abs(int(inset[2]) - 30) < 3,
		"SSGI must preserve the editor UI outside the world viewport",
	)
	fmt.println("ADVANCED_LIGHTING_SMOKE_PASSED")
}
