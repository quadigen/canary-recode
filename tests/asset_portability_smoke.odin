// A .kine file is only portable if the bytes a map points at travel inside it.
// This writes real asset files, points real properties at them, serializes,
// deletes the sources, and then checks the blobs still resolve from the loaded
// map. Anything that silently kept reading from disk fails here.
package main

import assetstore "../src/engine/assetstore"
import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"
import "core:strings"

MESH_BODY :: "mesh bytes that are not really an fbx but are definitely bytes"
TEXTURE_BODY :: "texture bytes that are not really a png but are definitely bytes"
DECAL_BODY :: "decal bytes, also not a real image, also definitely bytes"
FONT_BODY := #load("../src/engine/assets/fonts/Montserrat-Regular.ttf")
RUNTIME_IMAGE :: "<svg xmlns='http://www.w3.org/2000/svg' width='4' height='4'><rect width='4' height='4' fill='red'/></svg>"
RUNTIME_IMAGE_URI :: "memory://asset-portability-smoke"
AUDIO_BODY :: "test bytes for an audio asset"
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

check_project_bundle :: proc(script_vm: ^vm.VM, environment: ^engine_runtime.Environment, scratch: string) {
	project := fmt.tprintf("%s/project", scratch)
	assert(os.make_directory_all(fmt.tprintf("%s/assets/replicated", project)) == nil)
	assert(os.make_directory_all(fmt.tprintf("%s/custom-output", project)) == nil)
	svg_path := write_asset(fmt.tprintf("%s/assets/replicated", project), "shapes.svg", RUNTIME_IMAGE)
	_ = write_asset(project, "manifest.example", "arbitrary file contents")
	_ = write_asset(project, "autosave.kine", "generated save")
	_ = write_asset(fmt.tprintf("%s/custom-output", project), "old-game", "previous export")
	root, root_ok := classes.Push_New(&environment.classes, script_vm, "Folder", true)
	assert(root_ok)
	vm.SetGlobalFromStack(script_vm, "BundleRoot")
	run_script_or_fail(script_vm, fmt.tprintf(`
local code = Instance.new("ModuleScript", BundleRoot)
code.Name = "Code"
code.Source = [=[
return function(name)
	local image = Instance.new("ImageLabel")
	image.Image = "project://assets/replicated/" .. name
	local legacy = Instance.new("ImageLabel")
	legacy.Image = %q
	return image, legacy
end
]=]
`, svg_path), "project_bundle_script")

	assetstore.Set_Project_Root(project)
	run_script_or_fail(script_vm, `
local image = Instance.new("ImageLabel")
image.Image = "project://assets/replicated/shapes.svg"
EditorProjectImage = image
`, "project_bundle_editor_image")
	vm.GetGlobal(script_vm.L, "EditorProjectImage")
	editor_image := cast(^classes.ImageLabel)classes.Object_From_Argument(script_vm.L, -1)
	vm.Pop(script_vm.L)
	assert(editor_image.stored_image != nil, "editor could not resolve project:// against the project root")

	bundle, write_err := serializer.Serialize(
		&environment.classes, script_vm.L, root,
		script_asset_root = project,
		project_output_file = fmt.tprintf("%s/custom-output/game.kine", project),
		project_output_directory = fmt.tprintf("%s/custom-output", project),
	)
	assert(serializer.Error_Is_None(write_err), serializer.Error_String(write_err))
	defer delete(bundle)
	assert(serializer.Has_Path_Assets(bundle))

	assetstore.Set_Project_Root("")
	assert(os.remove_all(project) == nil)
	assetstore.Clear()
	loaded, load_err := serializer.Deserialize(&environment.classes, script_vm.L, nil, bundle)
	assert(serializer.Error_Is_None(load_err), serializer.Error_String(load_err))
	assert(loaded != nil)
	manifest, found := assetstore.Resolve_Bytes("project://manifest.example")
	assert(found && string(manifest) == "arbitrary file contents")
	_, autosave := assetstore.Resolve_Bytes("project://autosave.kine")
	_, prior_export := assetstore.Resolve_Bytes("project://custom-output/old-game")
	assert(!autosave && !prior_export)
	vm.PushRegistryReference(script_vm.L, loaded.lua_ref)
	vm.SetGlobalFromStack(script_vm, "LoadedBundle")
	run_script_or_fail(script_vm, `
ProjectImage, LegacyProjectImage = require(LoadedBundle.Code)("shapes.svg")
`, "project_bundle_exported_images")
	for name in ([]string{"ProjectImage", "LegacyProjectImage"}) {
		vm.GetGlobal(script_vm.L, name)
		image := cast(^classes.ImageLabel)classes.Object_From_Argument(script_vm.L, -1)
		vm.Pop(script_vm.L)
		assert(image != nil && image.stored_image != nil, name)
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
	font_path := write_asset(scratch, "custom.ttf", string(FONT_BODY))
	sound_path := write_asset(scratch, "custom.wav", AUDIO_BODY)
	classes.ImageLabel_Register_Runtime_Image(RUNTIME_IMAGE_URI, RUNTIME_IMAGE)

	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	for input in ([]struct{name, value: string}{
		{"MeshPath", mesh_path},
		{"TexturePath", texture_path},
		{"TextureUri", fmt.tprintf("file://%s", texture_path)},
		{"DecalPath", decal_path},
		{"FontPath", font_path},
		{"SoundPath", sound_path},
		{"RuntimeImage", RUNTIME_IMAGE_URI},
	}) {
		vm.PushString(script_vm.L, input.value)
		vm.SetGlobalFromStack(&script_vm, input.name)
	}

	// Build a map the way an author would: real classes pointing at real files.
	run_script_or_fail(
		&script_vm,
		`
local model = Instance.new("Model")
model.Name = "Rig"

local mesh = Instance.new("MeshPart", model)
mesh.Name = "Body"
mesh.MeshId = MeshPath
mesh.TextureId = TexturePath

local decal = Instance.new("Decal", model)
decal.Name = "Scorch"
decal.Texture = DecalPath

local gui = Instance.new("ScreenGui", model)
local label = Instance.new("ImageLabel", gui)
label.Image = RuntimeImage
label.SliceCenter = Rect.new(8, 9, 20, 24)
local button = Instance.new("ImageButton", gui)
button.Image = TextureUri
for _, class in ipairs({"TextLabel", "TextButton", "TextBox"}) do
	local text = Instance.new(class, gui)
	text.FontFace = Font.new(FontPath, Enum.FontWeight.Bold, Enum.FontStyle.Italic)
end
local material = Instance.new("MaterialVariant", model)
material.ColorMap = TexturePath
material.NormalMap = DecalPath
local sound = Instance.new("Sound", model)
sound.SoundId = SoundPath
local contentSound = Instance.new("Sound", model)
contentSound.Name = "ContentSound"
contentSound.AudioContent = Content.fromUri(SoundPath)
local contentMesh = Instance.new("MeshPart", model)
contentMesh.Name = "ContentMesh"
contentMesh.MeshContent = Content.fromUri(MeshPath)

model.Parent = game.Workspace
KineRoot = model
`,
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
	for path in ([]string{mesh_path, texture_path, decal_path, font_path, sound_path}) {
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

	reexport_path := fmt.tprintf("%s/reexport.kine", scratch)
	reexport_err := serializer.Serialize_To_File(&environment.classes, script_vm.L, loaded, reexport_path)
	assert(serializer.Error_Is_None(reexport_err), serializer.Error_String(reexport_err))
	serializer.Error_Delete(&reexport_err)
	assetstore.Clear()
	reloaded, reload_err := serializer.Deserialize_From_File(&environment.classes, script_vm.L, parent, reexport_path)
	assert(serializer.Error_Is_None(reload_err) && reloaded != nil, serializer.Error_String(reload_err))
	serializer.Error_Delete(&reload_err)
	vm.PushRegistryReference(script_vm.L, reloaded.lua_ref)
	vm.SetGlobalFromStack(&script_vm, "ReexportRoot")
	run_script_or_fail(&script_vm, `
local gui = ReexportRoot.ScreenGui
assert(gui.ImageLabel.SliceCenter == Rect.new(8, 9, 20, 24))
for _, class in ipairs({"TextLabel", "TextButton", "TextBox"}) do
	local face = gui[class].FontFace
	assert(face.Weight == Enum.FontWeight.Bold and face.Style == Enum.FontStyle.Italic)
	assert(face.Family == gui.TextLabel.FontFace.Family)
	assert(game:GetService("TextService"):GetTextSize("Embedded", 16, face, Vector2.new(1000, 100)).X > 0)
end
ReexportFont = gui.TextLabel.FontFace.Family
ReexportImage = gui.ImageLabel.Image
ReexportImageButton = gui.ImageButton.Image
ReexportColor = ReexportRoot.MaterialVariant.ColorMap
ReexportNormal = ReexportRoot.MaterialVariant.NormalMap
ReexportSound = ReexportRoot.Sound.SoundId
ReexportContentSound = ReexportRoot.ContentSound.AudioContent.Uri
ReexportContentMesh = ReexportRoot.ContentMesh.MeshContent.Uri
`, "asset_reexport_verify")
	for check in ([]struct{global, body: string}{
		{"ReexportFont", string(FONT_BODY)},
		{"ReexportImage", RUNTIME_IMAGE},
		{"ReexportImageButton", TEXTURE_BODY},
		{"ReexportColor", TEXTURE_BODY},
		{"ReexportNormal", DECAL_BODY},
		{"ReexportSound", AUDIO_BODY},
		{"ReexportContentSound", AUDIO_BODY},
		{"ReexportContentMesh", MESH_BODY},
	}) {
		value := read_global_string(&script_vm, check.global)
		defer delete(value)
		expect_bytes(check.global, value, check.body)
	}

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
	missing_stream, missing_err := serializer.Serialize(
		&environment.classes,
		script_vm.L,
		missing_root,
	)
	defer delete(missing_stream)
	if !serializer.Error_Is_None(missing_err) {
		serializer.Error_Delete(&missing_err)
		panic("serializing a map with a missing asset failed")
	}
	serializer.Error_Delete(&missing_err)
	missing_parent, missing_parent_ok := classes.Push_New(
		&environment.classes,
		&script_vm,
		"Folder",
		true,
	)
	if !missing_parent_ok || missing_parent == nil {
		panic("could not create a Folder for the missing-asset map")
	}
	vm.Pop(script_vm.L)
	missing_loaded, missing_load_err := serializer.Deserialize(
		&environment.classes,
		script_vm.L,
		missing_parent,
		missing_stream,
	)
	if !serializer.Error_Is_None(missing_load_err) || missing_loaded == nil {
		panic(
			fmt.tprintf(
				"loading the missing-asset map failed: %s",
				serializer.Error_String(missing_load_err),
			),
		)
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
	builtin_stream, builtin_err := serializer.Serialize(
		&environment.classes,
		script_vm.L,
		builtin_root,
	)
	defer delete(builtin_stream)
	if !serializer.Error_Is_None(builtin_err) {
		serializer.Error_Delete(&builtin_err)
		panic("serializing a builtin mesh failed")
	}
	serializer.Error_Delete(&builtin_err)
	builtin_parent, builtin_parent_ok := classes.Push_New(
		&environment.classes,
		&script_vm,
		"Folder",
		true,
	)
	if !builtin_parent_ok || builtin_parent == nil {
		panic("could not create a Folder for the builtin map")
	}
	vm.Pop(script_vm.L)
	builtin_loaded, builtin_load_err := serializer.Deserialize(
		&environment.classes,
		script_vm.L,
		builtin_parent,
		builtin_stream,
	)
	if !serializer.Error_Is_None(builtin_load_err) || builtin_loaded == nil {
		panic(
			fmt.tprintf(
				"loading the builtin map failed: %s",
				serializer.Error_String(builtin_load_err),
			),
		)
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
	legacy_parent, legacy_parent_ok := classes.Push_New(
		&environment.classes,
		&script_vm,
		"Folder",
		true,
	)
	if !legacy_parent_ok || legacy_parent == nil {
		panic("could not create a Folder for the legacy map")
	}
	vm.Pop(script_vm.L)
	legacy_loaded, legacy_load_err := serializer.Deserialize(
		&environment.classes,
		script_vm.L,
		legacy_parent,
		legacy,
	)
	legacy_load_ok := serializer.Error_Is_None(legacy_load_err)
	serializer.Error_Delete(&legacy_load_err)
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
	handle_stream, handle_err := serializer.Serialize(
		&environment.classes,
		script_vm.L,
		handle_root,
	)
	defer delete(handle_stream)
	if !serializer.Error_Is_None(handle_err) {
		serializer.Error_Delete(&handle_err)
		panic("serializing an object-backed Content failed")
	}
	serializer.Error_Delete(&handle_err)
	handle_parent, handle_parent_ok := classes.Push_New(
		&environment.classes,
		&script_vm,
		"Folder",
		true,
	)
	if !handle_parent_ok || handle_parent == nil {
		panic("could not create a Folder for the object-handle map")
	}
	vm.Pop(script_vm.L)
	handle_loaded, handle_load_err := serializer.Deserialize(
		&environment.classes,
		script_vm.L,
		handle_parent,
		handle_stream,
	)
	if !serializer.Error_Is_None(handle_load_err) || handle_loaded == nil {
		panic(
			fmt.tprintf(
				"loading the object-handle map failed: %s",
				serializer.Error_String(handle_load_err),
			),
		)
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
		panic(
			fmt.tprintf(
				"Content object id changed across the round-trip: %v became %v",
				handle_source_id,
				handle_restored_id,
			),
		)
	}

	check_project_bundle(&script_vm, &environment, scratch)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("ASSET_PORTABILITY_PASSED")
}
