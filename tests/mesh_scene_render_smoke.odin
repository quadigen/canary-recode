package main

import k "../src/engine/bindings"
import classes "../src/engine/classes"
import datatypes "../src/engine/datatypes"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:math"
import "core:os"
import sdl "vendor:sdl3"

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.Run(v, source, "mesh_scene_render_smoke"); assert(ok, err)
}

main :: proc() {
	camera := classes.Camera_Init()
	camera.CFrame = datatypes.CFrame_Identity
	camera.viewport_width = 100; camera.viewport_height = 100
	camera.field_of_view = 120
	frustum, valid := services.Workspace_Frustum_Build(&camera, 1000); assert(valid)
	assert(services.Workspace_Frustum_Contains_Sphere(&frustum, {10, 0, -10}, 0.1))
	camera.field_of_view = 30
	frustum, valid = services.Workspace_Frustum_Build(&camera, 1000); assert(valid)
	assert(!services.Workspace_Frustum_Contains_Sphere(&frustum, {4, 0, -10}, 0.1))

	assert(sdl.Init({.VIDEO})); defer sdl.Quit()
	window := sdl.CreateWindow(
		"Mesh material and culling regression",
		320,
		240,
		sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN,
	)
	assert(window != nil); defer sdl.DestroyWindow(window)
	ctx := k.Kine_Filament_CreateForVulkanCompositorWindow(window, 320, 240)
	assert(ctx != nil); defer k.Kine_Filament_Destroy(ctx)
	view := renderer.RendererObject {
		Filament        = ctx,
		HasViewportRect = true,
		ViewportRect    = {0, 0, 320, 240},
	}
	v := vm.New(); env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &v, &view)
	defer {vm.Close(&v); engine_runtime.Environment_Destroy(&env)}
	run(
		&v,
		`
workspace.CurrentCamera.CameraType=Enum.CameraType.Scriptable
game:GetService("Lighting").ReflectionProbeEffect.Enabled=false
workspace.CurrentCamera.CFrame=CFrame.new(50,0,8)
workspace.CurrentCamera.FieldOfView=60
for _,effect in game:GetService("Lighting"):GetChildren() do
    if effect:IsA("LightingEffect") then effect.Enabled=false end
end
local part=Instance.new("MeshPart",workspace)
part.Name="Scene";part.Anchored=true;part.MeshId="tests/assets/multi_material.gltf"
part.Size=Vector3.new(2,2,2);part.Color=Color3.new(1,1,1)
`,
	)
	workspace := cast(^services.Workspace)services.Ensure_Service(&env.services, "Workspace")
	part := cast(^classes.MeshPart)classes.Find_First_Child(
		&workspace.object,
		"Scene",
	); assert(part != nil)
	compositor := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(ctx)
	pixels := make([]u8, 320 * 240 * 3); defer delete(pixels)
	for frame in 0 ..< 5 {
		services.Prepare_3D(&env.services, &view)
		base := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(
			compositor,
		); assert(base != nil)
		k.Kine_Skia_Surface_Clear(base, 24, 27, 35, 255)
		engine_runtime.Environment_Render_2D(&env, &v, base, 320, 240, 1.0 / 60.0)
		engine_runtime.Environment_Render_3D(&env, &v, 1.0 / 60.0)
		assert(part.native_mesh != nil)
		assert(
			len(workspace.draw_items) == 1,
			"Offset geometry must be visible even when its Part origin is outside the frustum",
		)
		k.Kine_Filament_RenderFrame(ctx, 1.0 / 60.0)
		overlay := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginOverlay(
			compositor,
		); assert(overlay != nil)
		engine_runtime.Environment_Render_Overlay(&env, &v, overlay, 320, 240, 1.0 / 60.0)
		if frame == 4 {for y in 0 ..< 240 {for x in 0 ..< 320 {
					r, g, b, a: u8; k.Kine_Skia_Surface_GetPixel(overlay, i32(x), i32(y), &r, &g, &b, &a)
					offset :=
						(y * 320 + x) *
						3; pixels[offset] = r; pixels[offset + 1] = g; pixels[offset + 2] = b
				}}}
		assert(k.Kine_VulkanCompositor_EndFrame(compositor) != 0)
	}
	red, green := 0, 0
	for y in 60 ..< 180 {for x in 0 ..< 320 {
			i :=
				(y * 320 + x) *
				3; r, g, b := int(pixels[i]), int(pixels[i + 1]), int(pixels[i + 2])
			if r > g * 2 && r > b * 2 && r > 40 {red += 1}
			if g > r * 2 && g > b * 2 && g > 40 {green += 1}
		}}
	assert(red > 200 && green > 200, "Separate material textures must both reach the GPU")
	assert(
		green < red * 3 / 4 && green > red / 4,
		"The back-facing green quad must render double-sided with half its texture cut out",
	)
	fmt.println("MULTI_MATERIAL_PIXELS", red, green)
	file, e := os.create("build/mesh_scene_render.ppm"); assert(e == nil)
	header := "P6\n320 240\n255\n"; _, _ = os.write(file, transmute([]u8)header); _, _ = os.write(file, pixels); os.close(file)
	center, half_extent: [3]f32
	assert(k.Kine_Filament_GetMeshBounds(part.native_mesh, &center[0], &half_extent[0]))
	assert(abs(center[0] - 50) < 0.01 && abs(half_extent[0] - 3) < 0.01)


	active := cast(^classes.Camera)view.ActiveCamera; assert(active != nil)
	active.CFrame = datatypes.CFrame_LookAt_Default({50, 0, 8}, {50, 0, 16})
	engine_runtime.Environment_Render_3D(&env, &v, 1.0 / 60.0)
	assert(len(workspace.draw_items) == 0)

	active.CFrame = datatypes.CFrame_LookAt_Default({50, 0, 20}, {50, 0, 0})
	workspace.max_draw_distance = 18
	engine_runtime.Environment_Render_3D(&env, &v, 1.0 / 60.0)
	assert(len(workspace.draw_items) == 1)
	workspace.max_draw_distance = 0
	run(
		&v,
		`workspace.Scene.Size=Vector3.new(4,6,2)
workspace.Scene.CFrame=CFrame.new(10,20,0)*CFrame.Angles(0,0,math.pi/2)`,
	)
	active.CFrame = datatypes.CFrame_LookAt_Default({10, 120, 8}, {10, 120, 0})
	engine_runtime.Environment_Render_3D(&env, &v, 1.0 / 60.0)
	assert(len(workspace.draw_items) == 1, "Mesh bounds must follow rotation and nonuniform scale")

	if len(os.args) > 1 {
		run(
			&v,
			`workspace.Scene.Size=Vector3.new(2,2,2)
workspace.Scene.CFrame=CFrame.identity
workspace.Scene.MeshId="build/sponza/Sponza.glb"`,
		)

		for turn in 0 ..< 16 {
			angle := f64(turn) * 2 * math.PI / 16
			eye := datatypes.Vector3{9, 1.7, 0}
			direction := datatypes.Vector3{f32(math.cos(angle)), 0, f32(math.sin(angle))}
			active.CFrame = datatypes.CFrame_LookAt_Default(
				eye,
				datatypes.Vec3_Add(eye, direction),
			)
			engine_runtime.Environment_Render_3D(&env, &v, 1.0 / 60.0)
			assert(
				len(workspace.draw_items) == 1,
				"Sponza must not disappear when the camera turns",
			)
		}
		count := k.Kine_Filament_GetMeshMaterialCount(part.native_mesh)
		assert(count >= 25)
		unique: map[^k.KineFilamentTex]bool; defer delete(unique)
		for i in 0 ..< count {texture := k.Kine_Filament_GetMeshMaterialTexture(part.native_mesh, i); if texture != nil {unique[texture] = true}}
		assert(len(unique) >= 25)
		fmt.println("SPONZA_MATERIALS", count, "CAMERA_DIRECTIONS", 16)
	}
	fmt.println("MESH_SCENE_RENDER_SMOKE_PASSED")
}
