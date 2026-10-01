package main

import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"

import classes "../src/engine/classes"
import engine_runtime "../src/engine/runtime"
import enums "../src/engine/enum"
import serializer "../src/engine/serializer"
import services "../src/engine/services"
import vm "../src/engine/vm"

KINE_PATH :: "build/kine-terrain-smoke.kine"

// The cell layout the format documents. These tests would rather state the
// expected byte cost than trust a constant that could drift from the writer.
CELL_BYTES :: 17

// One 16-bit fixed point step is 1/65535 of the range.
FIXED_POINT_TOLERANCE :: f32(1.0 / 65535.0)

// The chunk name is only used for diagnostics on a failed run.
@(private="file")
run_script :: proc(script_vm: ^vm.VM, body, name: string) {
	// ExportService is gated behind internal studio access, which is the same
	// capability the editor's own save path runs with. Without it the call would
	// be refused as a security error rather than failing for a real reason.
	previous := vm.GetThreadSecurityCapabilities(script_vm.L)
	vm.SetThreadSecurityCapabilities(script_vm.L, vm.THREAD_SECURITY_ALL)
	defer vm.SetThreadSecurityCapabilities(script_vm.L, previous)

	ok, err := vm.Run(script_vm, body, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("kine terrain smoke test failed")
	}
}

// grids_match compares two voxel grids cell for cell. Voxel occupancy and water
// are stored as 16-bit fixed point, so a round trip is exact only to that
// resolution and a strict equality would fail on a value that was never a whole
// number of steps to begin with.
grids_match :: proc(source, loaded: ^services.Terrain) -> bool {
	if len(source.voxels) != len(loaded.voxels) {
		return false
	}
	for key, cell in source.voxels {
		other, ok := loaded.voxels[key]
		if !ok {
			return false
		}
		if cell.material != other.material {
			return false
		}
		if abs(cell.occupancy - other.occupancy) > FIXED_POINT_TOLERANCE {
			return false
		}
		if abs(cell.water - other.water) > FIXED_POINT_TOLERANCE {
			return false
		}
	}
	return true
}

terrain_of :: proc(environment: ^engine_runtime.Environment) -> ^services.Terrain {
	object := services.Ensure_Service(&environment.services, "Terrain")
	assert(object != nil, "the Terrain service must be instantiable")
	return cast(^services.Terrain)object
}

// build_map creates a map with a Part in it and a distinctive block of terrain,
// then saves it through the same ExportService entry point the editor's
// "Save to File" menu uses.
build_and_save_map :: proc(environment: ^engine_runtime.Environment, script_vm: ^vm.VM) {
	run_script(script_vm, `
local model = Instance.new("Model")
model.Name = "TerrainMap"
local part = Instance.new("Part")
part.Name = "Marker"
part.Position = Vector3.new(11, 22, 33)
part.Parent = model
model.Parent = game:GetService("Workspace")

local Terrain = game:GetService("Terrain")
Terrain.VoxelSize = 4
Terrain.WaterColor = Color3.new(0.25, 0.5, 0.75)
Terrain.GrassLength = 3.5

-- A solid block plus a single water cell, so the saved grid has to carry both an
-- occupancy and a water channel as well as a material.
Terrain:FillBlock(CFrame.new(0, 8, 0), Vector3.new(12, 4, 12), Enum.Material.Grass)
-- The block fills voxels x=-2..1, y=1..2, z=-2..1, so this water cell sits
-- outside it and has no solid occupancy of its own.
Terrain:SetWaterCell(3, 1, 3)
Terrain:SetVoxel(4, 1, 4, 0.5, Enum.Material.Water)

assert(
	game:GetService("ExportService"):ExportToFile("` + KINE_PATH + `"),
	"saving the map failed"
)
`, "kine_terrain_build")
}

main :: proc() {
	source_vm := vm.New()
	source: engine_runtime.Environment
	engine_runtime.Environment_Init(&source, &source_vm)
	build_and_save_map(&source, &source_vm)

	source_terrain := terrain_of(&source)
	saved_cells := len(source_terrain.voxels)
	fmt.printf("source terrain holds %d voxels\n", saved_cells)
	assert(saved_cells > 1, "the source map should have filled some voxels")

	// A second, empty environment is the real test: it can only see the terrain
	// that actually made it into the file.
	client_vm := vm.New()
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&client, &client_vm)

	assert(
		engine_runtime.Load_Map(&client, &client_vm, KINE_PATH),
		"the saved map should load"
	)

	loaded := terrain_of(&client)
	assert(
		len(loaded.voxels) == saved_cells,
		fmt.tprintf(
			"every voxel should survive a save and load: expected %d, got %d",
			saved_cells,
			len(loaded.voxels),
		),
	)

	assert(loaded.voxel_size == source_terrain.voxel_size, "voxel size should round trip")
	assert(loaded.iso_level == source_terrain.iso_level, "iso level should round trip")
	assert(loaded.grass_length == source_terrain.grass_length, "grass length should round trip")
	assert(
		loaded.water_color.R == source_terrain.water_color.R &&
			loaded.water_color.G == source_terrain.water_color.G &&
			loaded.water_color.B == source_terrain.water_color.B,
		"water colour should round trip",
	)

	// Rather than hard coding which voxel indices a fill happened to land on,
	// compare the whole grid: every cell of the source must reappear unchanged,
	// including the water cells whose level lives in a separate channel.
	assert(
		grids_match(source_terrain, loaded),
		"the restored grid should match the saved one cell for cell",
	)

	// A solid voxel has to come back solid, not as an empty cell that silently
	// leaves a hole where the ground was.
	solid_found := false
	for key, cell in loaded.voxels {
		if cell.occupancy == 1 {
			assert(cell.material == enums.Material.Grass, "a solid voxel should keep its material")
			solid_found = true
		}
		_ = key
	}
	assert(solid_found, "the block should restore at least one fully occupied voxel")

	// Water is stored in its own channel, so it only survives if both channels
	// were written.
	water_found := false
	for _, cell in loaded.voxels {
		if cell.water > 0 {
			assert(cell.occupancy == 0, "a water cell should not also be solid")
			water_found = true
		}
	}
	assert(water_found, "a water cell should restore its level")

	// Collision reads geometry_version, so a restored map that left it alone
	// would stand on invisible ground.
	assert(loaded.geometry_version > 0, "restoring terrain must invalidate collision")

	// The instance half of the file still has to arrive.
	workspace := services.Ensure_Service(&client.services, "Workspace")
	loaded_model := classes.Find_First_Child(workspace, "TerrainMap")
	assert(loaded_model != nil, "the map model should load")
	loaded_part := classes.Find_First_Child(loaded_model, "Marker")
	assert(loaded_part != nil && (cast(^classes.Part)loaded_part).cframe.x == 11)

	check_malformed_streams_rejected(&client, &client_vm)

	engine_runtime.Environment_Destroy(&client)
	engine_runtime.Environment_Destroy(&source)
	fmt.println("KINE_TERRAIN_SMOKE_PASSED")
}

// check_malformed_streams_rejected covers the hostile cases a save file can
// present, since a .kine file is untrusted input. Each stream is built in memory
// so the bytes being corrupted are known exactly.
check_malformed_streams_rejected :: proc(
	environment: ^engine_runtime.Environment,
	script_vm: ^vm.VM,
) {
	root := services.Ensure_Service(&environment.services, "Workspace")
	assert(root != nil)

	table: serializer.Kine_Terrain
	table.voxel_size = 4
	table.iso_level = 0.5
	table.cells = make([dynamic]serializer.Kine_Terrain_Cell, 0, 2)
	append(&table.cells, serializer.Kine_Terrain_Cell{x = 0, y = 0, z = 0, material = 1, occupancy = 1})
	append(&table.cells, serializer.Kine_Terrain_Cell{x = 1, y = 0, z = 0, material = 1, occupancy = 1})
	defer serializer.Kine_Terrain_Destroy(&table)

	data, ok := serializer.Serialize(&environment.classes, script_vm.L, root, nil, &table)
	assert(ok && data != nil, "a map with terrain should serialize")
	defer delete(data)

	// The documented version has to be what was written, since older builds read
	// the version byte to decide whether a terrain section follows the tree.
	assert(data[4] == u8(serializer.KINE_VERSION), "the saved version byte should be current")

	cell_count := len(table.cells)
	count_offset := len(data) - cell_count * CELL_BYTES - 4
	assert(count_offset > 5, "the cell count should sit just before the cells")

	// A well formed stream is the control case: the corruption below has to be
	// what causes the rejection, not the format itself.
	control: serializer.Kine_Terrain
	defer serializer.Kine_Terrain_Destroy(&control)
	loaded, control_ok := serializer.Deserialize_From_Data(&environment.classes, script_vm.L, nil, data, &control)
	assert(control_ok && loaded != nil, "a well formed stream should load")
	assert(control.cells != nil && len(control.cells) == cell_count, "cells should round trip")
	if loaded != nil {
		classes.Destroy_Hierarchy(loaded)
	}

	// A cell count far larger than the bytes present must be refused. Without the
	// bound a short file could demand a multi-gigabyte allocation before the
	// reader noticed it ran out of data.
	hostile := slice.clone(data)
	defer delete(hostile)
	hostile[count_offset + 0] = 0xFF
	hostile[count_offset + 1] = 0xFF
	hostile[count_offset + 2] = 0xFF
	hostile[count_offset + 3] = 0xFF
	rejected, hostile_ok := serializer.Deserialize_From_Data(&environment.classes, script_vm.L, nil, hostile)
	assert(!hostile_ok && rejected == nil, "an impossible cell count must be rejected")

	// A coordinate past the supported range would place a voxel far outside any
	// renderable or collidable area.
	out_of_range := slice.clone(data)
	defer delete(out_of_range)
	out_of_range[count_offset + 4 + 0] = 0x00
	out_of_range[count_offset + 4 + 1] = 0x00
	out_of_range[count_offset + 4 + 2] = 0x40
	out_of_range[count_offset + 4 + 3] = 0x00
	rejected_range, range_ok := serializer.Deserialize_From_Data(&environment.classes, script_vm.L, nil, out_of_range)
	assert(!range_ok && rejected_range == nil, "an out of range coordinate must be rejected")

	// Truncating the tail leaves the tree intact and the terrain section short,
	// which must be caught rather than applied as a partial world.
	truncated := slice.clone(data[:len(data)-3])
	defer delete(truncated)
	rejected_truncated, truncated_ok := serializer.Deserialize_From_Data(&environment.classes, script_vm.L, nil, truncated)
	assert(!truncated_ok && rejected_truncated == nil, "a truncated terrain section must be rejected")
}



