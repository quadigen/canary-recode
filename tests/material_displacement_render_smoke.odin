package main

import assetstore "../src/engine/assetstore"
import k "../src/engine/bindings"
import classes "../src/engine/classes"
import materials "../src/engine/material"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"
import sdl "vendor:sdl3"

run :: proc(v: ^vm.VM, s: string) {ok, err := vm.Run(v, s, "displaced_material"); assert(ok, err)}
write_map :: proc(path: string, color: [3]u8, checker: bool = false) {
	bytes: [18 + 4 * 4 * 3]u8
	bytes[2] = 2; bytes[12] = 4; bytes[14] = 4; bytes[16] = 24; bytes[17] = 32
	for y in 0 ..< 4 {for x in 0 ..< 4 {
			c := color; if checker && (x + y) % 2 == 0 {c = {0, 0, 0}}
			i := 18 + (y * 4 + x) * 3; bytes[i] = c[2]; bytes[i + 1] = c[1]; bytes[i + 2] = c[0]
		}}
	assert(os.write_entire_file(path, bytes[:]) == nil)
}
Result :: struct {
	world, preview: [4]u8,
	samples:        [144][3]u8,
	coverage:       int,
	center_x:       f32,
}
pixel :: proc(s: ^k.KineSkiaSurface, x, y: i32) -> [4]u8 {
	p: [4]u8; k.Kine_Skia_Surface_GetPixel(s, x, y, &p[0], &p[1], &p[2], &p[3]); return p
}
capture :: proc(env: ^engine_runtime.Environment, v: ^vm.VM) -> Result {
	f := env.renderer.Filament
	c := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(f)
	r: Result
	for iteration in 0 ..< 3 {
		services.Prepare_3D(&env.services, env.renderer)
		base := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(c); assert(base != nil)
		k.Kine_Skia_Surface_Clear(base, 20, 30, 40, 255)
		engine_runtime.Environment_Render_2D(env, v, base, 320, 240, 1.0 / 60.0)
		engine_runtime.Environment_Render_3D(env, v, 1.0 / 60.0)
		k.Kine_Filament_SetSun(f, -1, -1, -1, 100000)
		k.Kine_Filament_RenderFrame(f, 1.0 / 60.0)
		overlay := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginOverlay(
			c,
		); assert(overlay != nil)
		engine_runtime.Environment_Render_Overlay(env, v, overlay, 320, 240, 1.0 / 60.0)
		if iteration == 2 {
			r.world = pixel(overlay, 160, 120); r.preview = pixel(overlay, 50, 50)
			for y in 0 ..< 12 {for x in 0 ..< 12 {
					p := pixel(
						overlay,
						112 + i32(x * 8),
						72 + i32(y * 8),
					); r.samples[y * 12 + x] = {p[0], p[1], p[2]}
				}}
			for y in 0 ..< 30 {for x in 0 ..< 40 {
					px, py := i32(x * 8 + 4), i32(y * 8 + 4)
					if px < 95 && py < 95 {continue}
					p := pixel(overlay, px, py)
					if int(p[1]) > int(p[0]) + 40 &&
					   int(p[1]) > int(p[2]) + 40 {r.coverage += 1; r.center_x += f32(px)}
				}}
			if r.coverage > 0 {r.center_x /= f32(r.coverage)}
		}
		assert(k.Kine_VulkanCompositor_EndFrame(c) != 0)
	}
	fmt.println(
		"Advanced material:",
		r.world,
		r.preview,
		"coverage",
		r.coverage,
		"center",
		r.center_x,
	)
	return r
}
changed :: proc(a, b: Result) -> int {
	n := 0
	for p, i in a.samples {d := 0; for c, j in p {d += abs(int(c) - int(b.samples[i][j]))}; if d > 12 {n += 1}}
	fmt.println("Changed material pixels:", n); return n
}
main :: proc() {
	paths := [?]string {
		"build/advanced-red.tga",
		"build/advanced-white.tga",
		"build/advanced-black.tga",
		"build/advanced-checker.tga",
	}
	defer {for path in paths {os.remove(path)}}
	write_map(
		paths[0],
		{255, 0, 0},
	); write_map(paths[1], {255, 255, 255}); write_map(paths[2], {0, 0, 0}); write_map(paths[3], {255, 255, 255}, true)
	assert(sdl.Init({.VIDEO})); defer sdl.Quit()
	w := sdl.CreateWindow(
		"Advanced materials",
		320,
		240,
		sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN,
	); assert(w != nil); defer sdl.DestroyWindow(w)
	f := k.Kine_Filament_CreateForVulkanCompositorWindow(
		w,
		320,
		240,
	); assert(f != nil); defer k.Kine_Filament_Destroy(f)
	ro := renderer.RendererObject {
		Filament = f,
	}
	v := vm.New(); env: engine_runtime.Environment; engine_runtime.Environment_Init(&env, &v, &ro)
	defer {vm.Close(&v); engine_runtime.Environment_Destroy(&env)}
	run(
		&v,
		`
root=Instance.new("Model",workspace)
m=Instance.new("MaterialVariant",root);m.Name="Advanced"
p=Instance.new("Part",root);p.Size=Vector3.new(4,4,4);p.Shape=Enum.PartType.Ball;p.MaterialVariant="Advanced"
workspace.CurrentCamera.CFrame=CFrame.new(0,0,8)
for _,e in game:GetService("Lighting"):GetChildren() do if e:IsA("LightingEffect") then e.Enabled=false end end
local screen=Instance.new("ScreenGui",game.CoreGui);screen.RenderOnTop=true
preview=Instance.new("ViewportFrame",screen);preview.Size=UDim2.fromOffset(80,80);preview.Position=UDim2.fromOffset(10,10)
local camera=Instance.new("Camera",preview);camera.CFrame=CFrame.new(0,0,8);preview.CurrentCamera=camera
local copy=p:Clone();copy.Parent=preview
m.ColorMap="build/advanced-red.tga"
`,
	)
	red := capture(&env, &v); assert(red.world[0] > red.world[2] + 30)

	assert(os.remove(paths[0]) == nil)
	run(&v, `m.FragmentSource="material.baseColor.rgb = material.baseColor.bgr;"`)
	blue := capture(&env, &v)
	assert(
		blue.world[2] > blue.world[0] + 30 && blue.preview[2] > blue.preview[0] + 30,
		"fragment hook did not modify the sampled texture",
	)
	run(&v, `m.FragmentSource="invalid shader code;"`)
	blue = capture(
		&env,
		&v,
	); assert(blue.world[2] > blue.world[0] + 30, "failed shader edit lost the textured material")
	run(
		&v,
		`
assert(m.Compiled and #m.LastError>0)
m:ResetShader();m.Roughness=0
m.Source=[[
material {name:"TexturedCustom",shadingModel:unlit,instanced:true,
parameters:[{type:sampler2d,name:colorMap},{type:float,name:roughness}]}
fragment {void material(inout MaterialInputs material) {
prepareMaterial(material);vec3 color=texture(materialParams_colorMap,vec2(0.5)).rgb;
material.baseColor=vec4(mix(color,vec3(1.0)-color,materialParams.roughness),1.0);
}}
]]
`,
	)
	red = capture(&env, &v); assert(red.world[0] > red.world[1] + 30)
	run(&v, `m.Roughness=1`)
	inverted := capture(&env, &v)
	assert(
		inverted.world[1] > inverted.world[0] + 30 && inverted.world[2] > inverted.world[0] + 30,
		"full custom shader did not modify its texture",
	)
	run(
		&v,
		`
m:ResetShader();assert(m.FragmentSource=="" and m.VertexSource=="")
m.ColorMap="build/advanced-black.tga";m.EmissiveMap="build/advanced-white.tga"
m.EmissiveColor=Color3.new(0,0,1);m.EmissiveStrength=2
`,
	)
	emit := capture(&env, &v); assert(emit.world[2] > emit.world[0] + 40)
	run(&v, `m.EmissiveStrength=0`)
	dark := capture(
		&env,
		&v,
	); assert(int(emit.world[2]) > int(dark.world[2]) + 40, "emissive strength did not affect the map")
	run(
		&v,
		`
m.ColorMap="build/advanced-white.tga";m.EmissiveMap=""
preview.Ambient=Color3.new(1,1,1);preview.LightColor=Color3.new(0,0,0)
m.AOMap="build/advanced-white.tga"
`,
	)
	ambient := capture(&env, &v)
	run(&v, `m.AmbientOcclusionMap="build/advanced-black.tga"`)
	occluded := capture(&env, &v)
	assert(
		int(ambient.preview[0]) > int(occluded.preview[0]) + 30,
		"AO map did not occlude ambient lighting",
	)
	run(&v, `m.AOStrength=0`)
	ambient_again := capture(&env, &v)
	assert(int(ambient_again.preview[0]) > int(occluded.preview[0]) + 30)
	run(
		&v,
		`
m.AOMap="";m.ColorMap="build/advanced-checker.tga";m.HeightMap="build/advanced-checker.tga"
m.StudsPerTile=2;m.ParallaxDepth=0
workspace.CurrentCamera.CFrame=CFrame.lookAt(Vector3.new(6,3,8),Vector3.zero)
`,
	)
	flat := capture(&env, &v)
	run(&v, `m.ParallaxDepth=0.8;m.ParallaxSteps=32`)
	parallax := capture(
		&env,
		&v,
	); assert(changed(flat, parallax) > 12, "parallax did not shift the texture samples")
	run(
		&v,
		`
m.ParallaxDepth=0;m.HeightMap="build/advanced-white.tga";m.HeightScale=0
workspace.CurrentCamera.CFrame=CFrame.new(0,0,8)
m.FragmentSource="material.baseColor=vec4(0.0,1.0,0.0,1.0); material.emissive=vec4(0.0,1.0,0.0,0.0);"
`,
	)
	base := capture(&env, &v); assert(base.coverage > 20)
	run(&v, `m.HeightScale=2;m.DisplacementSubdivisions=3`)
	displaced := capture(&env, &v)
	assert(
		displaced.coverage > base.coverage * 13 / 10,
		"height map did not change the actual silhouette",
	)
	run(
		&v,
		`m.HeightScale=0;m.DisplacementBounds=2;m.VertexSource="material.worldPosition.x += 1.5;"`,
	)
	moved := capture(&env, &v)
	assert(moved.center_x > base.center_x + 20, "vertex hook did not move real geometry")

	run(&v, `m.AOMap="build/advanced-black.tga";m.EmissiveMap="build/advanced-white.tga"`)
	vm.GetGlobal(v.L, "root"); root := classes.Object_From_Argument(v.L, -1); vm.Pop(v.L)
	data, err := serializer.Serialize(
		&env.classes,
		v.L,
		root,
	); assert(serializer.Error_Is_None(err)); defer delete(data)
	for path in paths {os.remove(path)}
	assetstore.Clear()
	loaded, load_err := serializer.Deserialize(
		&env.classes,
		v.L,
		nil,
		data,
	); assert(serializer.Error_Is_None(load_err))
	classes.Push_Object(v.L, loaded); vm.SetGlobalFromStack(&v, "loaded")
	run(
		&v,
		`
root:Destroy();root=loaded;root.Parent=workspace;m=root:FindFirstChild("Advanced")
assert(#m.FragmentSource>0 and #m.VertexSource>0 and m.DisplacementBounds==2)
assert(string.sub(m.HeightMap,1,12)=="kineasset:
assert(string.sub(m.AOMap,1,12)=="kineasset:
`,
	)
	loaded_result := capture(&env, &v); assert(loaded_result.center_x > base.center_x + 20)
	run(
		&v,
		`
m.VertexSource="";m.DisplacementBounds=0;m.HeightScale=1
root:FindFirstChild("Part").Transparency=1
local terrain=game:GetService("Terrain");terrain.MaterialVariant="Advanced"
terrain:FillBall(Vector3.zero,8,Enum.Material.Rock)
workspace.CurrentCamera.CFrame=CFrame.new(0,0,24)
`,
	)
	terrain := capture(
		&env,
		&v,
	); assert(terrain.coverage > 20, "displaced terrain failed to render")
	run(&v, `game:GetService("Terrain"):Clear();m:Destroy()`)
	capture(&env, &v)


	materials.shutdown(&ro)
	reloaded := capture(&env, &v)
	assert(int(reloaded.preview[0]) + int(reloaded.preview[1]) + int(reloaded.preview[2]) > 100)
	fmt.println("MATERIAL_DISPLACEMENT_RENDER_SMOKE_PASSED")
}
