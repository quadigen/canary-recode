package main

import assetstore "../src/engine/assetstore"
import k "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"
import "core:time"
import sdl "vendor:sdl3"

run :: proc(script_vm: ^vm.VM, source: string) {
	ok, err := vm.Run(script_vm, source, "material_texture_render_smoke")
	assert(ok, err)
}

write_map :: proc(path: string, color: [3]u8, checker: bool = false) {

	pixels: [18 + 4 * 4 * 3]u8
	pixels[2] = 2; pixels[12] = 4; pixels[14] = 4; pixels[16] = 24; pixels[17] = 32
	for y in 0 ..< 4 {for x in 0 ..< 4 {
			v := color
			if checker && (x + y) % 2 == 0 {v = {0, 0, 0}}
			i := 18 + (y * 4 + x) * 3
			pixels[i] = v[2]; pixels[i + 1] = v[1]; pixels[i + 2] = v[0]
		}}
	assert(os.write_entire_file(path, pixels[:]) == nil)
}

Capture :: struct {
	world, preview: [4]u8,
	signature:      u64,
	samples:        [144][3]u8,
}
changed_pixels :: proc(a, b: Capture) -> int {
	count := 0
	for p, i in a.samples {
		difference := 0
		for value, channel in p {difference += abs(int(value) - int(b.samples[i][channel]))}
		if difference > 12 {count += 1}
	}
	fmt.println("Material pixels changed beyond dithering:", count)
	return count
}
pixel :: proc(surface: ^k.KineSkiaSurface, x, y: i32) -> [4]u8 {
	p: [4]u8
	k.Kine_Skia_Surface_GetPixel(surface, x, y, &p[0], &p[1], &p[2], &p[3])
	return p
}
capture :: proc(env: ^engine_runtime.Environment, script_vm: ^vm.VM) -> Capture {
	filament := env.renderer.Filament
	compositor := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(filament)
	result: Capture
	for iteration in 0 ..< 600 {
		services.Prepare_3D(&env.services, env.renderer)
		base := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(compositor)
		assert(base != nil)
		k.Kine_Skia_Surface_Clear(base, 20, 30, 40, 255)
		engine_runtime.Environment_Render_2D(env, script_vm, base, 320, 240, 1.0 / 60.0)
		engine_runtime.Environment_Render_3D(env, script_vm, 1.0 / 60.0)
		k.Kine_Filament_SetSun(filament, -1, -1, -1, 100000)
		k.Kine_Filament_RenderFrame(filament, 1.0 / 60.0)
		overlay := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginOverlay(compositor)
		assert(overlay != nil)
		engine_runtime.Environment_Render_Overlay(env, script_vm, overlay, 320, 240, 1.0 / 60.0)
		pending := false
		for object in classes.Find_Class(&env.classes, "MaterialVariant").instances {
			if !object.destroyed && (cast(^classes.MaterialVariant)object).compile_job != nil {
				pending = true
				break
			}
		}
		terrain := cast(^services.Terrain)services.Ensure_Service(&env.services, "Terrain")
		ready := iteration >= 2 && !pending && terrain.mesh_batch == nil && len(terrain.dirty_queue) == 0
		if ready {
			result.world = pixel(overlay, 160, 120)
			result.preview = pixel(overlay, 50, 50)
			result.signature = 14695981039346656037
			for y in 0 ..< 12 {for x in 0 ..< 12 {
					p := pixel(overlay, 112 + i32(x * 8), 72 + i32(y * 8))
					result.samples[y * 12 + x] = {p[0], p[1], p[2]}
					for channel in p {result.signature = (result.signature ~ u64(channel / 8)) * 1099511628211}
				}}
		}
		assert(k.Kine_VulkanCompositor_EndFrame(compositor) != 0)
		if ready {
			fmt.println("Texture capture:", result.world, result.preview, result.signature)
			return result
		}
		time.sleep(time.Millisecond)
	}
	panic("Timed out waiting for material or terrain preparation")
}

main :: proc() {
	paths := [?]string {
		"build/material-red.tga",
		"build/material-green.tga",
		"build/material-normal.tga",
		"build/material-black.tga",
		"build/material-white.tga",
		"build/material-checker.tga",
	}
	defer {for path in paths {os.remove(path)}}
	write_map(paths[0], {255, 0, 0}); write_map(paths[1], {0, 255, 0})
	write_map(paths[2], {220, 128, 220}); write_map(paths[3], {0, 0, 0})
	write_map(paths[4], {255, 255, 255}); write_map(paths[5], {255, 255, 255}, true)
	assert(sdl.Init({.VIDEO})); defer sdl.Quit()
	window := sdl.CreateWindow(
		"Material textures",
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
	script_vm := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm, &renderer_object)
	defer {vm.Close(&script_vm); engine_runtime.Environment_Destroy(&env)}
	run(
		&script_vm,
		`
root = Instance.new("Model", workspace)
variant = Instance.new("MaterialVariant", root)
variant.Name = "Mapped"
assert(variant.ColorMap == "" and variant.AlbedoMap == "")
assert(variant.NormalMap == "" and variant.RoughnessMap == "" and variant.MetalnessMap == "")
assert(variant.StudsPerTile == 4)
assert(not pcall(function() variant.StudsPerTile = 0 end))
assert(not pcall(function() variant.StudsPerTile = math.huge end))
part = Instance.new("Part", root)
part.Size = Vector3.new(4,4,4)
part.Shape = Enum.PartType.Ball
part.MaterialVariant = "Mapped"
workspace.CurrentCamera.CFrame = CFrame.new(0,0,8)
for _, effect in game:GetService("Lighting"):GetChildren() do
    if effect:IsA("LightingEffect") then effect.Enabled = false end
end
local screen = Instance.new("ScreenGui",game.CoreGui)
screen.RenderOnTop = true
local preview = Instance.new("ViewportFrame",screen)
preview.Size = UDim2.fromOffset(80,80)
preview.Position = UDim2.fromOffset(10,10)
local camera = Instance.new("Camera",preview)
camera.CFrame = CFrame.new(0,0,8)
preview.CurrentCamera = camera
local previewPart = part:Clone()
previewPart.Parent = preview
variant.ColorMap = "build/material-red.tga"
assert(variant.AlbedoMap == variant.ColorMap)
`,
	)
	red := capture(&env, &script_vm)
	assert(
		red.world[0] > red.world[1] + 30 && red.preview[0] > red.preview[1] + 30,
		"albedo map did not render red",
	)
	run(
		&script_vm,
		`variant.AlbedoMap = "build/material-green.tga"; assert(variant.ColorMap == variant.AlbedoMap)`,
	)
	green := capture(&env, &script_vm)
	assert(
		green.world[1] > green.world[0] + 30 && green.preview[1] > green.preview[0] + 30,
		"live albedo map replacement failed",
	)
	run(&script_vm, `variant.ColorMap = "build/material-missing.tga"`)
	failed := capture(&env, &script_vm)
	assert(
		failed.world[1] > failed.world[0] + 30,
		"failed texture replacement lost the previous map",
	)
	run(&script_vm, `assert(#variant.LastError > 0); variant.ColorMap = ""`)
	clear := capture(&env, &script_vm)
	assert(clear.world[0] > green.world[0] + 30, "clearing albedo failed to restore the tint")
	run(&script_vm, `variant.ColorMap = "build/material-checker.tga"; variant.StudsPerTile = 4`)
	large := capture(&env, &script_vm)
	run(&script_vm, `variant.StudsPerTile = 1`)
	small := capture(&env, &script_vm)
	assert(changed_pixels(large, small) > 8, "StudsPerTile did not change texture tiling")
	run(&script_vm, `variant.ColorMap = ""; variant.RoughnessMap = "build/material-black.tga"`)
	smooth := capture(&env, &script_vm)
	run(&script_vm, `variant.RoughnessMap = "build/material-white.tga"`)
	rough := capture(&env, &script_vm)
	assert(changed_pixels(smooth, rough) > 8, "roughness map did not affect shading")
	run(&script_vm, `variant.RoughnessMap = ""; variant.MetalnessMap = "build/material-white.tga"`)
	metal := capture(&env, &script_vm)
	run(&script_vm, `variant.MetalnessMap = "build/material-black.tga"`)
	dielectric := capture(&env, &script_vm)
	assert(changed_pixels(metal, dielectric) > 8, "metalness map did not affect shading")
	run(&script_vm, `variant.NormalMap = "build/material-normal.tga"`)
	bump := capture(&env, &script_vm)
	assert(changed_pixels(bump, dielectric) > 8, "normal map did not affect lighting")

	run(
		&script_vm,
		`
variant.ColorMap = "build/material-green.tga"
variant.RoughnessMap = "build/material-white.tga"
local copy = variant:Clone()
assert(copy.ColorMap == variant.ColorMap and copy.NormalMap == variant.NormalMap)
assert(copy.RoughnessMap == variant.RoughnessMap and copy.MetalnessMap == variant.MetalnessMap)
assert(copy.StudsPerTile == 1)
copy:Destroy()
`,
	)
	vm.GetGlobal(script_vm.L, "root")
	root := classes.Object_From_Argument(script_vm.L, -1); vm.Pop(script_vm.L)
	data, err := serializer.Serialize(&env.classes, script_vm.L, root)
	assert(serializer.Error_Is_None(err)); defer delete(data)
	for path in paths {os.remove(path)}
	assetstore.Clear()
	loaded, load_err := serializer.Deserialize(&env.classes, script_vm.L, nil, data)
	assert(serializer.Error_Is_None(load_err))
	classes.Push_Object(script_vm.L, loaded); vm.SetGlobalFromStack(&script_vm, "loaded")
	run(
		&script_vm,
		`
root:Destroy()
root = loaded
root.Parent = workspace
variant = root:FindFirstChild("Mapped")
assert(string.sub(variant.ColorMap, 1, 12) == "kineasset://")
part = root:FindFirstChild("Part")
`,
	)
	embedded := capture(&env, &script_vm)
	assert(embedded.world[1] > embedded.world[0] + 30, "embedded color map did not render")
	for object in classes.Find_Class(&env.classes, "MaterialVariant").instances {
		if object.destroyed || object.parent == nil {continue}
		variant := cast(^classes.MaterialVariant)object
		for i in 0 ..< 4 {assert(variant.maps_loaded[i], "an embedded PBR map was not loaded")}
	}
	run(
		&script_vm,
		`
part.Transparency = 1
local terrain = game:GetService("Terrain")
terrain.MaterialVariant = "Mapped"
terrain:FillBall(Vector3.zero,8,Enum.Material.Rock)
workspace.CurrentCamera.CFrame = CFrame.new(0,0,24)
`,
	)
	terrain := capture(&env, &script_vm)
	assert(terrain.world[1] > terrain.world[0] + 30, "terrain did not use the embedded albedo map")
	run(&script_vm, `variant:Destroy()`)
	capture(&env, &script_vm)
	fmt.println("MATERIAL_TEXTURE_RENDER_SMOKE_PASSED")
}
