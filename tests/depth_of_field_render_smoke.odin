package main

import k "../src/engine/bindings"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import sdl "vendor:sdl3"

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.Run(v, source, "depth_of_field_render_smoke")
	assert(ok, err)
}

edge_energy :: proc(env: ^engine_runtime.Environment, v: ^vm.VM) -> int {
	filament := env.renderer.Filament
	compositor := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(filament)
	energy := 0
	for frame in 0 ..< 4 {
		services.Prepare_3D(&env.services, env.renderer)
		base := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(compositor)
		assert(base != nil)
		k.Kine_Skia_Surface_Clear(base, 20, 30, 40, 255)
		engine_runtime.Environment_Render_2D(env, v, base, 320, 240, 1.0 / 60.0)
		engine_runtime.Environment_Render_3D(env, v, 1.0 / 60.0)
		k.Kine_Filament_RenderFrame(filament, 1.0 / 60.0)
		overlay := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginOverlay(compositor)
		assert(overlay != nil)
		engine_runtime.Environment_Render_Overlay(env, v, overlay, 320, 240, 1.0 / 60.0)
		if frame == 3 {
			for y in 115 ..< 125 {
				previous := 0
				for x in 65 ..< 255 {
					p: [4]u8
					k.Kine_Skia_Surface_GetPixel(
						overlay,
						i32(x),
						i32(y),
						&p[0],
						&p[1],
						&p[2],
						&p[3],
					)
					brightness := int(p[0]) + int(p[1]) + int(p[2])
					if x > 65 {energy += abs(brightness - previous)}
					previous = brightness
				}
			}
		}
		assert(k.Kine_VulkanCompositor_EndFrame(compositor) != 0)
	}
	fmt.println("DoF edge energy:", energy)
	return energy
}

main :: proc() {
	assert(sdl.Init({.VIDEO})); defer sdl.Quit()
	window := sdl.CreateWindow(
		"Depth of field regression",
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
	v := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &v, &view)
	defer {vm.Close(&v); engine_runtime.Environment_Destroy(&env)}
	run(
		&v,
		`
local lighting = game:GetService("Lighting")
for _, effect in lighting:GetChildren() do
    if effect:IsA("LightingEffect") then effect.Enabled = false end
end
for i=-16,16 do
    local p = Instance.new("Part",workspace)
    p.Anchored = true
    p.Size = Vector3.new(0.4,12,1)
    p.CFrame = CFrame.new(i*0.4,0,-10)
    p.Color = i%2 == 0 and Color3.new(1,1,1) or Color3.new(0,0,0)
end
workspace.CurrentCamera.CFrame = CFrame.new(0,0,8)
dof = lighting.DepthOfFieldEffect
dof.FocusDistance = 2; dof.InFocusRadius = 0
dof.NearIntensity = 0; dof.FarIntensity = 1
`,
	)
	sharp := edge_energy(&env, &v)
	assert(sharp > 10000, "test scene has no visible stripe edges")
	run(&v, `dof.Enabled = true`)
	blurred := edge_energy(&env, &v)
	assert(blurred < sharp * 8 / 10, "far depth of field did not blur distant geometry")
	run(&v, `dof.FarIntensity = 0`)
	zero := edge_energy(&env, &v)
	assert(zero > blurred * 12 / 10, "zero far intensity did not restore sharp distant geometry")
	run(&v, `dof.FarIntensity = 1; dof.InFocusRadius = 1000`)
	wide := edge_energy(&env, &v)
	assert(wide > blurred * 12 / 10, "increasing focus radius did not reduce blur")
	run(
		&v,
		`dof.FocusDistance = 40; dof.InFocusRadius = 0; dof.NearIntensity = 1; dof.FarIntensity = 0`,
	)
	near := edge_energy(&env, &v)
	assert(near < sharp * 8 / 10, "near intensity did not blur foreground geometry")
	run(&v, `dof.FocusDistance = 17.5`)
	focused := edge_energy(&env, &v)
	assert(
		focused > near * 12 / 10,
		"focus distance did not keep geometry on the focal plane sharp",
	)
	run(&v, `dof.Enabled = false`)
	disabled := edge_energy(&env, &v)
	assert(disabled > sharp * 9 / 10, "disabling depth of field did not restore sharpness")
	fmt.println("DEPTH_OF_FIELD_RENDER_SMOKE_PASSED")
}
