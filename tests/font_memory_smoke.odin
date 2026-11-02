package main

import "core:fmt"

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import vm "../src/engine/vm"


FONT_BYTES := #load("../src/engine/assets/fonts/Montserrat-Regular.ttf")

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("font memory smoke test setup failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)


	vm.PushBytes(script_vm.L, FONT_BYTES[:])
	vm.SetGlobalFromStack(&script_vm, "FontBytes")

	run_script(
		&script_vm,
		`
-- A buffer is how a download arrives, and the bytes must survive intact.
local downloaded = buffer.fromstring(FontBytes)
assert(buffer.len(downloaded) > 0)

local face = Font.fromMemory(downloaded)
assert(type(face) == "userdata")
assert(face.FromMemory == true)
assert(face.Bold == false)
-- The internal handle stays out of sight when the font is printed.
assert(string.find(tostring(face), "Font.fromMemory") ~= nil)

-- A string works too, since HttpService hands bodies back as strings.
local from_string = Font.fromMemory(FontBytes)
assert(from_string.FromMemory == true)

-- Empty input is rejected rather than installing a font that renders nothing.
assert(not pcall(function() return Font.fromMemory(buffer.create(0)) end))
assert(not pcall(function() return Font.fromMemory(nil) end))

-- A font with no bytes of its own reports so.
assert(Font.fromName("Montserrat").FromMemory == false)

-- TextLabel takes the face through FontFace, and through Font as well.
local label = Instance.new("TextLabel")
label.Text = "downloaded"
label.FontFace = face
assert(label.FontFace.FromMemory == true)

-- Reading Font back hands over the font itself, because a memory face belongs
-- to no Enum.Font and naming one would misreport what is being rendered.
label.Font = face
assert(label.Font.FromMemory == true)

-- TextButton and TextBox get the same treatment.
local button = Instance.new("TextButton")
button.Text = "downloaded"
button.FontFace = face
assert(button.FontFace.FromMemory == true)
button.Font = face
assert(button.Font.FromMemory == true)

local box = Instance.new("TextBox")
box.Text = "downloaded"
box.FontFace = face
assert(box.FontFace.FromMemory == true)
box.Font = face
assert(box.Font.FromMemory == true)

-- The bytes really reach the rasterizer: measuring against the downloaded face
-- must produce real dimensions, which only happens once Skia has parsed it.
local TextService = game:GetService("TextService")
local measured = TextService:GetTextSize("downloaded", 16, face, Vector2.new(1000, 100))
assert(measured.X > 0, "a downloaded face measured zero width")
assert(measured.Y > 0, "a downloaded face measured zero height")

-- Each fromMemory call gets its own face, so two labels never share one by
-- accident even for identical bytes.
assert(Font.fromMemory(downloaded) ~= face)
`,
		"font_memory_smoke",
	)


	run_script(
		&script_vm,
		`
local screen = Instance.new("ScreenGui")
screen.Name = "Hud"

local label = Instance.new("TextLabel", screen)
label.Name = "Caption"
label.Text = "saved"
label.Font = Enum.Font.Code

screen.Parent = game.Workspace
SavedRoot = screen
`,
		"font_memory_save",
	)

	vm.GetGlobal(script_vm.L, "SavedRoot")
	root := cast(^classes.Object)vm.UserdataValue(script_vm.L, -1)
	vm.Pop(script_vm.L)
	if root == nil {
		panic("SavedRoot global missing")
	}

	data, save_err := serializer.Serialize(&environment.classes, script_vm.L, root)
	if !serializer.Error_Is_None(save_err) || data == nil {
		panic(fmt.tprintf("serialize failed: %s", serializer.Error_String(save_err)))
	}
	serializer.Error_Delete(&save_err)
	defer delete(data)
	fmt.println("PROGRESS: serialized")


	saved_parent, saved_ok := classes.Push_New(&environment.classes, &script_vm, "Folder", true)
	if !saved_ok || saved_parent == nil {
		panic("could not create a Folder")
	}
	vm.Pop(script_vm.L)

	loaded, load_err := serializer.Deserialize(
		&environment.classes,
		script_vm.L,
		saved_parent,
		data,
	)
	if !serializer.Error_Is_None(load_err) || loaded == nil {
		panic(fmt.tprintf("deserialize failed: %s", serializer.Error_String(load_err)))
	}
	serializer.Error_Delete(&load_err)
	fmt.println("PROGRESS: deserialized")


	vm.PushRegistryReference(script_vm.L, loaded.lua_ref)
	vm.SetGlobalFromStack(&script_vm, "LoadedRoot")

	run_script(
		&script_vm,
		`
local saved = LoadedRoot:FindFirstChild("Caption")
assert(saved ~= nil, "the saved label did not survive the round trip")

-- The family is the engine's own handle; what matters is that the face bytes
-- are still there, so the label renders exactly as it did before the save.
assert(saved.FontFace.FromMemory == true, "the memory font lost its face bytes")

local TextService = game:GetService("TextService")
local measured = TextService:GetTextSize("saved", 16, saved.FontFace, Vector2.new(1000, 100))
assert(measured.X > 0, "the reloaded face would not measure")

-- A non-memory font keeps reporting no face bytes after the same trip.
local plain = Instance.new("TextLabel", LoadedRoot)
plain.Font = Enum.Font.Code
assert(plain.FontFace.FromMemory == false)
`,
		"font_memory_verify",
	)


	legacy, legacy_err := serializer.Serialize_Legacy(&environment.classes, script_vm.L, root)
	if !serializer.Error_Is_None(legacy_err) || legacy == nil {
		panic(fmt.tprintf("legacy serialize failed: %s", serializer.Error_String(legacy_err)))
	}
	serializer.Error_Delete(&legacy_err)
	defer delete(legacy)

	legacy_parent, legacy_ok := classes.Push_New(&environment.classes, &script_vm, "Folder", true)
	if !legacy_ok || legacy_parent == nil {
		panic("could not create a Folder")
	}
	vm.Pop(script_vm.L)

	legacy_loaded, legacy_load_err := serializer.Deserialize(
		&environment.classes,
		script_vm.L,
		legacy_parent,
		legacy,
	)
	if !serializer.Error_Is_None(legacy_load_err) || legacy_loaded == nil {
		panic(
			fmt.tprintf("legacy deserialize failed: %s", serializer.Error_String(legacy_load_err)),
		)
	}
	serializer.Error_Delete(&legacy_load_err)

	fmt.println("PROGRESS: pre-close")
	vm.Close(&script_vm)
	fmt.println("PROGRESS: closed")
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("PROGRESS: destroyed")

	fmt.println("FONT_MEMORY_SMOKE_PASSED")
}
