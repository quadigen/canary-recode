package main

import k "../src/engine/bindings"
import enums "../src/engine/enum"
import materials "../src/engine/material"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"
import sdl "vendor:sdl3"

main :: proc() {
	assert(sdl.Init({.VIDEO})); defer sdl.Quit()
	window := sdl.CreateWindow(
		"Built-in material catalog",
		960,
		640,
		sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN,
	)
	assert(window != nil); defer sdl.DestroyWindow(window)
	filament := k.Kine_Filament_CreateForVulkanCompositorWindow(window, 960, 640)
	assert(filament != nil); defer k.Kine_Filament_Destroy(filament)
	view := renderer.RendererObject {
		Filament        = filament,
		HasViewportRect = true,
		ViewportRect    = {0, 0, 960, 640},
	}
	v := vm.New(); env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &v, &view)
	defer {vm.Close(&v); engine_runtime.Environment_Destroy(&env)}
	ok, err := vm.Run(
		&v,
		`
workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
workspace.CurrentCamera.CFrame = CFrame.new(0,0,22)
workspace.CurrentCamera.FieldOfView = 45
for _,effect in game:GetService("Lighting"):GetChildren() do
    if effect:IsA("LightingEffect") then effect.Enabled = false end
end
local screen = Instance.new("ScreenGui",game.CoreGui)
screen.RenderOnTop = true
for i,item in Enum.Material:GetEnumItems() do
    local col,row = (i-1)%9,math.floor((i-1)/9)
    local x,y = (col-4)*3,(2-row)*3.2
    local part = Instance.new("Part",workspace)
    part.Name = item.Name; part.Anchored = true
    part.Shape = Enum.PartType.Ball; part.Size = Vector3.new(2.45,2.45,2.45)
    part.CFrame = CFrame.new(x,y,0); part.Material = item
    if item == Enum.Material.Air then part.Transparency = 1 end
    if item == Enum.Material.ForceField then part.Color = Color3.new(0.15,0.6,1) end
    if item == Enum.Material.Water then
        part.CFrame = CFrame.new(x,y,0)*CFrame.Angles(math.rad(55),0,0)
        part.Size = Vector3.new(2.45,0.1,2.45)
    end
    local label = Instance.new("TextLabel",screen)
    label.BackgroundTransparency = 1
    label.Text = item.Name; label.TextColor3 = Color3.new(1,1,1); label.TextSize = 12
    label.Size = UDim2.fromOffset(104,24)
    label.Position = UDim2.fromOffset(480+(col-4)*105.35-52,320-(2-row)*112.37+45)
end
`,
		"material_catalog_render_smoke",
	)
	assert(ok, err)
	compositor := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(filament)
	pixels := make([]u8, 960 * 640 * 3); defer delete(pixels)
	for frame in 0 ..< 4 {
		services.Prepare_3D(&env.services, &view)
		base := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(compositor)
		assert(base != nil); k.Kine_Skia_Surface_Clear(base, 24, 27, 35, 255)
		engine_runtime.Environment_Render_2D(&env, &v, base, 960, 640, 1.0 / 60.0)
		engine_runtime.Environment_Render_3D(&env, &v, 1.0 / 60.0)
		k.Kine_Filament_RenderFrame(filament, 1.0 / 60.0)
		overlay := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginOverlay(compositor)
		assert(overlay != nil)
		engine_runtime.Environment_Render_Overlay(&env, &v, overlay, 960, 640, 1.0 / 60.0)
		if frame == 3 && len(os.args) > 1 {
			for y in 0 ..< 640 {for x in 0 ..< 960 {
					r, g, b, a: u8
					k.Kine_Skia_Surface_GetPixel(overlay, i32(x), i32(y), &r, &g, &b, &a)
					offset :=
						(y * 960 + x) *
						3; pixels[offset] = r; pixels[offset + 1] = g; pixels[offset + 2] = b
				}}
		}
		assert(k.Kine_VulkanCompositor_EndFrame(compositor) != 0)
	}

	for material in enums.Material_Public_Order {
		if material == .Air ||
		   material == .Glass ||
		   material == .Water ||
		   material == .Neon ||
		   material == .ForceField {continue}
		entry := materials.Get(material)
		assert(entry.loaded && entry.texture != nil, enums.Material_Names[int(material)])
	}
	forcefield, _ := materials.Lookup(.ForceField)
	assert(forcefield.material_kind == k.KINE_MAT_FORCEFIELD)
	if len(os.args) > 1 {
		file, e := os.create(os.args[1]); assert(e == nil); defer os.close(file)
		header := "P6\n960 640\n255\n"
		_, _ = os.write(file, transmute([]u8)header); _, _ = os.write(file, pixels)
	}
	fmt.println("MATERIAL_CATALOG_RENDER_SMOKE_PASSED")
}
