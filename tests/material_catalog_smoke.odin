package main

import classes "../src/engine/classes"
import enums "../src/engine/enum"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"

run :: proc(v: ^vm.VM, source: string) {
	ok, err := vm.Run(v, source, "material_catalog_smoke")
	assert(ok, err)
}

main :: proc() {
	v := vm.New()
	env: engine_runtime.Environment
	engine_runtime.Environment_Init(&env, &v)
	defer {vm.Close(&v); engine_runtime.Environment_Destroy(&env)}
	run(
		&v,
		`
local names = {
"Plastic","SmoothPlastic","Neon","Wood","WoodPlanks","Marble","Basalt","Slate","CrackedLava","Concrete","Limestone","Granite","Pavement","Brick","Pebble","Cobblestone","Rock","Sandstone","CorrodedMetal","DiamondPlate","Foil","Metal","Grass","LeafyGrass","Sand","Fabric","Snow","Mud","Ground","Asphalt","Salt","Ice","Glacier","Glass","ForceField","Air","Water","Cardboard","Carpet","CeramicTiles","ClayRoofTiles","RoofShingles","Leather","Plaster","Rubber"}
local items = Enum.Material:GetEnumItems()
assert(#items == #names and #items == 45,"material list does not match Roblox")
assert(Enum.Material.DiamondPlate.Value == 1056)
assert(Enum.Material.Plastic.Value == 256 and Enum.Material.Rubber.Value == 2311)
assert(Enum.Material.Wood.Value == 512 and Enum.Material.Water.Value == 2048)
root = Instance.new("Model",workspace)
local terrain = game:GetService("Terrain")
for i,name in names do
    local item = items[i]
    assert(item.Name == name,"material order mismatch: "..name)
    assert(Enum.Material:FromName(name) == item)
    assert(Enum.Material:FromValue(item.Value) == item)
    assert(EnumItem.fromValue(Enum.Material,item.Value) == item)
    local part = Instance.new("Part",root)
    part.Name = name; part.Material = item
    assert(part.Material == item)
    local copy = part:Clone(); assert(copy.Material == item); copy:Destroy()
end
assert(Enum.Material:FromValue(9999) == nil)
terrain:SetCell(0,0,0,Enum.Material.Basalt)
terrain:SetCell(1,0,0,Enum.Material.Rubber)
terrain:SetMaterialColor(Enum.Material.DiamondPlate,Color3.new(0.2,0.4,0.6))
`,
	)
	vm.GetGlobal(v.L, "root")
	root := classes.Object_From_Argument(v.L, -1); vm.Pop(v.L)
	terrain := cast(^services.Terrain)services.Ensure_Service(&env.services, "Terrain")
	table: serializer.Kine_Terrain
	services.Terrain_Write_Kine_Table(terrain, &table)
	defer serializer.Kine_Terrain_Destroy(&table)
	data, err := serializer.Serialize(&env.classes, v.L, root, terrain = &table)
	assert(serializer.Error_Is_None(err)); defer delete(data)
	restored: serializer.Kine_Terrain
	defer serializer.Kine_Terrain_Destroy(&restored)
	loaded, read_err := serializer.Deserialize_From_Data(&env.classes, v.L, nil, data, &restored)
	assert(serializer.Error_Is_None(read_err))
	assert(services.Terrain_Read_Kine_Table(terrain, nil, &restored))
	classes.Push_Object(v.L, loaded); vm.SetGlobalFromStack(&v, "loaded")
	run(
		&v,
		`
for _,item in Enum.Material:GetEnumItems() do
    assert(loaded:FindFirstChild(item.Name).Material == item,"saved material changed: "..item.Name)
end
local terrain = game:GetService("Terrain")
assert(terrain:GetCell(0,0,0) == Enum.Material.Basalt)
assert(terrain:GetCell(1,0,0) == Enum.Material.Rubber)
assert(math.abs(terrain:GetMaterialColor(Enum.Material.DiamondPlate).G-0.4) < 0.01)
`,
	)
	records := []services.Terrain_Cell_Record {
		{x = 3, occupancy = 1, material = .DiamondPlate},
		{x = 4, occupancy = 1, material = .Rubber},
	}
	bytes: [dynamic]u8; defer delete(bytes)
	services.encode_terrain_batch(&bytes, records)
	reader := services.Replication_Reader {
		data   = bytes[:],
		offset = 1,
		valid  = true,
	}
	decoded, ok := services.decode_terrain_batch(&reader)
	defer delete(decoded)
	assert(
		ok &&
		len(decoded) == 2 &&
		decoded[0].material == .DiamondPlate &&
		decoded[1].material == .Rubber,
	)
	assert(
		int(enums.Material.SmoothPlastic) == 0 &&
		int(enums.Material.Wood) == 1 &&
		int(enums.Material.Air) == 11,
		"legacy save IDs changed",
	)
	fmt.println("MATERIAL_CATALOG_SMOKE_PASSED")
}
