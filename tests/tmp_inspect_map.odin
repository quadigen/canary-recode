package main

import assetstore "../src/engine/assetstore"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"

main :: proc() {
	path := "autosave.kine"
	if len(os.args) > 1 {path = os.args[1]}
	data, read_err := os.read_entire_file(path, context.allocator)
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
		path,
		clear_assets = false,
	)
	fmt.println("restore ok =", ok)
	if !ok {os.exit(2)}

	fmt.printf("assets: %d\n", assetstore.Count())
	for i in 0 ..< assetstore.Count() {
		entry, _ := assetstore.At(i)
		head := entry.bytes
		if len(head) > 16 {head = head[:16]}
		fmt.printf("  asset[%d] id=%s kind=%v bytes=%d path=%q head=%v\n",
			i, entry.id, entry.kind, len(entry.bytes), entry.path, head)
	}

	source := `
local interesting = {
	Part = true, MeshPart = true, MaterialVariant = true, Decal = true,
	ImageLabel = true, ImageButton = true, SurfaceAppearance = true,
	SpecialMesh = true, Texture = true, Sky = true, Lighting = true,
}
local props = {
	"MeshId", "TextureId", "Texture", "Image", "Size", "CFrame", "Shape",
	"MaterialVariant", "ColorMap", "NormalMap", "MetalnessMap", "RoughnessMap",
	"HeightMap", "AmbientOcclusionMap", "EmissiveMap", "Transparency",
	"Material", "Anchored", "CanCollide", "StudsPerTile", "HeightScale",
	"SkyboxFt", "SkyboxBk", "SkyboxUp", "SkyboxDn", "SkyboxLf", "SkyboxRt",
	"Brightness", "ExposureCompensation", "EnvironmentDiffuseScale",
	"EnvironmentSpecularScale", "GlobalShadows", "Technology",
}
print("descendants:", #game:GetDescendants())
for _, obj in ipairs(game:GetDescendants()) do
	if interesting[obj.ClassName] then
		local parts = { obj.ClassName, obj.Name }
		for _, key in ipairs(props) do
			local ok, value = pcall(function() return obj[key] end)
			if ok and value ~= nil and value ~= "" then
				local text = tostring(value)
				if #text > 160 then text = text:sub(1, 160) .. "..." end
				table.insert(parts, key .. "=" .. text)
			end
		end
		print(table.concat(parts, " | "))
	end
end
`
	run_ok, run_err := vm.Run(&script_vm, source, "inspect")
	if !run_ok {
		fmt.eprintln("script failed:", run_err)
		delete(run_err)
	}
}
