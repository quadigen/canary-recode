package main

import k "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"

check_import :: proc(path: cstring, expected_vertices, expected_indices: i32) {
	data := k.Kine_Filament_LoadMeshDataFromPath(path)
	assert(data != nil)
	defer k.Kine_Filament_DestroyMeshData(data)
	vertices := k.Kine_Filament_GetMeshDataVertexCount(data)
	count := k.Kine_Filament_GetMeshDataIndexCount(data)
	fmt.printf("Mesh counts: %d vertices, %d indices\n", vertices, count)
	assert(vertices == expected_vertices)
	assert(vertices > 65535)
	assert(count == expected_indices)
	indices := make([]u32, int(count)); defer delete(indices)
	assert(k.Kine_Filament_CopyMeshDataIndices(data, raw_data(indices), count) != 0)
	maximum: u32
	for index in indices {assert(index < u32(vertices)); maximum = max(maximum, index)}
	assert(maximum == u32(vertices - 1))
	fmt.printf(
		"Imported %s: %d vertices, %d triangles, max index %d\n",
		path,
		vertices,
		count / 3,
		maximum,
	)
}

main :: proc() {
	assert(sdl.Init({.VIDEO})); defer sdl.Quit()
	window := sdl.CreateWindow(
		"Large mesh import",
		960,
		640,
		sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN,
	)
	assert(window != nil); defer sdl.DestroyWindow(window)
	ctx := k.Kine_Filament_CreateForVulkanCompositorWindow(window, 960, 640)
	assert(ctx != nil); defer k.Kine_Filament_Destroy(ctx)

	vertices := make([]f32, 70002 * 8); defer delete(vertices)
	indices := make([]u32, 70002); defer delete(indices)
	obj: strings.Builder; defer strings.builder_destroy(&obj)
	for i in 0 ..< 70002 {
		x, y := f32(i % 300), f32(i / 300) + f32(i % 3 == 2 ? 1 : 0) * 0.5
		vertices[i * 8] = x; vertices[i * 8 + 1] = y; vertices[i * 8 + 5] = 1
		indices[i] = u32(i)
		fmt.sbprintf(&obj, "v %f %f 0\n", x, y)
	}
	for i in 0 ..< 70002 / 3 {fmt.sbprintf(&obj, "f %d %d %d\n", i * 3 + 1, i * 3 + 2, i * 3 + 3)}
	assert(
		os.write_entire_file("build/large_mesh.obj", transmute([]u8)strings.to_string(obj)) == nil,
	)
	check_import("build/large_mesh.obj", 70002, 70002)
	mesh := k.Kine_Filament_CreateCustomMeshEx32(
		ctx,
		raw_data(vertices),
		nil,
		70002,
		raw_data(indices),
		70002,
	)
	assert(mesh != nil)
	assert(k.Kine_Filament_UpdateCustomMesh(ctx, mesh, raw_data(vertices), 70002) != 0)
	k.Kine_Filament_DestroyMesh(ctx, mesh)
	indices[70001] = 70002
	assert(
		k.Kine_Filament_CreateCustomMesh32(
			ctx,
			raw_data(vertices),
			70002,
			raw_data(indices),
			70002,
		) ==
		nil,
	)
	small := [3]u16{0, 1, 2}
	mesh = k.Kine_Filament_CreateCustomMesh(ctx, raw_data(vertices), 3, &small[0], 3)
	assert(mesh != nil); k.Kine_Filament_DestroyMesh(ctx, mesh)

	view := renderer.RendererObject {
		Filament        = ctx,
		HasViewportRect = true,
		ViewportRect    = {0, 0, 960, 640},
	}
	v := vm.New(); env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &v, &view)
	defer {vm.Close(&v); engine_runtime.Environment_Destroy(&env)}
	source := `
workspace.CurrentCamera.CameraType=Enum.CameraType.Scriptable
workspace.CurrentCamera.CFrame=CFrame.new(0,0,8)
local editable=Instance.new("EditableMesh")
for i=0,69999 do editable:AddVertex(Vector3.new(i,0,0)) end
local a=editable:AddVertex(Vector3.new(-1,-1,0))
local b=editable:AddVertex(Vector3.new(1,-1,0))
local c=editable:AddVertex(Vector3.new(0,1,0))
-- More than 65k rendered corners. Only the last triangle is visible.
for i=1,22000 do editable:AddTriangle(0,1,2) end
editable:AddTriangle(a,b,c)
local part=Instance.new("MeshPart",workspace)
part.Anchored=true; part.MeshContent=Content.fromObject(editable)
part.Size=Vector3.new(70000,2,2); part.CFrame=CFrame.new(34999,0,0)
part.Material=Enum.Material.SmoothPlastic; part.Color=Color3.new(1,0,0)
`
	if len(os.args) > 1 {
		check_import("build/sponza/Sponza.gltf", 192492, 786801)
		check_import("build/sponza/Sponza.glb", 192492, 786801)
		bytes, read_error := os.read_entire_file(
			"build/sponza/Sponza.glb",
			context.allocator,
		); assert(read_error == nil); defer delete(bytes)
		mesh = k.Kine_Filament_CreateMeshFromMemory(
			ctx,
			raw_data(bytes),
			uintptr(len(bytes)),
			"glb",
		)
		assert(mesh != nil); k.Kine_Filament_DestroyMesh(ctx, mesh)
		source = `
workspace.CurrentCamera.CameraType=Enum.CameraType.Scriptable
workspace.CurrentCamera.CFrame=CFrame.lookAt(Vector3.new(9,1.7,0),Vector3.new(-6,3.5,0))
workspace.CurrentCamera.FieldOfView=70
for _,effect in game:GetService("Lighting"):GetChildren() do
    if effect:IsA("LightingEffect") then effect.Enabled=false end
end
local part=Instance.new("MeshPart",workspace)
part.Anchored=true; part.MeshId="build/sponza/Sponza.glb"; part.Size=Vector3.new(2,2,2)
part.Color=Color3.new(1,1,1)
`
	}
	ok, err := vm.Run(&v, source, "large_mesh_smoke"); assert(ok, err)
	compositor := cast(^k.KineVulkanCompositor)k.Kine_Filament_GetVulkanCompositor(ctx)
	pixels := make([]u8, 960 * 640 * 3); defer delete(pixels)
	red_pixels := 0
	for frame in 0 ..< 5 {
		services.Prepare_3D(&env.services, &view)
		base := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginFrame(
			compositor,
		); assert(base != nil)
		k.Kine_Skia_Surface_Clear(base, 24, 27, 35, 255)
		engine_runtime.Environment_Render_2D(&env, &v, base, 960, 640, 1.0 / 60.0)
		engine_runtime.Environment_Render_3D(&env, &v, 1.0 / 60.0)
		part := cast(^classes.MeshPart)classes.Find_First_Child_Of_Class(
			services.Ensure_Service(&env.services, "Workspace"),
			"MeshPart",
		)
		assert(
			part != nil && part.native_mesh != nil,
			"Imported geometry must render without the fallback cube",
		)
		k.Kine_Filament_RenderFrame(ctx, 1.0 / 60.0)
		overlay := cast(^k.KineSkiaSurface)k.Kine_VulkanCompositor_BeginOverlay(
			compositor,
		); assert(overlay != nil)
		engine_runtime.Environment_Render_Overlay(&env, &v, overlay, 960, 640, 1.0 / 60.0)
		if frame == 4 {for y in 0 ..< 640 {for x in 0 ..< 960 {
					r, g, b, a: u8
					k.Kine_Skia_Surface_GetPixel(overlay, i32(x), i32(y), &r, &g, &b, &a)
					offset :=
						(y * 960 + x) *
						3; pixels[offset] = r; pixels[offset + 1] = g; pixels[offset + 2] = b
					if int(r) > int(g) * 2 && int(r) > int(b) * 2 && r > 80 {red_pixels += 1}
				}}}
		assert(k.Kine_VulkanCompositor_EndFrame(compositor) != 0)
	}
	fmt.println("Visible red pixels:", red_pixels)
	output := len(os.args) > 1 ? "build/sponza/render.ppm" : "build/large_mesh.ppm"
	file, e := os.create(output); assert(e == nil); defer os.close(file)
	header := "P6\n960 640\n255\n"; _, _ = os.write(file, transmute([]u8)header); _, _ = os.write(file, pixels)
	if len(os.args) ==
	   1 {assert(red_pixels > 1000, "Final editable triangle above 65k corners must render")}
	if len(os.args) > 1 {
		saved, save_error := vm.RunInternal(
			&v,
			`assert(game:GetService("ExportService"):ExportToFile("build/sponza/Sponza.kine"))`,
			"save_sponza",
		)
		assert(saved, save_error)
	}
	fmt.println("LARGE_MESH_SMOKE_PASSED", output)
}
