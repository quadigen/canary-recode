package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import classes "../src/engine/classes"
import serializer "../src/engine/serializer"
import vm "../src/engine/vm"

run_script_or_fail :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln("script failed:", name, err)
		delete(err)
		panic(name)
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	run_script_or_fail(&script_vm, `
local model = Instance.new("Model")
model.Name = "Car"

local part = Instance.new("Part", model)
part.Name = "Block"
part.Anchored = false
part.Transparency = 0.25
part.Size = Vector3.new(3, 4, 5)
part.CFrame = CFrame.new(10, 20, 30) * CFrame.Angles(0.5, 0.2, 0.1)
part.Color = Color3.fromRGB(200, 50, 20)
part.Material = Enum.Material.Neon

part:SetAttribute("Health", 100)
part:SetAttribute("Title", "Ready")
part:SetAttribute("Tint", Color3.fromRGB(1, 2, 3))
part:SetAttribute("Offset", Vector3.new(1, 2, 3))
part:SetAttribute("Flag", true)
part:SetAttribute("Speed", 12.5)
part:SetAttribute("Count", 7)

local screen = Instance.new("ScreenGui", model)
screen.Name = "Hud"

local text = Instance.new("TextBox", screen)
text.Name = "Label"
text.Text = "hello"
text.BackgroundColor3 = Color3.fromRGB(10, 20, 30)
text.Position = UDim2.fromScale(0.25, 0.5)
text.Visible = true

model.Parent = game.Workspace
KineRoot = model
`, "serializer_build")

	vm.GetGlobal(script_vm.L, "KineRoot")
	root := cast(^classes.Object)vm.UserdataValue(script_vm.L, -1)
	vm.Pop(script_vm.L)
	if root == nil {
		panic("KineRoot global missing")
	}

	// In-memory round trip.
	data, ok := serializer.Serialize(&environment.classes, script_vm.L, root)
	if !ok || data == nil {
		panic("serialize failed")
	}
	defer delete(data)
	fmt.printf("serialized %d bytes\n", len(data))

	parent, parent_ok := classes.Push_New(&environment.classes, &script_vm, "Folder", true)
	if !parent_ok || parent == nil {
		panic("could not create Folder")
	}
	vm.Pop(script_vm.L)

	loaded, load_ok := serializer.Deserialize(&environment.classes, script_vm.L, parent, data)
	if !load_ok || loaded == nil {
		panic("deserialize failed")
	}

	vm.PushRegistryReference(script_vm.L, loaded.lua_ref)
	vm.SetGlobalFromStack(&script_vm, "LoadedRoot")

	run_script_or_fail(&script_vm, `
local function cframeNearlyEqual(a, b)
    local ax, ay, az, a00, a01, a02, a10, a11, a12, a20, a21, a22 = a:GetComponents()
    local bx, by, bz, b00, b01, b02, b10, b11, b12, b20, b21, b22 = b:GetComponents()
    local eps = 1e-3
    if math.abs(ax - bx) > eps then return false end
    if math.abs(ay - by) > eps then return false end
    if math.abs(az - bz) > eps then return false end
    if math.abs(a00 - b00) > eps then return false end
    if math.abs(a01 - b01) > eps then return false end
    if math.abs(a02 - b02) > eps then return false end
    if math.abs(a10 - b10) > eps then return false end
    if math.abs(a11 - b11) > eps then return false end
    if math.abs(a12 - b12) > eps then return false end
    if math.abs(a20 - b20) > eps then return false end
    if math.abs(a21 - b21) > eps then return false end
    if math.abs(a22 - b22) > eps then return false end
    return true
end

assert(LoadedRoot:IsA("Model"))
assert(LoadedRoot.Name == "Car")

local part = LoadedRoot:FindFirstChild("Block")
assert(part ~= nil)
assert(part.ClassName == "Part")
assert(part.Anchored == false)
assert(math.abs(part.Transparency - 0.25) < 1e-5)
assert(part.Size == Vector3.new(3, 4, 5))
assert(cframeNearlyEqual(part.CFrame, CFrame.new(10, 20, 30) * CFrame.Angles(0.5, 0.2, 0.1)))
assert(math.abs(part.Color.R - 200/255) < 1e-5)
assert(math.abs(part.Color.G - 50/255) < 1e-5)
assert(math.abs(part.Color.B - 20/255) < 1e-5)
assert(part.Material == Enum.Material.Neon)

assert(part:GetAttribute("Health") == 100)
assert(part:GetAttribute("Title") == "Ready")
local tint = part:GetAttribute("Tint")
assert(math.abs(tint.R - 1/255) < 1e-5 and math.abs(tint.G - 2/255) < 1e-5 and math.abs(tint.B - 3/255) < 1e-5)
assert(part:GetAttribute("Offset") == Vector3.new(1, 2, 3))
assert(part:GetAttribute("Flag") == true)
assert(math.abs(part:GetAttribute("Speed") - 12.5) < 1e-5)
assert(part:GetAttribute("Count") == 7)

local hud = LoadedRoot:FindFirstChild("Hud")
assert(hud ~= nil and hud.ClassName == "ScreenGui")
local text = hud:FindFirstChild("Label")
assert(text ~= nil and text.ClassName == "TextBox")
assert(text.Text == "hello")
assert(math.abs(text.BackgroundColor3.R - 10/255) < 1e-5)
assert(math.abs(text.Position.X.Scale - 0.25) < 1e-5)
assert(math.abs(text.Position.Y.Scale - 0.5) < 1e-5)
assert(text.Visible == true)

assert(part.Parent == LoadedRoot)
assert(text:IsDescendantOf(LoadedRoot))
`, "serializer_verify")

	// File round trip.
	save_ok := serializer.Serialize_To_File(&environment.classes, script_vm.L, root, "build/smoke.kine")
	if !save_ok {
		panic("saving .kine file failed")
	}

	loaded_file, file_ok := serializer.Deserialize_From_File(&environment.classes, script_vm.L, parent, "build/smoke.kine")
	if !file_ok || loaded_file == nil {
		panic("loading .kine file failed")
	}

	vm.PushRegistryReference(script_vm.L, loaded_file.lua_ref)
	vm.SetGlobalFromStack(&script_vm, "LoadedFile")

	run_script_or_fail(&script_vm, `
assert(LoadedFile.ClassName == "Model")
assert(LoadedFile.Name == "Car")
local part = LoadedFile:FindFirstChild("Block")
assert(part ~= nil)
assert(part.Size == Vector3.new(3, 4, 5))
assert(part.Material == Enum.Material.Neon)
assert(part:GetAttribute("Health") == 100)
assert(LoadedFile:FindFirstChild("Hud"):FindFirstChild("Label").Text == "hello")
`, "serializer_file_verify")

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("SERIALIZER_SMOKE_PASSED")
}