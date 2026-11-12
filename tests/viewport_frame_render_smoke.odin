package main
import kineffi "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"
import "core:time"
import sdl3 "vendor:sdl3"

pixel :: proc(surface: ^kineffi.KineSkiaSurface, x, y: i32) -> [4]u8 {
	result: [4]u8
	kineffi.Kine_Skia_Surface_GetPixel(
		surface,
		x,
		y,
		&result[0],
		&result[1],
		&result[2],
		&result[3],
	)
	return result
}
capture_preview :: proc(
	env: ^engine_runtime.Environment,
	script_vm: ^vm.VM,
	filament: ^kineffi.KineFilamentContext,
	compositor: ^kineffi.KineVulkanCompositor,
) -> (
	signature: u64,
	coverage: int,
) {
	signature = 14695981039346656037
	for iteration in 0 ..< 2 {
		surface := cast(^kineffi.KineSkiaSurface)kineffi.Kine_VulkanCompositor_BeginFrame(
			compositor,
		)
		assert(surface != nil); kineffi.Kine_Skia_Surface_Clear(surface, 20, 30, 40, 255)
		engine_runtime.Environment_Render_2D(env, script_vm, surface, 320, 240, 1.0 / 30.0)
		if kineffi.Kine_Filament_Viewport_HasWork(
			filament,
		) {kineffi.Kine_Filament_Viewport_RenderFrame(filament, 1.0 / 30.0, false)}
		overlay := cast(^kineffi.KineSkiaSurface)kineffi.Kine_VulkanCompositor_BeginOverlay(
			compositor,
		)
		assert(
			overlay != nil,
		); engine_runtime.Environment_Render_Overlay(env, script_vm, overlay, 320, 240, 1.0 / 30.0)
		if iteration == 1 {
			for y in 0 ..< 10 {for x in 0 ..< 10 {
					c := pixel(overlay, 46 + i32(x * 12), 46 + i32(y * 12))

					for channel in c {signature = (signature ~ u64(channel / 8)) * 1099511628211}
					if abs(i32(c[0]) - 20) > 3 ||
					   abs(i32(c[1]) - 30) > 3 ||
					   abs(i32(c[2]) - 40) > 3 {coverage += 1}
				}}
		}
		assert(kineffi.Kine_VulkanCompositor_EndFrame(compositor) != 0)
	}
	return
}
main :: proc() {
	assert(sdl3.Init({.VIDEO})); defer sdl3.Quit()
	window := sdl3.CreateWindow(
		"ViewportFrame GUI regression",
		320,
		240,
		sdl3.WINDOW_VULKAN | sdl3.WINDOW_HIDDEN,
	)
	assert(window != nil); defer sdl3.DestroyWindow(window)
	filament := kineffi.Kine_Filament_CreateForVulkanCompositorWindow(window, 320, 240)
	assert(filament != nil); defer kineffi.Kine_Filament_Destroy(filament)
	renderer_object := renderer.RendererObject {
		Filament = filament,
	}
	script_vm := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm, &renderer_object)
	defer {vm.Close(&script_vm); engine_runtime.Environment_Destroy(&env)}
	ok, err := vm.Run(
		&script_vm,
		`
local screen=Instance.new("ScreenGui",game.CoreGui)
preview=Instance.new("ViewportFrame",screen)
preview.Position=UDim2.fromOffset(40,40)
preview.Size=UDim2.fromOffset(128,128)
preview.BackgroundTransparency=1
preview.Ambient=Color3.new(1,1,1)
preview.LightColor=Color3.new(0,0,0)
local camera=Instance.new("Camera",preview)
camera.CFrame=CFrame.new(0,0,6)
preview.CurrentCamera=camera
part=Instance.new("Part",preview)
part.Anchored=true
part.Size=Vector3.new(3,3,3)
part.Color=Color3.new(1,0,0)
local badge=Instance.new("Frame",preview)
badge.Size=UDim2.fromOffset(8,8)
badge.Position=UDim2.fromOffset(60,60)
badge.BackgroundColor3=Color3.new(0,0,1)
`,
		"viewport_frame_render",
	)
	if !ok {fmt.eprintln(err); panic("GUI setup failed")}
	compositor := cast(^kineffi.KineVulkanCompositor)kineffi.Kine_Filament_GetVulkanCompositor(
		filament,
	)
	for index in 0 ..< 4 {
		if index == 2 {
			ok, err = vm.Run(&script_vm, "part.Color=Color3.new(0,1,0)", "animate_preview")
			assert(ok, err)
		}
		surface := cast(^kineffi.KineSkiaSurface)kineffi.Kine_VulkanCompositor_BeginFrame(
			compositor,
		)
		assert(surface != nil)
		kineffi.Kine_Skia_Surface_Clear(surface, 20, 30, 40, 255)
		engine_runtime.Environment_Render_2D(&env, &script_vm, surface, 320, 240, 1.0 / 30.0)
		if kineffi.Kine_Filament_Viewport_HasWork(
			filament,
		) {kineffi.Kine_Filament_Viewport_RenderFrame(filament, 1.0 / 30.0, false)}
		overlay := cast(^kineffi.KineSkiaSurface)kineffi.Kine_VulkanCompositor_BeginOverlay(
			compositor,
		)
		assert(overlay != nil)
		engine_runtime.Environment_Render_Overlay(&env, &script_vm, overlay, 320, 240, 1.0 / 30.0)
		if index == 1 || index == 3 {
			center, badge, outside :=
				pixel(overlay, 95, 104), pixel(overlay, 104, 104), pixel(overlay, 42, 42)
			fmt.printf(
				"GUI pixels frame=%d object=%v badge=%v outside=%v\n",
				index,
				center,
				badge,
				outside,
			)
			if index ==
			   1 {assert(center[0] > center[1] + 40, "preview did not draw red")} else {assert(center[1] > center[0] + 40, "preview animation did not draw green")}
			assert(badge[2] > 200 && badge[0] < 40, "GUI descendant must draw above preview")
			assert(
				abs(i32(outside[0]) - 20) <= 2 &&
				abs(i32(outside[1]) - 30) <= 2 &&
				abs(i32(outside[2]) - 40) <= 2,
				"preview background must stay transparent",
			)
		}
		assert(kineffi.Kine_VulkanCompositor_EndFrame(compositor) != 0)
	}
	ok, err = vm.Run(
		&script_vm,
		`
preview:FindFirstChild("Frame"):Destroy()
part.Color=Color3.new(0.65,0.65,0.65)
part.Material=Enum.Material.debug
preview.LightColor=Color3.new(1,1,1)
preview.CurrentCamera.CFrame=CFrame.lookAt(Vector3.new(4,3,6),Vector3.zero)
`,
		"shape_setup",
	)
	assert(ok, err)
	ball_signature, block_signature: u64
	shapes := []string {
		"Ball",
		"Block",
		"Cylinder",
		"Wedge",
		"CornerWedge",
		"Cone",
		"Pyramid",
		"Truss",
		"Torus",
		"TriangleWedge",
		"Capsule",
	}
	for shape in shapes {
		command := fmt.tprintf("part.Shape=Enum.PartType.%s", shape)
		ok, err = vm.Run(&script_vm, command, "preview_shape"); assert(ok, err)
		signature, coverage := capture_preview(&env, &script_vm, filament, compositor)
		fmt.printf("SHAPE %s coverage=%d\n", shape, coverage)
		assert(coverage > 0, "preview shape did not render")
		if shape ==
		   "Ball" {ball_signature = signature}; if shape == "Block" {block_signature = signature}
	}
	assert(ball_signature != block_signature, "different shapes produced identical previews")
	material_names := []string {
		"SmoothPlastic",
		"Wood",
		"Brick",
		"Grass",
		"Concrete",
		"Slate",
		"Glass",
		"Neon",
		"Sand",
		"Water",
		"debug",
	}
	wood_signature, brick_signature: u64
	descriptor := classes.Find_Class(&env.classes, "ViewportFrame")
	preview := cast(^classes.ViewportFrame)descriptor.instances[0]
	for material in material_names {
		command := fmt.tprintf(
			"part.Shape=Enum.PartType.Ball;part.Material=Enum.Material.%s;part.Transparency=0",
			material,
		)
		ok, err = vm.Run(&script_vm, command, "preview_material"); assert(ok, err)
		signature, coverage := capture_preview(&env, &script_vm, filament, compositor)
		if material == "Wood" || material == "Brick" {
			// Built-in textures are decoded on a worker and published during rendering.
			started := time.tick_now()
			for len(preview.items) == 1 && preview.items[0].tex == nil && time.tick_since(started) < 3 * time.Second {
				signature, coverage = capture_preview(&env, &script_vm, filament, compositor)
			}
			assert(len(preview.items) == 1 && preview.items[0].tex != nil, "material texture was not submitted")
		}
		fmt.printf("MATERIAL %s coverage=%d\n", material, coverage)
		assert(coverage > 0, "preview material did not render")
		if material ==
		   "Wood" {wood_signature = signature}; if material == "Brick" {brick_signature = signature}
		assert(len(preview.items) == 1 && preview.items[0].mesh != nil)
	}
	assert(wood_signature != brick_signature, "Wood and Brick produced identical previews")
	ok, err = vm.Run(&script_vm, "preview.Visible=false", "hide_preview")
	assert(ok, err)
	surface := cast(^kineffi.KineSkiaSurface)kineffi.Kine_VulkanCompositor_BeginFrame(compositor)
	assert(surface != nil)
	kineffi.Kine_Skia_Surface_Clear(surface, 20, 30, 40, 255)
	engine_runtime.Environment_Render_2D(&env, &script_vm, surface, 320, 240, 1.0 / 30.0)
	alive, pages: u32
	kineffi.Kine_Filament_Viewport_Stats(filament, &alive, &pages, nil)
	assert(alive == 0 && pages == 1, "hidden previews should release native scenes and slots")
	assert(!kineffi.Kine_Filament_Viewport_HasWork(filament))
	assert(kineffi.Kine_VulkanCompositor_EndFrame(compositor) != 0)
	fmt.println("VIEWPORT_FRAME_RENDER_SMOKE_PASSED")
}
