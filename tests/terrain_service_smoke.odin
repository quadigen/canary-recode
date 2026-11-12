package main

import "core:fmt"
import "core:math"
import "core:strings"

import enums "../src/engine/enum"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import marching_cubes "../src/engine/util/marching_cubes"
import vm "../src/engine/vm"

march_count_triangle :: proc(p0, p1, p2: marching_cubes.Vec3, user_data: rawptr) {
	counter := cast(^int)user_data
	counter^ += 1
}


TERRAIN_SCRIPT_PREAMBLE :: "local Terrain = game:GetService(\"Terrain\")\n"

run_script :: proc(script_vm: ^vm.VM, body, name: string) {
	source := strings.concatenate({TERRAIN_SCRIPT_PREAMBLE, body})
	defer delete(source)

	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("terrain service smoke test failed")
	}
}

terrain_of :: proc(environment: ^engine_runtime.Environment) -> ^services.Terrain {
	object := services.Ensure_Service(&environment.services, "Terrain")
	assert(object != nil, "the Terrain service must be instantiable")
	service := cast(^services.Terrain)object
	assert(service != nil)
	return service
}

queued_chunk_count :: proc(service: ^services.Terrain) -> int {
	return max(0, len(service.dirty_queue) - service.dirty_head)
}

has_chunk :: proc(service: ^services.Terrain, key: services.Terrain_Chunk_Key) -> bool {
	chunk, ok := service.chunks[key]
	return ok && chunk != nil
}

clear_dirty_bookkeeping :: proc(service: ^services.Terrain) {
	for _, chunk in service.chunks {
		if chunk != nil {
			chunk.dirty = false
		}
	}
	clear(&service.dirty_lookup)
	clear(&service.dirty_queue)
	service.dirty_head = 0
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	terrain := terrain_of(&environment)


	{
		cell: marching_cubes.MC_Cell
		triangle_count := 0
		assert(marching_cubes.MC_March_Cube(&cell, 0.5) == 0, "an empty cell has no surface")

		for offset, index in marching_cubes.MC_Corner_Offsets {
			cell.positions[index] = offset
		}
		cell.densities[0] = 1
		count := marching_cubes.MC_March_Cube(&cell, 0.5, march_count_triangle, &triangle_count)
		assert(count > 0, "a lone solid corner must emit triangles")
		assert(triangle_count == count, "the emit callback must see every triangle")
	}


	assert(terrain.voxel_size == services.TERRAIN_DEFAULT_VOXEL_SIZE)
	assert(math.abs(terrain.iso_level - services.TERRAIN_DEFAULT_ISO_LEVEL) < 1e-6)
	assert(services.Terrain_Cell_Count(terrain) == 0)
	assert(len(terrain.chunks) == 0)
	assert(len(terrain.dirty_queue) == 0 && terrain.dirty_head == 0)
	assert(len(terrain.draw_items) == 0)
	assert(services.TERRAIN_CHUNK_SIZE == 16)
	assert(services.TERRAIN_REBUILDS_PER_FRAME == 8)


	run_script(
		&script_vm,
		`
assert(Terrain ~= nil)
assert(Terrain:IsA("Service"))
assert(Terrain.ClassName == "Terrain")
assert(game:GetService("Terrain") == Terrain)
assert(terrain == Terrain, "the registered global alias must be the same service")
assert(game.terrain == nil, "the alias is a global, not a DataModel member")

-- Roblox Terrain properties.
assert(Terrain.Decoration == false)
assert(math.abs(Terrain.GrassLength - 0.1) < 1e-6)
assert(Terrain.IsSmooth == true)
local extents = Terrain.MaxExtents
assert(extents.Min.X == -16000 and extents.Max.X == 16000)
assert(typeof(Terrain.WaterColor) == "Color3")
assert(math.abs(Terrain.WaterReflectance - 1) < 1e-6)
assert(math.abs(Terrain.WaterTransparency - 0.3) < 1e-6)
assert(math.abs(Terrain.WaterWaveSize - 1) < 1e-6)
assert(math.abs(Terrain.WaterWaveSpeed - 10) < 1e-6)

Terrain.Decoration = true
Terrain.GrassLength = 0.5
Terrain.WaterColor = Color3.fromRGB(10, 20, 30)
Terrain.WaterReflectance = 5
Terrain.WaterTransparency = -1
assert(Terrain.Decoration == true)
assert(math.abs(Terrain.GrassLength - 0.5) < 1e-6)
assert(math.abs(Terrain.WaterReflectance - 1) < 1e-6, "reflectance clamps to 1")
assert(math.abs(Terrain.WaterTransparency) < 1e-6, "transparency clamps to 0")

-- Engine extensions used by the mesher.
assert(Terrain.ChunkSize == 16)
assert(Terrain.QueuedChunkCount == 0)
Terrain.VoxelSize = 4
assert(Terrain.VoxelSize == 4)
assert(not pcall(function() Terrain.VoxelSize = 0 end))
assert(Terrain.VoxelSize == 4, "a rejected VoxelSize must leave the old value")
Terrain.IsoLevel = 5
assert(math.abs(Terrain.IsoLevel - 0.999) < 1e-6)
Terrain.IsoLevel = 0.5
`,
		"terrain_service_properties",
	)


	run_script(
		&script_vm,
		`
local corner = Terrain:CellCornerToWorld(1, 2, 3)
assert(corner.X == 4 and corner.Y == 8 and corner.Z == 12)

local center = Terrain:CellCenterToWorld(1, 2, 3)
assert(center.X == 6 and center.Y == 10 and center.Z == 14)

local cell = Terrain:WorldToCell(Vector3.new(5, 9, 13))
assert(cell.X == 1 and cell.Y == 2 and cell.Z == 3)

-- PreferSolid on an empty neighbourhood still returns a cell.
local solid = Terrain:WorldToCellPreferSolid(Vector3.new(5, 9, 13))
local empty = Terrain:WorldToCellPreferEmpty(Vector3.new(5, 9, 13))
assert(typeof(solid) == "Vector3" and typeof(empty) == "Vector3")
`,
		"terrain_service_world_cell",
	)


	run_script(
		&script_vm,
		`
Terrain:Clear()
Terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(4, 4, 4), Enum.Material.Slate)
assert(Terrain:CountCells() == 8, "a 4x4x4 block fills the eight touching cell centers")
assert(Terrain.QueuedChunkCount > 0)

local materials, occupancy = Terrain:ReadVoxels(Region3.new(Vector3.new(-4, -4, -4), Vector3.new(4, 4, 4)), 4)
assert(materials[1][1][1] == Enum.Material.Slate)
assert(math.abs(occupancy[1][1][1] - 1) < 1e-6)

-- Material arguments must be Enum.Material, not strings.
assert(not pcall(function()
	Terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(4, 4, 4), "Slate")
end))
`,
		"terrain_service_fill_block",
	)


	assert(services.Terrain_Cell_Count(terrain) == 8)
	slate_cells := services.Terrain_Collect_Cells(terrain)
	defer delete(slate_cells)
	for entry in slate_cells {
		assert(entry.cell.material == enums.Material.Slate)
		assert(math.abs(entry.cell.occupancy - 1) < 1e-6)
	}


	run_script(
		&script_vm,
		`
Terrain:Clear()
local region = Region3.new(Vector3.new(0, 0, 0), Vector3.new(8, 8, 8))
local materials = {
	{
		{ Enum.Material.Sand, Enum.Material.Sand },
		{ Enum.Material.Sand, Enum.Material.Sand },
	},
	{
		{ Enum.Material.Sand, Enum.Material.Sand },
		{ Enum.Material.Sand, Enum.Material.Sand },
	},
}
local occupancy = {
	{ { 1, 1 }, { 1, 1 } },
	{ { 1, 1 }, { 1, 1 } },
}
Terrain:WriteVoxels(region, 4, materials, occupancy)
assert(Terrain:CountCells() == 8)

local read_materials, read_occupancy = Terrain:ReadVoxels(region, 4)
assert(read_materials[2][2][2] == Enum.Material.Sand)
assert(math.abs(read_occupancy[2][2][2] - 1) < 1e-6)

local empty_materials = Terrain:ReadVoxels(Region3.new(Vector3.new(100, 100, 100), Vector3.new(108, 108, 108)), 4)
assert(empty_materials[1][1][1] == Enum.Material.Air)

-- ReplaceMaterial swaps solid cells only.
Terrain:ReplaceMaterial(region, 4, Enum.Material.Sand, Enum.Material.Grass)
local replaced = Terrain:ReadVoxels(region, 4)
assert(replaced[1][1][1] == Enum.Material.Grass)
`,
		"terrain_service_voxels",
	)

	assert(services.Terrain_Cell_Count(terrain) == 8)
	grass_cells := services.Terrain_Collect_Cells(terrain)
	defer delete(grass_cells)
	for entry in grass_cells {
		assert(entry.cell.material == enums.Material.Grass)
	}


	run_script(
		&script_vm,
		`
Terrain:Clear()
Terrain:FillBall(Vector3.new(0, 0, 0), 4, Enum.Material.Concrete)
assert(Terrain:CountCells() == 8)

Terrain:Clear()
Terrain:FillRegion(Region3.new(Vector3.new(0, 0, 0), Vector3.new(8, 8, 8)), 4, Enum.Material.Wood)
assert(Terrain:CountCells() == 8)

Terrain:Clear()
Terrain:FillCylinder(CFrame.new(0, 0, 0), 4, 4, Enum.Material.Slate)
assert(Terrain:CountCells() > 0)

Terrain:Clear()
Terrain:FillWedge(CFrame.new(0, 0, 0), Vector3.new(4, 4, 4), Enum.Material.Slate)
assert(Terrain:CountCells() > 0)
`,
		"terrain_service_fill_primitives",
	)


	run_script(
		&script_vm,
		`
Terrain:Clear()
Terrain:FillRegion(Region3.new(Vector3.new(0, 0, 0), Vector3.new(8, 8, 8)), 4, Enum.Material.Slate)
local snapshot = Terrain:CopyRegion(Region3int16.new(Vector3int16.new(0, 0, 0), Vector3int16.new(2, 2, 2)))
assert(snapshot.Size.X == 2 and snapshot.Size.Y == 2 and snapshot.Size.Z == 2)

Terrain:Clear()
assert(Terrain:CountCells() == 0)
Terrain:PasteRegion(snapshot, Vector3int16.new(10, 10, 10), true)
assert(Terrain:CountCells() >= 1)

local pasted = Terrain:ReadVoxels(Region3.new(Vector3.new(40, 40, 40), Vector3.new(48, 48, 48)), 4)
assert(pasted[1][1][1] == Enum.Material.Slate)
snapshot:Destroy()
`,
		"terrain_service_copy_paste",
	)


	run_script(
		&script_vm,
		`
Terrain:Clear()
assert(Terrain:AutowedgeCell(0, 0, 0) == false)
Terrain:AutowedgeCells(Region3int16.new(Vector3int16.new(0, 0, 0), Vector3int16.new(1, 1, 1)))
Terrain:ConvertToSmooth()

Terrain:SetCell(0, 0, 0, Enum.Material.Slate)
local material, value = Terrain:GetCell(0, 0, 0)
assert(material == Enum.Material.Slate and math.abs(value - 1) < 1e-6)

Terrain:SetWaterCell(1, 1, 1)
local water_material, water = Terrain:GetWaterCell(1, 1, 1)
assert(water_material == Enum.Material.Water and math.abs(water - 1) < 1e-6)
`,
		"terrain_service_deprecated",
	)


	run_script(
		&script_vm,
		`
Terrain:Clear()
Terrain:SetVoxel(5, 6, 7, 0.75, Enum.Material.Slate)
local written = Terrain:GetVoxel(5, 6, 7)
assert(written ~= nil)
assert(math.abs(written.occupancy - 0.75) < 1e-6)
assert(written.material == Enum.Material.Slate)
assert(not pcall(function() Terrain:SetVoxel(0, 0, 0, 1, "Slate") end))

-- SetVoxel queues exactly the touched chunk for an interior voxel.
assert(Terrain.QueuedChunkCount == 1)
`,
		"terrain_service_extension_voxels",
	)

	extension_cell, extension_ok := services.Terrain_Get_Cell(terrain, 5, 6, 7)
	assert(extension_ok && extension_cell.material == enums.Material.Slate)


	version_before := terrain.draw_version
	run_script(
		&script_vm,
		`
Terrain:Clear()
Terrain:Clear()
assert(Terrain.QueuedChunkCount == 0)
assert(Terrain:CountCells() == 0)
`,
		"terrain_service_clear",
	)

	assert(services.Terrain_Cell_Count(terrain) == 0)
	assert(len(terrain.chunks) == 0)
	assert(len(terrain.dirty_lookup) == 0)
	assert(len(terrain.dirty_queue) == 0 && terrain.dirty_head == 0)
	assert(len(terrain.draw_items) == 0)
	assert(terrain.draw_dirty, "Clear must invalidate the draw list")
	assert(terrain.draw_version > version_before, "Clear must bump the draw version")


	run_script(
		&script_vm,
		`
Terrain:Clear()
Terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(4, 4, 4), Enum.Material.Grass)
`,
		"terrain_service_rebuild_setup",
	)
	assert(len(terrain.chunks) > 0)

	clear_dirty_bookkeeping(terrain)
	for _, chunk in terrain.chunks {
		assert(chunk != nil && !chunk.dirty)
	}

	run_script(&script_vm, `Terrain:GenerateMesh()`, "terrain_service_generate_mesh")
	assert(len(terrain.dirty_queue) == len(terrain.chunks))
	for key, chunk in terrain.chunks {
		assert(chunk != nil && chunk.dirty)
		assert(terrain.dirty_lookup[key])
	}


	chunks_before := len(terrain.chunks)
	queue_before := len(terrain.dirty_queue)
	services.Terrain_Prepare_3D(terrain, nil)
	services.Terrain_Prepare_3D(nil, nil)
	services.Prepare_3D(&environment.services, nil)
	assert(len(terrain.chunks) == chunks_before)
	assert(
		len(terrain.dirty_queue) == queue_before,
		"no renderer means the queue must not be drained",
	)


	run_script(
		&script_vm,
		`
Terrain:Clear()
Terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(4, 4, 4), Enum.Material.Water)
assert(Terrain:CountCells() > 0, "a Water fill must create cells")
local material, occupancy = Terrain:GetCell(0, 0, 0)
assert(material == Enum.Material.Water, "a Water fill must keep its material")
assert(occupancy == 0, "a Water fill must not be stored as solid rock")
local _, depth = Terrain:GetWaterCell(0, 0, 0)
assert(depth > 0, "a Water fill must land in the water channel")
`,
		"terrain_liquid_water",
	)

	assert(services.Terrain_Cell_Count(terrain) > 0, "a Water fill must create cells")
	water_cells := services.Terrain_Collect_Cells(terrain)
	defer delete(water_cells)
	for entry in water_cells {
		assert(entry.cell.water == 1, "a Water fill must land in the water channel")
		assert(entry.cell.occupancy == 0, "a Water fill must not be stored as solid rock")
	}

	run_script(
		&script_vm,
		`
Terrain:Clear()
Terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(4, 4, 4), Enum.Material.Glass)
assert(Terrain:CountCells() > 0, "a Glass fill must create cells")
local material, occupancy = Terrain:GetCell(0, 0, 0)
assert(material == Enum.Material.Glass, "a Glass fill must keep its material")
assert(occupancy == 0, "a Glass fill must not be stored as solid rock")
local _, depth = Terrain:GetWaterCell(0, 0, 0)
assert(depth > 0, "a Glass fill must land in the water channel")
`,
		"terrain_liquid_glass",
	)

	assert(services.Terrain_Cell_Count(terrain) > 0, "a Glass fill must create cells")
	glass_cells := services.Terrain_Collect_Cells(terrain)
	defer delete(glass_cells)
	for entry in glass_cells {
		assert(entry.cell.water == 1, "a Glass fill must land in the water channel")
		assert(entry.cell.occupancy == 0, "a Glass fill must not be stored as solid rock")
	}

	run_script(
		&script_vm,
		`
Terrain:Clear()
Terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(4, 4, 4), Enum.Material.Neon)
assert(Terrain:CountCells() > 0, "a Neon fill must create cells")
local material, occupancy = Terrain:GetCell(0, 0, 0)
assert(material == Enum.Material.Neon, "a Neon fill must keep its material")
assert(occupancy == 1, "a Neon fill must stay solid")
local _, neon_depth = Terrain:GetWaterCell(0, 0, 0)
assert(neon_depth == 0, "Neon is not a liquid")
`,
		"terrain_liquid_neon",
	)

	assert(services.Terrain_Cell_Count(terrain) > 0, "a Neon fill must create cells")
	neon_cells := services.Terrain_Collect_Cells(terrain)
	defer delete(neon_cells)
	for entry in neon_cells {
		assert(entry.cell.occupancy == 1, "a Neon fill must stay solid")
		assert(entry.cell.water == 0, "Neon is not a liquid")
	}


	run_script(
		&script_vm,
		`
Terrain:Clear()
Terrain:FillBlock(CFrame.new(0, 0, 0), Vector3.new(4, 4, 4), Enum.Material.Grass)
assert(Terrain:CountCells() > 0)
local material, occupancy = Terrain:GetCell(0, 0, 0)
assert(material == Enum.Material.Grass)
assert(occupancy == 1, "rock must stay solid")
local _, rock_depth = Terrain:GetWaterCell(0, 0, 0)
assert(rock_depth == 0, "rock must stay dry")
`,
		"terrain_liquid_grass",
	)

	assert(services.Terrain_Cell_Count(terrain) > 0)
	rock_cells := services.Terrain_Collect_Cells(terrain)
	defer delete(rock_cells)
	for entry in rock_cells {
		assert(entry.cell.occupancy == 1 && entry.cell.water == 0, "rock must stay solid and dry")
	}


	run_script(
		&script_vm,
		`
Terrain:Clear()
Terrain:SetCell(0, 0, 0, Enum.Material.Grass)
Terrain:SetWaterCell(1, 0, 0, 1)
local _, rock = Terrain:GetCell(0, 0, 0)
assert(rock == 1, "the rock cell must stay solid")
local _, explicit = Terrain:GetWaterCell(1, 0, 0)
assert(explicit == 1, "explicit water must be visible to the surface pass")
`,
		"terrain_liquid_mixed",
	)

	run_script(&script_vm, `Terrain:Clear()`, "terrain_liquid_cleanup")
	assert(services.Terrain_Cell_Count(terrain) == 0)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("TERRAIN_SERVICE_SMOKE_PASSED")
}
