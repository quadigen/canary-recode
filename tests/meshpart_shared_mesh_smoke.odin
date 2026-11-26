package main

import assetstore "../src/engine/assetstore"
import k "../src/engine/bindings"
import classes "../src/engine/classes"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import sdl "vendor:sdl3"

new_meshpart :: proc(path: string, index: u32 = 0) -> ^classes.MeshPart {
	mesh := new(classes.MeshPart)
	mesh^ = classes.MeshPart_Init()
	mesh.mesh_id = strings.clone(path)
	mesh.mesh_index = index
	return mesh
}

free_meshpart :: proc(mesh: ^classes.MeshPart) {
	if mesh == nil {return}
	classes.MeshPart_Release_Native_Mesh(mesh)
	delete(mesh.mesh_id)
	delete(mesh.native_mesh_id)
	delete(mesh.texture_id)
	delete(mesh.collision_group)
	free(mesh)
}

cache_ownership_smoke :: proc() {

	ctx_a := cast(^k.KineFilamentContext)(uintptr(0x10000))
	ctx_b := cast(^k.KineFilamentContext)(uintptr(0x20000))
	mesh_a := cast(^k.KineFilamentMesh)(uintptr(0x30000))
	mesh_b := cast(^k.KineFilamentMesh)(uintptr(0x40000))

	assert(classes.Shared_Mesh_Cache_Entry_Count() == 0)
	assert(classes.Shared_Mesh_Register(ctx_a, "asset:one", 0, 10, true, mesh_a) == mesh_a)
	assert(classes.Shared_Mesh_Cache_References(mesh_a) == 1)
	assert(classes.Shared_Mesh_Acquire(ctx_a, "asset:one", 0, 10, true) == mesh_a)
	assert(classes.Shared_Mesh_Cache_References(mesh_a) == 2)

	assert(classes.Shared_Mesh_Acquire(ctx_b, "asset:one", 0, 10, true) == nil)
	assert(classes.Shared_Mesh_Acquire(ctx_a, "asset:one", 1, 10, true) == nil)
	assert(classes.Shared_Mesh_Acquire(ctx_a, "asset:one", 0, 11, true) == nil)
	assert(classes.Shared_Mesh_Acquire(ctx_a, "asset:one", 0, 10, false) == nil)
	assert(!classes.Shared_Mesh_Release(ctx_b, mesh_a, false))
	assert(classes.Shared_Mesh_Cache_References(mesh_a) == 2)

	assert(classes.Shared_Mesh_Register(ctx_b, "asset:one", 0, 10, true, mesh_b) == mesh_b)
	assert(classes.Shared_Mesh_Cache_Entry_Count() == 2)
	assert(classes.Shared_Mesh_Release(ctx_a, mesh_a, false))
	assert(classes.Shared_Mesh_Cache_References(mesh_a) == 1)
	assert(classes.Shared_Mesh_Acquire(ctx_a, "asset:one", 0, 10, true) == mesh_a)
	assert(classes.Shared_Mesh_Cache_References(mesh_a) == 2)
	assert(classes.Shared_Mesh_Release(ctx_a, mesh_a, false))
	assert(classes.Shared_Mesh_Release(ctx_a, mesh_a, false))
	assert(classes.Shared_Mesh_Cache_References(mesh_a) == 0)
	assert(classes.Shared_Mesh_Acquire(ctx_a, "asset:one", 0, 10, true) == nil)
	assert(classes.Shared_Mesh_Cache_Entry_Count() == 1)
	assert(classes.Shared_Mesh_Release(ctx_b, mesh_b, false))
	assert(classes.Shared_Mesh_Cache_Entry_Count() == 0)
}

main :: proc() {
	cache_ownership_smoke()
	fmt.println("SHARED_MESH_REFCOUNT_SMOKE_PASSED")

	assert(sdl.Init({.VIDEO}))
	defer sdl.Quit()
	window := sdl.CreateWindow(
		"Kinemium shared imported mesh",
		320,
		240,
		sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN,
	)
	assert(window != nil)
	defer sdl.DestroyWindow(window)
	ctx := k.Kine_Filament_CreateForVulkanCompositorWindow(window, 320, 240)
	assert(ctx != nil)
	defer k.Kine_Filament_Destroy(ctx)

	path := "src/engine/assets/shapes/Block.glb"
	first := new_meshpart(path)
	second := new_meshpart(path)
	defer free_meshpart(first)
	defer free_meshpart(second)

	first_handle := services.workspace_meshpart_mesh(first, ctx)
	assert(first_handle != nil)
	second_handle := services.workspace_meshpart_mesh(second, ctx)
	assert(second_handle == first_handle, "same MeshId must share an imported GPU mesh")
	assert(classes.Shared_Mesh_Cache_Entry_Count() == 1)
	assert(classes.Shared_Mesh_Cache_References(first_handle) == 2)


	classes.MeshPart_Release_Native_Mesh(first)
	assert(classes.Shared_Mesh_Cache_References(second_handle) == 1)
	assert(services.workspace_meshpart_mesh(second, ctx) == second_handle)


	clones := make([]^classes.MeshPart, 80)
	started := time.tick_now()
	for &item in clones {
		item = new_meshpart(path)
		assert(services.workspace_meshpart_mesh(item, ctx) == second_handle)
	}
	fmt.printf(
		"80 repeated MeshParts acquired in %.3f ms\n",
		f64(time.tick_since(started)) / f64(time.Millisecond),
	)
	assert(classes.Shared_Mesh_Cache_Entry_Count() == 1)
	assert(classes.Shared_Mesh_Cache_References(second_handle) == 81)


	indexed := new_meshpart(path, 1)
	indexed_handle := services.workspace_meshpart_mesh(indexed, ctx)
	if indexed_handle != nil {
		assert(indexed_handle != second_handle)
		assert(classes.Shared_Mesh_Cache_Entry_Count() == 2)
	}


	raw, err := os.read_entire_file(path, context.allocator)
	assert(err == nil)
	asset_id := assetstore.Register(raw, path, .Mesh)
	assert(asset_id != "")
	asset_uri := assetstore.Make_Uri(asset_id)
	embedded_a := new_meshpart(asset_uri)
	embedded_b := new_meshpart(asset_uri)
	embedded_handle := services.workspace_meshpart_mesh(embedded_a, ctx)
	assert(embedded_handle != nil)
	assert(embedded_handle != second_handle)
	assert(services.workspace_meshpart_mesh(embedded_b, ctx) == embedded_handle)
	assert(classes.Shared_Mesh_Cache_References(embedded_handle) == 2)


	delete(embedded_a.mesh_id)
	embedded_a.mesh_id = strings.clone("src/engine/assets/shapes/Ball.glb")
	replacement := services.workspace_meshpart_mesh(embedded_a, ctx)
	assert(replacement != nil && replacement != embedded_handle)
	assert(classes.Shared_Mesh_Cache_References(embedded_handle) == 1)
	assert(services.workspace_meshpart_mesh(embedded_b, ctx) == embedded_handle)

	for item in clones {free_meshpart(item)}
	delete(clones)
	free_meshpart(indexed)
	free_meshpart(embedded_a)
	free_meshpart(embedded_b)
	delete(asset_uri)
	delete(asset_id)

	assert(classes.Shared_Mesh_Cache_References(second_handle) == 1)
	classes.MeshPart_Release_Native_Mesh(second)
	assert(classes.Shared_Mesh_Cache_Entry_Count() == 0)


	temp_dir, temp_err := os.make_directory_temp("", "kinemium-shared-mesh-*", context.allocator)
	assert(temp_err == nil)
	defer {_ = os.remove_all(temp_dir); delete(temp_dir)}
	edit_path, join_err := os.join_path([]string{temp_dir, "source.glb"}, context.allocator)
	assert(join_err == nil)
	defer delete(edit_path)

	block_bytes, read_err := os.read_entire_file(path, context.allocator)
	assert(read_err == nil)
	defer delete(block_bytes)
	assert(os.write_entire_file(edit_path, block_bytes) == nil)

	old_a := new_meshpart(edit_path)
	old_b := new_meshpart(edit_path)
	old_handle := services.workspace_meshpart_mesh(old_a, ctx)
	assert(old_handle != nil)
	assert(services.workspace_meshpart_mesh(old_b, ctx) == old_handle)

	ball_bytes, ball_err := os.read_entire_file(
		"src/engine/assets/shapes/Ball.glb",
		context.allocator,
	)
	assert(ball_err == nil)
	defer delete(ball_bytes)
	assert(os.write_entire_file(edit_path, ball_bytes) == nil)
	new_owner := new_meshpart(edit_path)
	new_handle := services.workspace_meshpart_mesh(new_owner, ctx)
	assert(new_handle != nil && new_handle != old_handle)
	assert(classes.Shared_Mesh_Cache_Entry_Count() == 2)
	assert(classes.Shared_Mesh_Cache_References(old_handle) == 2)
	assert(classes.Shared_Mesh_Cache_References(new_handle) == 1)
	free_meshpart(old_a)
	free_meshpart(old_b)
	assert(classes.Shared_Mesh_Cache_Entry_Count() == 1)
	assert(services.workspace_meshpart_mesh(new_owner, ctx) == new_handle)
	free_meshpart(new_owner)
	assert(classes.Shared_Mesh_Cache_Entry_Count() == 0)


	view := renderer.RendererObject {
		Filament        = ctx,
		HasViewportRect = true,
		ViewportRect    = {0, 0, 320, 240},
	}
	script_vm := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &script_vm, &view)
	defer {vm.Close(&script_vm); engine_runtime.Environment_Destroy(&env)}

	script := `
sharedA = Instance.new("MeshPart", workspace)
sharedA.Name = "SharedA"
sharedA.MeshId = "src/engine/assets/shapes/Block.glb"
sharedB = sharedA:Clone()
sharedB.Name = "SharedB"
sharedB.Parent = workspace
assert(sharedB.MeshId == sharedA.MeshId)
`
	ok, script_error := vm.Run(&script_vm, script, "shared_mesh_create")
	assert(ok, script_error)

	workspace := services.Ensure_Service(&env.services, "Workspace")
	first_object := classes.Find_First_Child(workspace, "SharedA")
	second_object := classes.Find_First_Child(workspace, "SharedB")
	assert(first_object != nil && second_object != nil)
	lua_a := cast(^classes.MeshPart)first_object
	lua_b := cast(^classes.MeshPart)second_object
	lua_handle := services.workspace_meshpart_mesh(lua_a, ctx)
	assert(lua_handle != nil && services.workspace_meshpart_mesh(lua_b, ctx) == lua_handle)
	assert(classes.Shared_Mesh_Cache_References(lua_handle) == 2)

	ok, script_error = vm.Run(
		&script_vm,
		`sharedA.MeshId = sharedA.MeshId`,
		"meshpart_same_id_reassign",
	)
	assert(ok, script_error)
	assert(classes.Shared_Mesh_Cache_References(lua_handle) == 1)
	assert(services.workspace_meshpart_mesh(lua_a, ctx) == lua_handle)
	assert(classes.Shared_Mesh_Cache_References(lua_handle) == 2)

	ok, script_error = vm.Run(&script_vm, `sharedA:Destroy()`, "shared_mesh_destroy_first")
	assert(ok, script_error)


	classes.Flush_Pending_Destroy(&env.classes)
	assert(classes.Shared_Mesh_Cache_References(lua_handle) == 1)
	assert(services.workspace_meshpart_mesh(lua_b, ctx) == lua_handle)

	ok, script_error = vm.Run(&script_vm, `sharedB:Destroy()`, "shared_mesh_destroy_last")
	assert(ok, script_error)
	classes.Flush_Pending_Destroy(&env.classes)
	assert(classes.Shared_Mesh_Cache_Entry_Count() == 0)
	fmt.println("SHARED_MESHPART_GPU_SMOKE_PASSED")
}
