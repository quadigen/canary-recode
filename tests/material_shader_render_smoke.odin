package main

import k "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import sdl "vendor:sdl3"

run :: proc(script_vm: ^vm.VM, source: string) {
	ok, err := vm.Run(script_vm, source, "material_shader_render_smoke")
	assert(ok, err)
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
	for _ in 0 ..< 3 {
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
	}
	fmt.println("Shader pixel:", result)
	return result
}

main :: proc() {
	assert(sdl.Init({.VIDEO})); defer sdl.Quit()
	window := sdl.CreateWindow(
		"Material shader smoke",
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
variant = Instance.new("MaterialVariant", workspace)
variant.Name = "Shared"
part = Instance.new("Part", workspace)
part.Size = Vector3.new(3,3,3)
part.MaterialVariant = "Shared"
workspace.CurrentCamera.CFrame = CFrame.new(0,0,8)
workspace.CurrentCamera.FieldOfView = 45
for _, effect in game:GetService("Lighting"):GetChildren() do
    if effect:IsA("LightingEffect") then effect.Enabled = false end
end
local screen = Instance.new("ScreenGui", game.CoreGui)
screen.RenderOnTop = true
preview = Instance.new("ViewportFrame", screen)
preview.Size = UDim2.fromOffset(80,80)
preview.Position = UDim2.fromOffset(10,10)
preview.BackgroundTransparency = 1
previewPart = Instance.new("Part", preview)
previewPart.Size = Vector3.new(3,3,3)
previewPart.MaterialVariant = "Shared"
local camera = Instance.new("Camera", preview)
camera.CFrame = CFrame.new(0,0,8)
preview.CurrentCamera = camera
`,
	)

	shader, _ := classes.MaterialVariant_Resolve(&env.classes, "Shared", filament)
	assert(shader != nil, "default MaterialVariant shader did not compile")
	values := [4]f32{1, 1, 1, 1}
	assert(
		!k.Kine_Filament_Shader_SetUniform(shader, "baseColor", &values[0], 3),
		"uniform vector widths must match",
	)
	assert(
		!k.Kine_Filament_Shader_SetUniform(shader, "instanceColors", &values[0], 4),
		"numeric setters must reject arrays",
	)
	run(
		&script_vm,
		`
variant.Source = [[
material { name : "TestSurface", shadingModel : unlit, instanced : true,
    parameters : [{ type : float4, name : baseColor }] }
fragment { void material(inout MaterialInputs material) {
    prepareMaterial(material); material.baseColor = materialParams.baseColor;
} }
]]
variant.Color = Color3.new(1,0,0)
`,
	)
	red := capture(&env, &script_vm)
	assert(red[0] > red[1] + 50 && red[0] > red[2] + 50, "custom part shader did not render red")
	preview_red := capture(&env, &script_vm, 50, 50)
	assert(preview_red[0] > preview_red[1] + 50, "viewport custom material did not render")
	workspace := cast(^services.Workspace)services.Ensure_Service(&env.services, "Workspace")
	assert(len(workspace.draw_items) > 0 && workspace.draw_items[0].shader != nil)
	run(&script_vm, `variant.Color = Color3.new(0,1,0)`)
	green := capture(&env, &script_vm)
	assert(green[1] > green[0] + 50, "live material uniform update failed")
	preview_green := capture(&env, &script_vm, 50, 50)
	assert(preview_green[1] > preview_green[0] + 50, "viewport uniform update failed")

	run(&script_vm, `savedSource = variant.Source; variant.Source = "invalid material"`)
	green = capture(&env, &script_vm)
	assert(green[1] > green[0] + 50)
	run(
		&script_vm,
		`assert(variant.Compiled and #variant.LastError > 0); variant.Source = savedSource`,
	)
	preview_green = capture(&env, &script_vm, 50, 50)
	assert(preview_green[1] > preview_green[0] + 50, "viewport shader replacement failed")

	run(
		&script_vm,
		`
part.Transparency = 1
local terrain = game:GetService("Terrain")
terrain.MaterialVariant = "Shared"
terrain:FillBall(Vector3.new(0,0,0), 8, Enum.Material.Rock)
workspace.CurrentCamera.CFrame = CFrame.new(0,0,24)
`,
	)
	green = capture(&env, &script_vm)
	assert(green[1] > green[0] + 50, "terrain material variant did not render")
	terrain := cast(^services.Terrain)services.Ensure_Service(&env.services, "Terrain")
	assert(len(terrain.draw_items) > 0 && terrain.draw_items[0].shader != nil)
	run(
		&script_vm,
		`
effect = Instance.new("PostProcess", game:GetService("Lighting"))
effect.Source = [[
material { name : "TestPost", shadingModel : unlit, requires : [uv0],
    depthWrite : false, depthCulling : false, culling : none,
    parameters : [{type : sampler2d, name : inputTexture}] }
fragment { void material(inout MaterialInputs material) {
    prepareMaterial(material);
    material.baseColor = vec4(vec3(1.0) - texture(materialParams_inputTexture, getUV0()).rgb, 1.0);
} }
]]
`,
	)
	inverted := capture(&env, &script_vm)
	assert(
		inverted[0] > inverted[1] + 50 && inverted[2] > inverted[1] + 50,
		"PostProcess was not applied",
	)
	run(&script_vm, `postSource = effect.Source; effect.Source = "invalid material"`)
	inverted = capture(&env, &script_vm)
	assert(
		inverted[0] > inverted[1] + 50,
		"failed postprocess edit must preserve the working pass",
	)
	run(&script_vm, `assert(#effect.LastError > 0); effect.Source = postSource`)
	inverted = capture(&env, &script_vm)
	assert(inverted[0] > inverted[1] + 50, "postprocess source replacement failed")
	run(
		&script_vm,
		`
assert(effect.Compiled and effect.LastError == "")
local inactive = effect:Clone()
inactive.Enabled = false
inactive.Parent = workspace
inactive:Destroy()
`,
	)
	inverted = capture(&env, &script_vm)
	assert(
		inverted[0] > inverted[1] + 50,
		"destroying an inactive effect detached the active effect",
	)
	run(&script_vm, `effect.Enabled = false`)
	green = capture(&env, &script_vm)
	assert(green[1] > green[0] + 50, "disabling PostProcess did not restore the scene")
	run(&script_vm, `effect.Enabled = true`)
	inverted = capture(&env, &script_vm)
	assert(inverted[0] > inverted[1] + 50)
	run(&script_vm, `effect:Destroy(); variant:Destroy()`)
	capture(&env, &script_vm)
	assert(terrain.draw_items[0].shader == nil, "destroyed variant must restore terrain material")
	fmt.println("MATERIAL_SHADER_RENDER_SMOKE_PASSED")
}
