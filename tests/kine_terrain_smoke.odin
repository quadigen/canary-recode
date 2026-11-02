package main

import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"

import classes "../src/engine/classes"
import enums "../src/engine/enum"
import engine_runtime "../src/engine/runtime"
import serializer "../src/engine/serializer"
import services "../src/engine/services"
import vm "../src/engine/vm"

KINE_PATH :: "build/kine-terrain-smoke.kine"


CELL_BYTES :: 17


FIXED_POINT_TOLERANCE :: f32(1.0 / 65535.0)


TERRAIN_SETTINGS_BYTES :: 42


@(private = "file")
run_script :: proc(script_vm: ^vm.VM, body, name: string) {


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


grids_match :: proc(source, loaded: ^services.Terrain) -> bool {
	if services.Terrain_Cell_Count(source) != services.Terrain_Cell_Count(loaded) {
		return false
	}
	source_cells := services.Terrain_Collect_Cells(source)
	defer delete(source_cells)
	for entry in source_cells {
		other, ok := services.Terrain_Get_Cell(loaded, entry.x, entry.y, entry.z)
		if !ok {
			return false
		}
		if entry.cell.material != other.material {
			return false
		}
		if abs(entry.cell.occupancy - other.occupancy) > FIXED_POINT_TOLERANCE {
			return false
		}
		if abs(entry.cell.water - other.water) > FIXED_POINT_TOLERANCE {
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


build_and_save_map :: proc(environment: ^engine_runtime.Environment, script_vm: ^vm.VM) {
	run_script(
		script_vm,
		`
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
	game:GetService("ExportService"):ExportToFile("` +
		KINE_PATH +
		`"),
	"saving the map failed"
)
`,
		"kine_terrain_build",
	)
}

main :: proc() {
	source_vm := vm.New()
	source: engine_runtime.Environment
	engine_runtime.Environment_Init(&source, &source_vm)
	build_and_save_map(&source, &source_vm)

	source_terrain := terrain_of(&source)
	saved_cells := services.Terrain_Cell_Count(source_terrain)
	fmt.printf("source terrain holds %d voxels\n", saved_cells)
	assert(saved_cells > 1, "the source map should have filled some voxels")


	client_vm := vm.New()
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&client, &client_vm)

	assert(engine_runtime.Load_Map(&client, &client_vm, KINE_PATH), "the saved map should load")

	loaded := terrain_of(&client)
	assert(
		services.Terrain_Cell_Count(loaded) == saved_cells,
		fmt.tprintf(
			"every voxel should survive a save and load: expected %d, got %d",
			saved_cells,
			services.Terrain_Cell_Count(loaded),
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


	assert(
		grids_match(source_terrain, loaded),
		"the restored grid should match the saved one cell for cell",
	)


	solid_found := false
	loaded_cells := services.Terrain_Collect_Cells(loaded)
	defer delete(loaded_cells)
	for entry in loaded_cells {
		if entry.cell.occupancy == 1 {
			assert(
				entry.cell.material == enums.Material.Grass,
				"a solid voxel should keep its material",
			)
			solid_found = true
		}
	}
	assert(solid_found, "the block should restore at least one fully occupied voxel")


	water_found := false
	for entry in loaded_cells {
		if entry.cell.water > 0 {
			assert(entry.cell.occupancy == 0, "a water cell should not also be solid")
			water_found = true
		}
	}
	assert(water_found, "a water cell should restore its level")


	assert(loaded.geometry_version > 0, "restoring terrain must invalidate collision")


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
	append(
		&table.cells,
		serializer.Kine_Terrain_Cell{x = 0, y = 0, z = 0, material = 1, occupancy = 1},
	)
	append(
		&table.cells,
		serializer.Kine_Terrain_Cell{x = 1, y = 0, z = 0, material = 1, occupancy = 1},
	)
	defer serializer.Kine_Terrain_Destroy(&table)

	data, serialize_err := serializer.Serialize(
		&environment.classes,
		script_vm.L,
		root,
		nil,
		&table,
	)
	if !serializer.Error_Is_None(serialize_err) {
		panic(
			fmt.tprintf(
				"a map with terrain should serialize: %s",
				serializer.Error_String(serialize_err),
			),
		)
	}
	serializer.Error_Delete(&serialize_err)
	assert(data != nil, "a map with terrain should serialize to bytes")
	defer delete(data)


	assert(data[4] == u8(serializer.KINE_VERSION), "the saved version byte should be current")

	cell_count := len(table.cells)
	count_offset := len(data) - cell_count * CELL_BYTES - 4
	assert(count_offset > 5, "the cell count should sit just before the cells")


	control: serializer.Kine_Terrain
	defer serializer.Kine_Terrain_Destroy(&control)
	loaded, control_err := serializer.Deserialize_From_Data(
		&environment.classes,
		script_vm.L,
		nil,
		data,
		&control,
	)
	if !serializer.Error_Is_None(control_err) {
		panic(
			fmt.tprintf(
				"a well formed stream should load: %s",
				serializer.Error_String(control_err),
			),
		)
	}
	serializer.Error_Delete(&control_err)
	assert(loaded != nil, "a well formed stream should produce an object")
	assert(control.cells != nil && len(control.cells) == cell_count, "cells should round trip")
	if loaded != nil {
		classes.Destroy_Hierarchy(loaded)
	}


	hostile := slice.clone(data)
	defer delete(hostile)
	hostile[count_offset + 0] = 0xFF
	hostile[count_offset + 1] = 0xFF
	hostile[count_offset + 2] = 0xFF
	hostile[count_offset + 3] = 0xFF
	rejected, hostile_err := serializer.Deserialize_From_Data(
		&environment.classes,
		script_vm.L,
		nil,
		hostile,
	)
	expect_rejection(
		rejected,
		&hostile_err,
		.Terrain_Cell_Count_Exceeded,
		"an impossible cell count",
	)


	out_of_range := slice.clone(data)
	defer delete(out_of_range)
	out_of_range[count_offset + 4 + 0] = 0x00
	out_of_range[count_offset + 4 + 1] = 0x00
	out_of_range[count_offset + 4 + 2] = 0x40
	out_of_range[count_offset + 4 + 3] = 0x00
	rejected_range, range_err := serializer.Deserialize_From_Data(
		&environment.classes,
		script_vm.L,
		nil,
		out_of_range,
	)
	expect_rejection(
		rejected_range,
		&range_err,
		.Terrain_Cell_Out_Of_Range,
		"an out of range coordinate",
	)


	truncated := slice.clone(data[:len(data) - 3])
	defer delete(truncated)
	rejected_truncated, truncated_err := serializer.Deserialize_From_Data(
		&environment.classes,
		script_vm.L,
		nil,
		truncated,
	)
	expect_rejection(
		rejected_truncated,
		&truncated_err,
		.Terrain_Cell_Count_Exceeded,
		"a terrain section missing its last cells",
	)


	assert(
		count_offset > TERRAIN_SETTINGS_BYTES + 1,
		"the terrain section should be long enough to cut into its settings",
	)
	short_header := slice.clone(data[:count_offset - 40])
	defer delete(short_header)
	rejected_header, header_err := serializer.Deserialize_From_Data(
		&environment.classes,
		script_vm.L,
		nil,
		short_header,
	)
	expect_rejection(
		rejected_header,
		&header_err,
		.Terrain_Truncated,
		"a stream cut inside the terrain header",
	)


	trailing := make([]u8, len(data) + 1)
	defer delete(trailing)
	copy(trailing, data)
	trailing[len(data)] = 0x00
	rejected_trailing, trailing_err := serializer.Deserialize_From_Data(
		&environment.classes,
		script_vm.L,
		nil,
		trailing,
	)
	expect_rejection(
		rejected_trailing,
		&trailing_err,
		.Trailing_Bytes,
		"a stream with trailing bytes",
	)


	not_kine := []u8{'N', 'O', 'P', 'E', 0x04, 0x00}
	rejected_magic, magic_err := serializer.Deserialize_From_Data(
		&environment.classes,
		script_vm.L,
		nil,
		not_kine,
	)
	expect_rejection(rejected_magic, &magic_err, .Bad_Magic, "a stream that is not a .kine file")
}


@(private = "file")
expect_rejection :: proc(
	object: ^classes.Object,
	err: ^serializer.Error,
	expected: serializer.Error_Kind,
	what: string,
) {
	if object != nil {
		panic(fmt.tprintf("%s must not produce an object", what))
	}
	message := serializer.Error_String(err^)
	actual := err.kind
	offset := err.offset
	serializer.Error_Delete(err)
	if actual != expected {
		detail := fmt.tprintf(
			"%s should be rejected as %v but came back as %v: %s",
			what,
			expected,
			actual,
			message,
		)
		delete(message)
		panic(detail)
	}
	if offset < 0 {
		detail := fmt.tprintf("%s should report a byte offset: %s", what, message)
		delete(message)
		panic(detail)
	}
	delete(message)
}
