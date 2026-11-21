package main

import k "../src/engine/bindings"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:time"
import sdl "vendor:sdl3"

WIDTH :: 320
HEIGHT :: 240

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.Run(v, source, "terrain_raymarch_render_smoke")
	assert(ok, err)
}

capture :: proc(
	env: ^engine_runtime.Environment,
	v: ^vm.VM,
	view: ^renderer.RendererObject,
	compositor: ^k.KineVulkanCompositor,
	offset: i32 = 0,
) -> [3]u8 {
	terrain := cast(^services.Terrain)services.Ensure_Service(&env.services, "Terrain")
	start := time.tick_now()
	for {
		services.Prepare_3D(&env.services, view)
		if services.Terrain_Dirty_Queue_Depth(terrain) == 0 && terrain.mesh_batch == nil {break}
		assert(time.tick_since(start) < 10 * time.Second, "terrain rebuild did not finish")
		time.sleep(time.Millisecond)
	}

	pixel: [3]u8
	for frame in 0 ..< 3 {
		base := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(compositor)
		assert(base != nil)
		k.Kine_Skia_Surface_Clear(base, 10, 12, 15, 255)
		engine_runtime.Environment_Render_3D(env, v, 1.0 / 60.0)
		k.Kine_Filament_RenderFrame(view.Filament, 1.0 / 60.0)
		overlay := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginOverlay(compositor)
		assert(overlay != nil)
		if frame == 2 {
			alpha: u8
			k.Kine_Skia_Surface_GetPixel(
				overlay,
				WIDTH / 2 + offset,
				HEIGHT / 2,
				&pixel[0],
				&pixel[1],
				&pixel[2],
				&alpha,
			)
		}
		assert(k.Kine_VulkanCompositor_EndFrame(compositor) != 0)
	}
	return pixel
}

main :: proc() {
	assert(sdl.Init({.VIDEO}))
	defer sdl.Quit()
	window := sdl.CreateWindow(
		"Raymarched terrain regression",
		WIDTH,
		HEIGHT,
		sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN,
	)
	assert(window != nil)
	defer sdl.DestroyWindow(window)
	ctx := k.Kine_Filament_CreateForVulkanCompositorWindow(window, WIDTH, HEIGHT)
	assert(ctx != nil)
	defer k.Kine_Filament_Destroy(ctx)
	compositor := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(ctx)
	assert(compositor != nil)
	view := renderer.RendererObject {
		Filament        = ctx,
		HasViewportRect = true,
		ViewportRect    = {0, 0, WIDTH, HEIGHT},
	}
	v := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &v, &view)
	defer {vm.Close(&v); engine_runtime.Environment_Destroy(&env)}

	run(
		&v,
		`
local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable
camera.CFrame = CFrame.lookAt(Vector3.new(0, 8, 12), Vector3.new(0, -1.5, 0))
camera.FieldOfView = 40
local lighting = game:GetService("Lighting")
lighting.DynamicResolution = false
for _, effect in lighting:GetChildren() do
	if effect:IsA("LightingEffect") then effect.Enabled = false end
end

local terrain = game:GetService("Terrain")
terrain.VoxelSize = 1
terrain.Decoration = false
terrain.Raymarching = true

local tilted = CFrame.new(40, 0, 0) * CFrame.Angles(0, 0, math.rad(30))
terrain:FillBlock(tilted, Vector3.new(4, 4, 4), Enum.Material.Slate)
local inside = terrain:GetVoxel(41, 0, 0).occupancy
local outside = terrain:GetVoxel(41, 1, 0).occupancy
assert(inside > 0.5 and outside < 0.5 and math.abs(inside - outside - 0.25) < 0.001,
	"adjacent samples must retain the slope across the tilted block's face")
terrain:Clear()

terrain:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(222, 142, 27))
terrain:FillBlock(CFrame.new(0, -2, 0), Vector3.new(30, 4, 30), Enum.Material.Slate)

local probe = Instance.new("Part", workspace)
probe.Name = "BuriedProbe"
probe.Anchored = true
probe.Size = Vector3.new(3, 0.5, 3)
probe.Position = Vector3.new(0, -1.5, 0)
probe.Color = Color3.fromRGB(25, 66, 255)
`,
	)
	solid := capture(&env, &v, &view, compositor)
	for offset in ([?]i32{-8, 8}) {
		edge := capture(&env, &v, &view, compositor, offset)
		assert(
			edge[0] > 55 && int(edge[0]) > int(edge[2]) * 2,
			fmt.tprintf("chunk seam pixel %v", edge),
		)
	}
	assert(
		solid[0] > 55 && int(solid[0]) > int(solid[2]) * 2,
		fmt.tprintf("terrain must occlude a buried part: %v", solid),
	)

	run(&v, `game:GetService("Terrain"):FillBall(Vector3.new(0, 0, 0), 4, Enum.Material.Air)`)
	carved := capture(&env, &v, &view, compositor)
	assert(
		int(carved[2]) > int(carved[0]) + 65 && int(carved[2]) > int(carved[1]) + 40,
		fmt.tprintf("carving must reveal the buried part: %v", carved),
	)
	fmt.println("TERRAIN_RAYMARCH_RENDER_SMOKE_PASSED")
}
