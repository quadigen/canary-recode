package main

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"

variant_filter :: proc(parent: ^classes.Object, object: ^classes.Object) -> bool {
	if object == nil || object.class == nil {
		return true
	}
	if parent == nil || !classes.Is_A(parent, "DataModel") {
		return false
	}
	if !classes.Is_A(object, "Service") {
		return false
	}
	return !services.Map_Content_Service(object.name)
}

main :: proc() {
	if len(os.args) < 3 {
		fmt.eprintln("usage: <input.kine> <output.kine> <variant>")
		os.exit(1)
	}
	input, output, variant := os.args[1], os.args[2], os.args[3]
	data, read_err := os.read_entire_file(input, context.allocator)
	if read_err != nil {
		fmt.eprintln("read failed:", read_err)
		os.exit(1)
	}
	defer delete(data)

	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)
	defer engine_runtime.Environment_Destroy(&environment)

	ok := services.Restore_Map(
		&environment.services,
		script_vm.L,
		data,
		input,
		clear_assets = false,
	)
	fmt.println("restore ok =", ok)
	if !ok {os.exit(2)}

	vm.PushString(script_vm.L, variant)
	vm.SetGlobal(script_vm.L, "VariantName")
	source := `
local variant = VariantName
local function collect(pred)
	local found = {}
	for _, object in ipairs(game:GetDescendants()) do
		if pred(object) then table.insert(found, object) end
	end
	for _, object in ipairs(found) do object:Destroy() end
	print("destroyed", #found, variant)
end
local ws = game:GetService("Workspace")
if variant == "empty" then
	for _, child in ipairs(ws:GetChildren()) do child:Destroy() end
elseif variant == "nomaterial" then
	collect(function(o) return o.ClassName == "MaterialVariant" end)
elseif variant == "noparts" then
	collect(function(o) return o.ClassName == "Part" or o.ClassName == "MeshPart" end)
elseif variant == "nowater" then
	collect(function(o) return o.ClassName == "Part" and o.Material == Enum.Material.Water end)
elseif variant == "noshapes" then
	for _, child in ipairs(ws:GetChildren()) do
		if child.Name == "Shapes" or child.Name == "BuildingBlocks" then child:Destroy() end
	end
elseif variant == "nodecal" then
	collect(function(o) return o.ClassName == "Decal" end)
elseif variant == "noimages" then
	collect(function(o) return o.ClassName == "ImageLabel" or o.ClassName == "ImageButton" end)
elseif variant == "nolightingextra" then
	local lighting = game:GetService("Lighting")
	for _, child in ipairs(lighting:GetChildren()) do
		if child.ClassName ~= "Sky" then child:Destroy() end
	end
elseif variant == "noscripts" then
	for _, service in ipairs({ game:GetService("ReplicatedStorage"), game:GetService("StarterGui"), game:GetService("StarterPack"), game:GetService("StarterPlayer") }) do
		for _, child in ipairs(service:GetChildren()) do child:Destroy() end
	end
else
	print("unknown variant", variant)
end
`
	run_ok, run_err := vm.Run(&script_vm, source, "variant")
	if !run_ok {
		fmt.eprintln("script failed:", run_err)
		delete(run_err)
		os.exit(3)
	}

	model := environment.services.data_model
	serialized, serialize_err := serializer.Serialize(
		environment.services.classes,
		script_vm.L,
		&model.object,
		variant_filter,
	)
	if !serializer.Error_Is_None(serialize_err) {
		serializer.Error_Print(serialize_err, "serialize failed: ")
		os.exit(4)
	}
	defer delete(serialized)
	write_err := serializer.Write_File_Data(output, serialized)
	if !serializer.Error_Is_None(write_err) {
		serializer.Error_Print(write_err, "write failed: ")
		os.exit(5)
	}
	fmt.printf("wrote %s (%d bytes raw)\n", output, len(serialized))
}
