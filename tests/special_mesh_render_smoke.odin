package main
import assetstore "../src/engine/assetstore"
import k "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import sdl "vendor:sdl3"

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.RunInternal(v, source, "special_mesh_render"); assert(ok, err)
}
render :: proc(env: ^runtime.Environment, v: ^vm.VM) {
	ctx := env.renderer.Filament
	comp := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(ctx)
	services.Prepare_3D(&env.services, env.renderer)
	base := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(comp); assert(base != nil)
	k.Kine_Skia_Surface_Clear(base, 0, 0, 0, 255)
	runtime.Environment_Render_2D(env, v, base, 320, 240, 1.0 / 60)
	runtime.Environment_Render_3D(env, v, 1.0 / 60)
	k.Kine_Filament_RenderFrame(ctx, 1.0 / 60)
	overlay := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginOverlay(
		comp,
	); assert(overlay != nil)
	runtime.Environment_Render_Overlay(env, v, overlay, 320, 240, 1.0 / 60)
	assert(k.Kine_VulkanCompositor_EndFrame(comp) != 0)
}
main :: proc() {
	assert(sdl.Init({.VIDEO})); defer sdl.Quit()
	window := sdl.CreateWindow(
		"SpecialMesh render regression",
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
	v := vm.New(); env: runtime.Environment
	runtime.Environment_Init(&env, &v, &view)
	defer {vm.Close(&v); runtime.Environment_Destroy(&env)}
	run(
		&v,
		`
workspace.CurrentCamera.CameraType=Enum.CameraType.Scriptable
workspace.CurrentCamera.CFrame=CFrame.new(0,0,8)
for _,effect in game:GetService("Lighting"):GetChildren() do if effect:IsA("LightingEffect") then effect.Enabled=false end end
p=Instance.new("Part",workspace)
p.Name="SpecialMeshTest"
p.Anchored=true
p.Size=Vector3.new(2,2,2)
p.Position=Vector3.zero
p.Color=Color3.new(1,1,1)
m=Instance.new("SpecialMesh",p)
m.MeshType=Enum.MeshType.Sphere
m.Scale=Vector3.new(2,3,4)
m.Offset=Vector3.new(1,0,0)
m.VertexColor=Vector3.new(0.25,0.5,0.75)
`,
	)
	workspace := cast(^services.Workspace)services.Ensure_Service(&env.services, "Workspace")
	render(&env, &v)
	assert(len(workspace.draw_items) == 1)
	item := workspace.draw_items[0]
	assert(item.mesh != nil)
	assert(
		abs(item.transform[0] - 2) < 0.001 &&
		abs(item.transform[5] - 3) < 0.001 &&
		abs(item.transform[10] - 4) < 0.001,
	)
	assert(abs(item.worldPosition[0] - 1) < 0.001)
	assert(abs(item.r - 0.25) < 0.01 && abs(item.g - 0.5) < 0.01 && abs(item.b - 0.75) < 0.01)
	sphere := item.mesh
	run(
		&v,
		`
m.MeshType=Enum.MeshType.Brick
m.Scale=Vector3.one
m.Offset=Vector3.zero
m.VertexColor=Vector3.one
`,
	)
	render(&env, &v)
	assert(len(workspace.draw_items) == 1 && workspace.draw_items[0].mesh != sphere)
	run(
		&v,
		`
local hit=workspace:Raycast(Vector3.new(0,0,8),Vector3.new(0,0,-16))
assert(hit and hit.Instance==p and math.abs(hit.Distance-7)<0.05)
m.MeshType=Enum.MeshType.FileMesh
m.MeshId=""
m.Scale=Vector3.one
m.Offset=Vector3.new(1,0,0)
`,
	)

	bytes := #load("../src/engine/assets/shapes/Block.glb")
	blob := make([]u8, len(bytes)); copy(blob, bytes)
	mesh_id := assetstore.Register(blob, "block.glb", .Mesh); defer delete(mesh_id)
	ppm := "P6\n2 2\n255\n"
	texture_bytes := make([]u8, len(ppm) + 12)
	copy(texture_bytes, transmute([]u8)ppm)
	for i in len(ppm) ..< len(texture_bytes) {texture_bytes[i] = 255}
	texture_id := assetstore.Register(
		texture_bytes,
		"white.ppm",
		.Texture,
	); defer delete(texture_id)
	asset_script := fmt.aprintf(
		"m.MeshId='kineasset://%s';m.TextureId='kineasset://%s'",
		mesh_id,
		texture_id,
	); defer delete(asset_script)
	run(&v, asset_script)
	render(&env, &v)
	part := classes.Find_First_Child(&workspace.object, "SpecialMeshTest")
	mesh := classes.SpecialMesh_Find(part)
	assert(mesh.native_mesh != nil && len(workspace.draw_items) == 1)
	assert(workspace.draw_items[0].mesh == mesh.native_mesh)
	assert(abs(workspace.draw_items[0].worldPosition[0] - 1) < 0.001)
	assert(mesh.native_texture != nil && workspace.draw_items[0].tex == mesh.native_texture)
	run(&v, `m:Destroy()`)
	render(&env, &v)
	assert(len(workspace.draw_items) == 1)
	fmt.println("SPECIAL_MESH_RENDER_SMOKE_PASSED")
}
