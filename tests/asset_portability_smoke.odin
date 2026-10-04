// A .kine file is only portable if the bytes a map points at travel inside it.
// This writes real asset files, points real properties at them, serializes,
// deletes the sources, and then checks the blobs still resolve from the loaded
// map. Anything that silently kept reading from disk fails here.
package main

import "core:fmt"
import "core:os"
import "core:strings"
import engine_runtime "../src/engine/runtime"
import assetstore "../src/engine/assetstore"
import classes "../src/engine/classes"
import serializer "../src/engine/serializer"
import vm "../src/engine/vm"

MESH_BODY :: "mesh bytes that are not really an fbx but are definitely bytes"
TEXTURE_BODY :: "texture bytes that are not really a png but are definitely bytes"
DECAL_BODY :: "decal bytes, also not a real image, also definitely bytes"
MISSING_PATH :: "does/not/exist.fbx"

run_script_or_fail :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln("script failed:", name, err)
		delete(err)
		panic(name)
	}
}

scratch_directory :: proc() -> string {
	root, root_err := os.temp_dir(context.allocator)
	if root_err != nil {
		panic("could not resolve a temp directory")
	}
	defer delete(root)

	dir, join_err := os.join_path([]string{root, "kine_asset_smoke"}, context.allocator)
	if join_err != nil {
		panic("could not build the scratch directory")
	}
	os.remove_all(dir)
	if os.make_directory(dir) != nil {
		panic("could not create the scratch directory")
	}
	return dir
}

// write_asset creates a file inside dir and returns its path.
write_asset :: proc(dir, name, body: string) -> string {
	path, join_err := os.join_path([]string{dir, name}, context.allocator)
	if join_err != nil {
		panic("could not build an asset path")
	}
	if os.write_entire_file(path, body) != nil {
		panic(fmt.tprintf("could not write %s", name))
	}
	return path
}

// read_global_string copies a string global out of the script VM.
read_global_string :: proc(script_vm: ^vm.VM, name: string) -> string {
	vm.GetGlobal(script_vm.L, name)
	value := strings.clone(vm.ArgString(script_vm.L, -1))
	vm.Pop(script_vm.L)
	return value
}

read_global_number :: proc(script_vm: ^vm.VM, name: string) -> f64 {
	vm.GetGlobal(script_vm.L, name)
	value := vm.ArgNumber(script_vm.L, -1)
	vm.Pop(script_vm.L)
	return value
}

read_global_bool :: proc(script_vm: ^vm.VM, name: string) -> bool {
	vm.GetGlobal(script_vm.L, name)
	value := vm.ArgBoolean(script_vm.L, -1)
	vm.Pop(script_vm.L)
	return value
}

expect_bytes :: proc(label, uri, want: string) {
	if !assetstore.Is_Uri(uri) {
		panic(fmt.tprintf("%s: %q is not an embedded reference", label, uri))
	}
	data, found := assetstore.Resolve_Bytes(uri)
	if !found {
		panic(fmt.tprintf("%s: %s did not resolve to an embedded asset", label, uri))
	}
	if string(data) != want {
		panic(fmt.tprintf("%s: embedded bytes differ from the source file", label))
	}
}

expect_kept_as_path :: proc(label, uri, want: string) {
	if uri != want {
		panic(fmt.tprintf("%s: expected the bare path %q, got %q", label, want, uri))
	}
	if assetstore.Is_Uri(uri) {
		panic(fmt.tprintf("%s: %q was rewritten to an embedded reference", label, uri))
	}
}

main :: proc() {
	// A clean store proves the file carries its own bytes rather than relying on
	// whatever the serializing process happened to still hold in memory.
	assetstore.Clear()

	scratch := scratch_directory()
	defer os.remove_all(scratch)

	mesh_path := write_asset(scratch, "hero.fbx", MESH_BODY)
	texture_path := write_asset(scratch, "hero_diffuse.png", TEXTURE_BODY)
	decal_path := write_asset(scratch, "scorch.png", DECAL_BODY)

	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	// Build a map the way an author would: real classes pointing at real files.
	run_script_or_fail(
		&script_vm,
		fmt.tprintf(
			`
local model = Instance.new("Model")
model.Name = "Rig"

local mesh = Instance.new("MeshPart", model)
mesh.Name = "Body"
mesh.MeshId = %q
mesh.TextureId = %q

local decal = Instance.new("Decal", model)
decal.Name = "Scorch"
decal.Texture = %q

model.Parent = game.Workspace
KineRoot = model
`,
			mesh_path,
			texture_path,
			decal_path,
		),
		"asset_build",
	)

	vm.GetGlobal(script_vm.L, "KineRoot")
	root := cast(^classes.Object)vm.UserdataValue(script_vm.L, -1)
	vm.Pop(script_vm.L)
	if root == nil {
		panic("KineRoot global missing")
	}

	// The legacy stream is written first, from the same tree, so its paths are
	// still on disk when the version 2 reader is exercised below.
	legacy, legacy_err := serializer.Serialize_Legacy(&environment.classes, script_vm.L, root)
	if !serializer.Error_Is_None(legacy_err) || legacy == nil {
		panic(fmt.tprintf("legacy serialize failed: %s", serializer.Error_String(legacy_err)))
	}
	serializer.Error_Delete(&legacy_err)
	defer delete(legacy)
	if legacy[4] != u8(serializer.KINE_LEGACY_VERSION) {
		panic("the legacy stream is not tagged as version 2")
	}

	stream, err := serializer.Serialize(&environment.classes, script_vm.L, root)
	if !serializer.Error_Is_None(err) || stream == nil {
		panic(fmt.tprintf("serialize failed: %s", serializer.Error_String(err)))
	}
	serializer.Error_Delete(&err)
	defer delete(stream)
	if stream[4] != u8(serializer.KINE_VERSION) {
		panic("the stream is not tagged as the current version")
	}
	fmt.printf("serialized %d bytes, %d embedded assets\n", len(stream), assetstore.Count())

	// Deleting the sources is the whole point: if anything still reads from disk
	// the checks below fail instead of quietly passing.
	for path in ([]string{mesh_path, texture_path, decal_path}) {
		if os.remove(path) != nil {
			panic(fmt.tprintf("could not delete %s", path))
		}
	}
	if os.exists(mesh_path) {
		panic("the mesh source survived deletion")
	}

	assetstore.Clear()
	if assetstore.Count() != 0 {
		panic("the asset store did not clear")
	}

	parent, parent_ok := classes.Push_New(&environment.classes, &script_vm, "Folder", true)
	if !parent_ok || parent == nil {
		panic("could not create a Folder")
	}
	vm.Pop(script_vm.L)

	loaded, load_err := serializer.Deserialize(&environment.classes, script_vm.L, parent, stream)
	if !serializer.Error_Is_None(load_err) || loaded == nil {
		panic(fmt.tprintf("deserialize failed: %s", serializer.Error_String(load_err)))
	}
	serializer.Error_Delete(&load_err)
	vm.PushRegistryReference(script_vm.L, loaded.lua_ref)
	vm.SetGlobalFromStack(&script_vm, "LoadedRoot")

	// Property values stay kineasset:// references so an editor round-trip still
	// shows something meaningful, and the store holds the bytes behind them.
	run_script_or_fail(
		&script_vm,
		`
local mesh = LoadedRoot:FindFirstChild("Body")
assert(mesh ~= nil, "mesh part survived")
local decal = LoadedRoot:FindFirstChild("Scorch")
assert(decal ~= nil, "decal survived")

KineMeshValue = mesh.MeshId
KineTextureValue = mesh.TextureId
KineDecalValue = decal.Texture
`,
		"asset_verify",
	)

	mesh_value := read_global_string(&script_vm, "KineMeshValue")
	defer delete(mesh_value)
	texture_value := read_global_string(&script_vm, "KineTextureValue")
	defer delete(texture_value)
	decal_value := read_global_string(&script_vm, "KineDecalValue")
	defer delete(decal_value)

	expect_bytes("MeshId", mesh_value, MESH_BODY)
	expect_bytes("TextureId", texture_value, TEXTURE_BODY)
	expect_bytes("Decal.Texture", decal_value, DECAL_BODY)

	// A path that was never there keeps its original value rather than silently
	// becoming an empty reference.
	run_script_or_fail(
		&script_vm,
		fmt.tprintf(
			`
local model = Instance.new("Model")
model.Name = "Missing"
local mesh = Instance.new("MeshPart", model)
mesh.MeshId = %q
model.Parent = game.Workspace
KineRoot = model
`,
			MISSING_PATH,
		),
		"asset_missing_build",
	)
	vm.GetGlobal(script_vm.L, "KineRoot")
	missing_root := cast(^classes.Object)vm.UserdataValue(script_vm.L, -1)
	vm.Pop(script_vm.L)
	missing_stream, missing_err := serializer.Serialize(&environment.classes, script_vm.L, missing_root)
	defer delete(missing_stream)
	if !serializer.Error_Is_None(missing_err) {
		serializer.Error_Delete(&missing_err)
		panic("serializing a map with a missing asset failed")
	}
	serializer.Error_Delete(&missing_err)
	missing_parent, missing_parent_ok := classes.Push_New(&environment.classes, &script_vm, "Folder", true)
	if !missing_parent_ok || missing_parent == nil {
		panic("could not create a Folder for the missing-asset map")
	}
	vm.Pop(script_vm.L)
	missing_loaded, missing_load_err :=
		serializer.Deserialize(&environment.classes, script_vm.L, missing_parent, missing_stream)
	if !serializer.Error_Is_None(missing_load_err) || missing_loaded == nil {
		panic(fmt.tprintf("loading the missing-asset map failed: %s", serializer.Error_String(missing_load_err)))
	}
	serializer.Error_Delete(&missing_load_err)
	vm.PushRegistryReference(script_vm.L, missing_loaded.lua_ref)
	vm.SetGlobalFromStack(&script_vm, "MissingRoot")
	run_script_or_fail(
		&script_vm,
		`
KineMissingValue = MissingRoot.MeshPart.MeshId
`,
		"asset_missing_verify",
	)
	missing_value := read_global_string(&script_vm, "KineMissingValue")
	defer delete(missing_value)
	expect_kept_as_path("a missing file", missing_value, MISSING_PATH)

	// Non-file schemes are never embedded and never rewritten.
	run_script_or_fail(
		&script_vm,
		fmt.tprintf(
			`
local model = Instance.new("Model")
model.Name = "Builtin"
local mesh = Instance.new("MeshPart", model)
mesh.MeshId = "builtin://cube"
model.Parent = game.Workspace
KineRoot = model
`,
		),
		"asset_builtin_build",
	)
	vm.GetGlobal(script_vm.L, "KineRoot")
	builtin_root := cast(^classes.Object)vm.UserdataValue(script_vm.L, -1)
	vm.Pop(script_vm.L)
	builtin_stream, builtin_err := serializer.Serialize(&environment.classes, script_vm.L, builtin_root)
	defer delete(builtin_stream)
	if !serializer.Error_Is_None(builtin_err) {
		serializer.Error_Delete(&builtin_err)
		panic("serializing a builtin mesh failed")
	}
	serializer.Error_Delete(&builtin_err)
	builtin_parent, builtin_parent_ok := classes.Push_New(&environment.classes, &script_vm, "Folder", true)
	if !builtin_parent_ok || builtin_parent == nil {
		panic("could not create a Folder for the builtin map")
	}
	vm.Pop(script_vm.L)
	builtin_loaded, builtin_load_err :=
		serializer.Deserialize(&environment.classes, script_vm.L, builtin_parent, builtin_stream)
	if !serializer.Error_Is_None(builtin_load_err) || builtin_loaded == nil {
		panic(fmt.tprintf("loading the builtin map failed: %s", serializer.Error_String(builtin_load_err)))
	}
	serializer.Error_Delete(&builtin_load_err)
	vm.PushRegistryReference(script_vm.L, builtin_loaded.lua_ref)
	vm.SetGlobalFromStack(&script_vm, "BuiltinRoot")
	run_script_or_fail(
		&script_vm,
		`
KineBuiltinValue = BuiltinRoot.MeshPart.MeshId
`,
		"asset_builtin_verify",
	)
	builtin_value := read_global_string(&script_vm, "KineBuiltinValue")
	defer delete(builtin_value)
	expect_kept_as_path("a builtin reference", builtin_value, "builtin://cube")

	// A version 2 stream has no asset table and must still load, keeping bare
	// paths. The source files are gone by now, which is exactly the situation it
	// cannot survive, so the check is on the value, not on loading a mesh.
	legacy_parent, legacy_parent_ok := classes.Push_New(&environment.classes, &script_vm, "Folder", true)
	if !legacy_parent_ok || legacy_parent == nil {
		panic("could not create a Folder for the legacy map")
	}
	vm.Pop(script_vm.L)
	legacy_loaded, legacy_load_ok :=
		serializer.Deserialize(&environment.classes, script_vm.L, legacy_parent, legacy)
	if !legacy_load_ok || legacy_loaded == nil {
		panic("a KINE v2 stream failed to load")
	}
	vm.PushRegistryReference(script_vm.L, legacy_loaded.lua_ref)
	vm.SetGlobalFromStack(&script_vm, "LegacyRoot")
	run_script_or_fail(
		&script_vm,
		`
KineLegacyMesh = LegacyRoot:FindFirstChild("Body").MeshId
`,
		"asset_legacy_verify",
	)
	legacy_value := read_global_string(&script_vm, "KineLegacyMesh")
	defer delete(legacy_value)
	expect_kept_as_path("a v2 stream", legacy_value, mesh_path)

	// The format hint survives, because in-memory decoders need the extension
	// and the authored path is what carries it.
	mesh_hint := assetstore.Format_Hint(mesh_value)
	defer delete(mesh_hint)
	if mesh_hint != "fbx" {
		panic(fmt.tprintf("mesh format hint was %q, want fbx", mesh_hint))
	}
	texture_hint := assetstore.Format_Hint(texture_value)
	defer delete(texture_hint)
	if texture_hint != "png" {
		panic(fmt.tprintf("texture format hint was %q, want png", texture_hint))
	}

	// A Content that points at a live engine object has no URI at all, so before
	// version 3 it round-tripped into a dangling empty reference and the part
	// quietly lost its mesh on every save.
	run_script_or_fail(
		&script_vm,
		`
local model = Instance.new("Model")
model.Name = "Handle"
local editable = Instance.new("EditableMesh", model)
editable.Name = "Edited"
local part = Instance.new("MeshPart", model)
part.Name = "Piece"
part.MeshContent = Content.fromObject(editable)
assert(part.MeshContent.IsObject)
model.Parent = game.Workspace
KineRoot = model
KineHandleObjectId = part.MeshContent.ObjectId
`,
		"asset_handle_build",
	)
	vm.GetGlobal(script_vm.L, "KineRoot")
	handle_root := cast(^classes.Object)vm.UserdataValue(script_vm.L, -1)
	vm.Pop(script_vm.L)
	handle_source_id := read_global_number(&script_vm, "KineHandleObjectId")
	handle_stream, handle_err := serializer.Serialize(&environment.classes, script_vm.L, handle_root)
	defer delete(handle_stream)
	if !serializer.Error_Is_None(handle_err) {
		serializer.Error_Delete(&handle_err)
		panic("serializing an object-backed Content failed")
	}
	serializer.Error_Delete(&handle_err)
	handle_parent, handle_parent_ok := classes.Push_New(&environment.classes, &script_vm, "Folder", true)
	if !handle_parent_ok || handle_parent == nil {
		panic("could not create a Folder for the object-handle map")
	}
	vm.Pop(script_vm.L)
	handle_loaded, handle_load_err :=
		serializer.Deserialize(&environment.classes, script_vm.L, handle_parent, handle_stream)
	if !serializer.Error_Is_None(handle_load_err) || handle_loaded == nil {
		panic(fmt.tprintf(
			"loading the object-handle map failed: %s",
			serializer.Error_String(handle_load_err),
		))
	}
	serializer.Error_Delete(&handle_load_err)
	vm.PushRegistryReference(script_vm.L, handle_loaded.lua_ref)
	vm.SetGlobalFromStack(&script_vm, "HandleRoot")
	run_script_or_fail(
		&script_vm,
		`
KineHandleIsObject = HandleRoot:FindFirstChild("Piece").MeshContent.IsObject
KineHandleRestoredId = HandleRoot:FindFirstChild("Piece").MeshContent.ObjectId
`,
		"asset_handle_verify",
	)
	if !read_global_bool(&script_vm, "KineHandleIsObject") {
		panic("a Content object handle did not survive the round-trip")
	}
	handle_restored_id := read_global_number(&script_vm, "KineHandleRestoredId")
	if handle_restored_id != handle_source_id {
		panic(fmt.tprintf(
			"Content object id changed across the round-trip: %v became %v",
			handle_source_id,
			handle_restored_id,
		))
	}

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("ASSET_PORTABILITY_PASSED")
}
