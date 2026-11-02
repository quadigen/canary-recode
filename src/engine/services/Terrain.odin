package services
// wire:service


import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import materials "../material"
import serializer "../serializer"
import marching_cubes "../util/marching_cubes"
import vm "../vm"
import "core:math"
import "core:strings"
import "core:thread"

TERRAIN_CACHE_PAD :: 2
TERRAIN_CACHE_DIM :: TERRAIN_CHUNK_SIZE + 1 + 2 * TERRAIN_CACHE_PAD

TERRAIN_CHUNK_SIZE :: 16
TERRAIN_CHUNK_DATA_DIM :: TERRAIN_CHUNK_SIZE + 2 * TERRAIN_CACHE_PAD
TERRAIN_CHUNK_VOXELS :: TERRAIN_CHUNK_SIZE * TERRAIN_CHUNK_SIZE * TERRAIN_CHUNK_SIZE

TERRAIN_REBUILDS_PER_FRAME :: 8
TERRAIN_MAX_VERTICES_PER_MESH :: 65532
TERRAIN_STREAM_ID :: u64(0x5445525241494E)


TERRAIN_GPU_LATT :: TERRAIN_CHUNK_SIZE + 1
TERRAIN_GPU_MAX_VERTICES :: 3 * TERRAIN_GPU_LATT * TERRAIN_GPU_LATT * TERRAIN_GPU_LATT
TERRAIN_GPU_MAX_INDICES :: TERRAIN_CHUNK_VOXELS * 5 * 3


TERRAIN_GPU_MESHING :: #config(KINE_TERRAIN_GPU_MESHING, ODIN_OS != .JS)

TERRAIN_DEFAULT_VOXEL_SIZE :: f32(4)
TERRAIN_DEFAULT_ISO_LEVEL :: f32(0.5)

Terrain_Radius_Bounds :: struct {
	center: datatypes.Vector3,
	radius: f32,
}

Terrain_Max_Extents :: datatypes.Region3int16 {
	Min = datatypes.Vector3int16{-16000, -16000, -16000},
	Max = datatypes.Vector3int16{16000, 16000, 16000},
}


terrain_sdf_bounds :: proc(
	service: ^Terrain,
	shape: Terrain_SDF_Shape,
	pad_cells: int,
) -> datatypes.Region3int16 {
	min_x: int
	max_x: int
	min_y: int
	max_y: int
	min_z: int
	max_z: int

	if shape.kind == .Sphere {
		r := shape.radius + f32(pad_cells)
		world_min := datatypes.Vector3{shape.center.x - r, shape.center.y - r, shape.center.z - r}
		world_max := datatypes.Vector3{shape.center.x + r, shape.center.y + r, shape.center.z + r}
		min_x = int(math.floor(world_min.x / service.voxel_size))
		min_y = int(math.floor(world_min.y / service.voxel_size))
		min_z = int(math.floor(world_min.z / service.voxel_size))
		max_x = int(math.floor(world_max.x / service.voxel_size))
		max_y = int(math.floor(world_max.y / service.voxel_size))
		max_z = int(math.floor(world_max.z / service.voxel_size))
	} else {
		h := datatypes.Vector3 {
			shape.half.x + f32(pad_cells),
			shape.half.y + f32(pad_cells),
			shape.half.z + f32(pad_cells),
		}
		local_corners := [8]datatypes.Vector3 {
			{-h.x, -h.y, -h.z},
			{h.x, -h.y, -h.z},
			{h.x, h.y, -h.z},
			{-h.x, h.y, -h.z},
			{-h.x, -h.y, h.z},
			{h.x, -h.y, h.z},
			{h.x, h.y, h.z},
			{-h.x, h.y, h.z},
		}
		world_min := datatypes.Vector3{math.INF_F32, math.INF_F32, math.INF_F32}
		world_max := datatypes.Vector3{-math.INF_F32, -math.INF_F32, -math.INF_F32}
		for corner in local_corners {
			world := datatypes.CFrame_Mul_Vector3(shape.cframe, corner)
			world_min = datatypes.Vec3_Min(world_min, world)
			world_max = datatypes.Vec3_Max(world_max, world)
		}
		min_x = int(math.floor(world_min.x / service.voxel_size))
		min_y = int(math.floor(world_min.y / service.voxel_size))
		min_z = int(math.floor(world_min.z / service.voxel_size))
		max_x = int(math.floor(world_max.x / service.voxel_size))
		max_y = int(math.floor(world_max.y / service.voxel_size))
		max_z = int(math.floor(world_max.z / service.voxel_size))
	}

	return datatypes.Region3int16 {
		Min = datatypes.Vector3int16{i16(min_x), i16(min_y), i16(min_z)},
		Max = datatypes.Vector3int16{i16(max_x), i16(max_y), i16(max_z)},
	}
}


Terrain_Class := classes.Class_Info {
	name   = "Terrain",
	parent = &Service_Class,
}

Terrain_Type :: enum u8 {
	Flat,
	Hills,
	Mountains,
}

Terrain_Voxel_Key :: struct {
	x, y, z: int,
}

Terrain_Chunk_Key :: struct {
	x, y, z: int,
}

Terrain_Density_Cache :: struct {
	ox, oy, oz: int,
	data:       [TERRAIN_CACHE_DIM * TERRAIN_CACHE_DIM * TERRAIN_CACHE_DIM]f32,
}


Terrain_Cell :: struct {
	occupancy: f32,
	water:     f32,
	material:  enums.Material,
}


Terrain_Chunk_Data :: struct {
	occupancy: [TERRAIN_CHUNK_VOXELS]f32,
	water:     [TERRAIN_CHUNK_VOXELS]f32,
	material:  [TERRAIN_CHUNK_VOXELS]enums.Material,
	present:   int,
	solid:     int,
	surface:   int,
}

Terrain_Chunk :: struct {
	key:             Terrain_Chunk_Key,
	dirty:           bool,
	collision_dirty: bool,
	meshes:          [dynamic]^kineffi.KineFilamentMesh,
	data:            ^Terrain_Chunk_Data,
}


Terrain_Cell_Entry :: struct {
	x, y, z: int,
	cell:    Terrain_Cell,
}

Terrain_Fill_Options :: struct {
	terrain_type:      Terrain_Type,
	caves:             bool,
	seed:              i64,
	noise_scale:       f32,
	roughness:         f32,
	cave_density:      f32,
	cave_size:         f32,
	material_override: enums.Material,
	has_material:      bool,
}


Terrain_Region_Cells :: struct {
	origin:                    datatypes.Vector3,
	resolution:                f32,
	count_x, count_y, count_z: int,
}


Terrain_Cell_Record :: struct {
	x, y, z:   i32,
	occupancy: f32,
	water:     f32,
	material:  enums.Material,
}


Terrain_Dirty_Cell :: struct {
	record: Terrain_Cell_Record,
	serial: u64,
}


TERRAIN_DIRTY_LIMIT: int = 262144

Terrain :: struct {
	using service:      Service,
	chunks:             map[Terrain_Chunk_Key]^Terrain_Chunk,
	dirty_lookup:       map[Terrain_Chunk_Key]bool,
	dirty_queue:        [dynamic]Terrain_Chunk_Key,
	dirty_head:         int,
	preparing:          bool,
	voxel_size:         f32,
	iso_level:          f32,
	replication_dirty:  map[Terrain_Voxel_Key]Terrain_Dirty_Cell,
	change_serial:      u64,
	dirty_epoch:        u64,
	dirty_tracking:     bool,
	decoration:         bool,
	grass_length:       f32,
	water_color:        datatypes.Color3,
	water_reflectance:  f32,
	water_transparency: f32,
	water_wave_size:    f32,
	water_wave_speed:   f32,
	material_colors:    map[enums.Material]datatypes.Color3,
	material_variant:   string,
	shader_revision:    u64,
	texture_set:        ^kineffi.KineFilamentTex,
	texture_context:    ^kineffi.KineFilamentContext,
	draw_items:         [dynamic]kineffi.KineFilamentDrawItem,
	draw_dirty:         bool,
	draw_version:       u64,
	geometry_version:   u64,
	renderer:           ^classes.Renderer_Object,
	surface_mesh:       ^kineffi.KineFilamentMesh,
	gpu_occ:            [dynamic]f32,
	gpu_mat:            [dynamic]u32,
	gpu_verts:          [dynamic]f32,
	gpu_weights:        [dynamic]f32,
	gpu_indices:        [dynamic]u32,
}

terrain_material_names := enums.Material_Names

terrain_floor_div :: proc(value, divisor: int) -> int {
	q := value / divisor
	r := value % divisor
	if r < 0 {
		q -= 1
	}
	return q
}

terrain_floor_mod :: proc(value, divisor: int) -> int {
	r := value % divisor
	if r < 0 {
		r += divisor
	}
	return r
}

terrain_chunk_key_for_voxel :: proc(x, y, z: int) -> Terrain_Chunk_Key {
	return Terrain_Chunk_Key {
		terrain_floor_div(x, TERRAIN_CHUNK_SIZE),
		terrain_floor_div(y, TERRAIN_CHUNK_SIZE),
		terrain_floor_div(z, TERRAIN_CHUNK_SIZE),
	}
}

terrain_get_or_create_chunk :: proc(service: ^Terrain, key: Terrain_Chunk_Key) -> ^Terrain_Chunk {
	if chunk, ok := service.chunks[key]; ok {
		return chunk
	}

	chunk := new(Terrain_Chunk)
	chunk.key = key
	chunk.dirty = true
	chunk.collision_dirty = true
	chunk.meshes = make([dynamic]^kineffi.KineFilamentMesh)
	service.chunks[key] = chunk
	return chunk
}

terrain_queue_chunk_dirty :: proc(service: ^Terrain, key: Terrain_Chunk_Key) {
	if _, queued := service.dirty_lookup[key]; !queued {
		service.dirty_lookup[key] = true
		append(&service.dirty_queue, key)
	}
}

terrain_mark_chunk_dirty :: proc(service: ^Terrain, key: Terrain_Chunk_Key) {
	chunk := terrain_get_or_create_chunk(service, key)
	chunk.dirty = true
	chunk.collision_dirty = true
	terrain_queue_chunk_dirty(service, key)
}

terrain_mark_voxel_dirty :: proc(service: ^Terrain, x, y, z: int) {
	service.geometry_version += 1
	key := terrain_chunk_key_for_voxel(x, y, z)
	terrain_mark_chunk_dirty(service, key)

	lx := terrain_floor_mod(x, TERRAIN_CHUNK_SIZE)
	ly := terrain_floor_mod(y, TERRAIN_CHUNK_SIZE)
	lz := terrain_floor_mod(z, TERRAIN_CHUNK_SIZE)


	if lx == 0 {terrain_mark_chunk_dirty(service, {key.x - 1, key.y, key.z})}
	if lx == TERRAIN_CHUNK_SIZE - 1 {terrain_mark_chunk_dirty(service, {key.x + 1, key.y, key.z})}
	if ly == 0 {terrain_mark_chunk_dirty(service, {key.x, key.y - 1, key.z})}
	if ly == TERRAIN_CHUNK_SIZE - 1 {terrain_mark_chunk_dirty(service, {key.x, key.y + 1, key.z})}
	if lz == 0 {terrain_mark_chunk_dirty(service, {key.x, key.y, key.z - 1})}
	if lz == TERRAIN_CHUNK_SIZE - 1 {terrain_mark_chunk_dirty(service, {key.x, key.y, key.z + 1})}
}

terrain_mark_all_dirty :: proc(service: ^Terrain) {
	for key, _ in service.chunks {
		terrain_mark_chunk_dirty(service, key)
	}
}


terrain_mark_voxel_region_dirty :: proc(
	service: ^Terrain,
	min_x, min_y, min_z, max_x, max_y, max_z: int,
) {
	min_cx := terrain_floor_div(min_x - 1, TERRAIN_CHUNK_SIZE)
	max_cx := terrain_floor_div(max_x + 1, TERRAIN_CHUNK_SIZE)
	min_cy := terrain_floor_div(min_y - 1, TERRAIN_CHUNK_SIZE)
	max_cy := terrain_floor_div(max_y + 1, TERRAIN_CHUNK_SIZE)
	min_cz := terrain_floor_div(min_z - 1, TERRAIN_CHUNK_SIZE)
	max_cz := terrain_floor_div(max_z + 1, TERRAIN_CHUNK_SIZE)
	for cx in min_cx ..= max_cx {
		for cy in min_cy ..= max_cy {
			for cz in min_cz ..= max_cz {
				key := Terrain_Chunk_Key{cx, cy, cz}
				chunk, ok := service.chunks[key]
				if !ok || chunk == nil {
					continue
				}
				chunk.dirty = true
				chunk.collision_dirty = true
				terrain_queue_chunk_dirty(service, key)
			}
		}
	}
}


terrain_material_layer :: proc(material: enums.Material) -> int {
	#partial switch material {
	case .Grass, .LeafyGrass, .Ground, .Mud:
		return 0
	case .Sand, .Sandstone, .Salt:
		return 1
	case .Slate, .Glass, .Basalt, .Rock, .Granite, .Pebble, .CrackedLava:
		return 2
	case .Concrete, .Brick, .Limestone, .Pavement, .Cobblestone, .Asphalt:
		return 3
	case .Wood, .WoodPlanks:
		return 5
	case .SmoothPlastic, .Neon, .Water, .Air, .debug:
		return 4
	case:
		return 4
	}
}


terrain_material_is_liquid :: proc(material: enums.Material) -> bool {
	return material == .Water || material == .Glass
}


terrain_cell_has_surface :: proc(water: f32, material: enums.Material) -> bool {
	return water > 0 || material == .Neon
}


terrain_material_surface_kind :: proc(material: enums.Material) -> i32 {
	#partial switch material {
	case .Glass:
		return kineffi.KINE_MAT_GLASS
	case .Neon:
		return kineffi.KINE_MAT_NEON
	case:
		return kineffi.KINE_MAT_WATER
	}
}

terrain_default_material_color :: proc(material: enums.Material) -> datatypes.Color3 {
	#partial switch material {
	case .Grass:
		return datatypes.Color3{0.31, 0.55, 0.25}
	case .Sand:
		return datatypes.Color3{0.84, 0.79, 0.60}
	case .Brick:
		return datatypes.Color3{0.64, 0.32, 0.24}
	case .Wood:
		return datatypes.Color3{0.42, 0.30, 0.17}
	case .Concrete:
		return datatypes.Color3{0.80, 0.80, 0.78}
	case .Slate:
		return datatypes.Color3{0.40, 0.40, 0.42}
	case .Water:
		return datatypes.Color3{0.05, 0.29, 0.55}
	case .Glass:
		return datatypes.Color3{0.72, 0.85, 0.90}
	case .Neon:
		return datatypes.Color3{0.20, 1.00, 0.35}
	case .SmoothPlastic, .debug, .Air:
		return datatypes.Color3{1, 1, 1}
	}
	if enums.Material_Is_Valid(int(material)) {
		color := enums.Material_Default_Colors[int(material)]
		return datatypes.Color3{f32(color[0]) / 255, f32(color[1]) / 255, f32(color[2]) / 255}
	}
	return datatypes.Color3{1, 1, 1}
}

terrain_material_color :: proc(service: ^Terrain, material: enums.Material) -> datatypes.Color3 {
	if color, ok := service.material_colors[material]; ok {
		return color
	}
	return terrain_default_material_color(material)
}

terrain_arg_material :: proc(
	L: ^vm.State,
	index: int,
	enum_registry: ^enums.Registry,
	fallback: enums.Material,
) -> enums.Material {
	if enum_registry == nil || vm.IsNoneOrNil(L, index) {
		return fallback
	}
	item := enums.Arg_Item(L, index, enum_registry, "Material")
	if item == nil {
		return fallback
	}
	return enums.Material(item.value)
}

terrain_table_material :: proc(
	L: ^vm.State,
	table_index: int,
	enum_registry: ^enums.Registry,
) -> (
	enums.Material,
	bool,
) {
	_ = vm.GetField(L, table_index, "material")
	defer vm.Pop(L)
	if enum_registry == nil || !vm.IsUserdataType(L, -1, &enum_registry.item_binding) {
		return .Grass, false
	}
	item := enums.Arg_Item(L, -1, enum_registry, "Material")
	if item == nil {
		return .Grass, false
	}
	return enums.Material(item.value), true
}


terrain_chunk_local_index :: proc(x, y, z: int) -> int {
	lx := terrain_floor_mod(x, TERRAIN_CHUNK_SIZE)
	ly := terrain_floor_mod(y, TERRAIN_CHUNK_SIZE)
	lz := terrain_floor_mod(z, TERRAIN_CHUNK_SIZE)
	return (lx * TERRAIN_CHUNK_SIZE + ly) * TERRAIN_CHUNK_SIZE + lz
}


terrain_chunk_data_at :: proc(
	service: ^Terrain,
	x, y, z: int,
	create: bool,
) -> (
	data: ^Terrain_Chunk_Data,
	index: int,
	existed: bool,
) {
	key := terrain_chunk_key_for_voxel(x, y, z)
	chunk, ok := service.chunks[key]
	if !ok {
		if !create {
			return nil, 0, false
		}
		chunk = terrain_get_or_create_chunk(service, key)
	}
	if chunk.data == nil {
		if !create {
			return nil, 0, false
		}
		chunk.data = new(Terrain_Chunk_Data)
		return chunk.data, terrain_chunk_local_index(x, y, z), false
	}
	return chunk.data, terrain_chunk_local_index(x, y, z), true
}

terrain_get_cell :: proc(service: ^Terrain, x, y, z: int) -> (Terrain_Cell, bool) {
	data, index, _ := terrain_chunk_data_at(service, x, y, z, false)
	if data == nil {
		return {}, false
	}
	occ := data.occupancy[index]
	wat := data.water[index]
	if occ <= 0 && wat <= 0 {
		return {}, false
	}
	return Terrain_Cell{occupancy = occ, water = wat, material = data.material[index]}, true
}

terrain_cell_present :: proc(cell: Terrain_Cell) -> bool {
	return cell.occupancy > 0 || cell.water > 0
}

terrain_occupancy :: proc(service: ^Terrain, x, y, z: int) -> f32 {
	if cell, ok := terrain_get_cell(service, x, y, z); ok {
		if terrain_material_is_liquid(cell.material) {
			return 0
		}
		return cell.occupancy
	}
	return 0
}

terrain_water :: proc(service: ^Terrain, x, y, z: int) -> f32 {
	if cell, ok := terrain_get_cell(service, x, y, z); ok {
		return cell.water
	}
	return 0
}


terrain_erase_cell_data :: proc(service: ^Terrain, x, y, z: int) -> bool {
	data, index, existed := terrain_chunk_data_at(service, x, y, z, false)
	if !existed || data == nil {
		return false
	}
	if data.occupancy[index] <= 0 && data.water[index] <= 0 {
		return false
	}
	if terrain_cell_has_surface(data.water[index], data.material[index]) {
		data.surface -= 1
	}
	if data.occupancy[index] > 0 {
		data.solid -= 1
	}
	data.occupancy[index] = 0
	data.water[index] = 0
	data.material[index] = .Air
	data.present -= 1
	return true
}

terrain_erase_cell :: proc(service: ^Terrain, x, y, z: int) {
	if terrain_erase_cell_data(service, x, y, z) {
		terrain_mark_voxel_dirty(service, x, y, z)
	}
}


terrain_store_cell :: proc(
	service: ^Terrain,
	x, y, z: int,
	occupancy, water: f32,
	material: enums.Material,
) -> bool {
	occ := clamp(occupancy, 0, 1)
	wat := clamp(water, 0, 1)


	if terrain_material_is_liquid(material) && occ > 0 {
		wat = max(wat, occ)
		occ = 0
	}

	if occ <= 0 && wat <= 0 {


		terrain_note_change(service, x, y, z, 0, 0, material)
		return terrain_erase_cell_data(service, x, y, z)
	}

	data, index, _ := terrain_chunk_data_at(service, x, y, z, true)
	if data == nil {
		return false
	}

	was_present := data.occupancy[index] > 0 || data.water[index] > 0
	was_solid := data.occupancy[index] > 0
	was_surface := terrain_cell_has_surface(data.water[index], data.material[index])
	data.occupancy[index] = occ
	data.water[index] = wat
	data.material[index] = material
	if !was_present {
		data.present += 1
	}
	if was_solid != (occ > 0) {
		if occ > 0 {
			data.solid += 1
		} else {
			data.solid -= 1
		}
	}
	is_surface := terrain_cell_has_surface(wat, material)
	if was_surface != is_surface {
		if is_surface {
			data.surface += 1
		} else {
			data.surface -= 1
		}
	}

	terrain_note_change(service, x, y, z, occ, wat, material)
	return true
}

terrain_set_cell :: proc(
	service: ^Terrain,
	x, y, z: int,
	occupancy, water: f32,
	material: enums.Material,
) {
	if terrain_store_cell(service, x, y, z, occupancy, water, material) {
		terrain_mark_voxel_dirty(service, x, y, z)
	}
}


Terrain_Get_Cell :: proc(service: ^Terrain, x, y, z: int) -> (Terrain_Cell, bool) {
	return terrain_get_cell(service, x, y, z)
}


Terrain_Cell_Count :: proc(service: ^Terrain) -> int {
	if service == nil {
		return 0
	}
	total := 0
	for _, chunk in service.chunks {
		if chunk != nil && chunk.data != nil {
			total += chunk.data.present
		}
	}
	return total
}


Terrain_Chunk_Count :: proc(service: ^Terrain) -> int {
	if service == nil {
		return 0
	}
	return len(service.chunks)
}


Terrain_Draw_Item_Count :: proc(service: ^Terrain) -> int {
	if service == nil {
		return 0
	}
	return len(service.draw_items)
}


Terrain_Dirty_Queue_Depth :: proc(service: ^Terrain) -> int {
	if service == nil {
		return 0
	}
	return len(service.dirty_queue) - service.dirty_head
}


Terrain_Collect_Cells :: proc(service: ^Terrain) -> [dynamic]Terrain_Cell_Entry {
	entries := make([dynamic]Terrain_Cell_Entry)
	if service == nil {
		return entries
	}
	for key, chunk in service.chunks {
		if chunk == nil || chunk.data == nil {
			continue
		}
		data := chunk.data
		base_x := key.x * TERRAIN_CHUNK_SIZE
		base_y := key.y * TERRAIN_CHUNK_SIZE
		base_z := key.z * TERRAIN_CHUNK_SIZE
		for lx in 0 ..< TERRAIN_CHUNK_SIZE {
			for ly in 0 ..< TERRAIN_CHUNK_SIZE {
				for lz in 0 ..< TERRAIN_CHUNK_SIZE {
					index := (lx * TERRAIN_CHUNK_SIZE + ly) * TERRAIN_CHUNK_SIZE + lz
					occ := data.occupancy[index]
					wat := data.water[index]
					if occ <= 0 && wat <= 0 {
						continue
					}
					append(
						&entries,
						Terrain_Cell_Entry {
							x = base_x + lx,
							y = base_y + ly,
							z = base_z + lz,
							cell = Terrain_Cell {
								occupancy = occ,
								water = wat,
								material = data.material[index],
							},
						},
					)
				}
			}
		}
	}
	return entries
}


terrain_note_change :: proc(
	service: ^Terrain,
	x, y, z: int,
	occupancy, water: f32,
	material: enums.Material,
) {
	if !service.dirty_tracking {return}
	service.change_serial += 1
	service.replication_dirty[Terrain_Voxel_Key{x, y, z}] = Terrain_Dirty_Cell {
		record = Terrain_Cell_Record {
			x = i32(x),
			y = i32(y),
			z = i32(z),
			occupancy = occupancy,
			water = water,
			material = material,
		},
		serial = service.change_serial,
	}
	if len(service.replication_dirty) > TERRAIN_DIRTY_LIMIT {
		service.dirty_epoch += 1
		clear(&service.replication_dirty)
	}
}

terrain_set_water :: proc(service: ^Terrain, x, y, z: int, water: f32) {
	occurred, ok := terrain_get_cell(service, x, y, z)
	material := enums.Material.Water
	if ok {
		material = occurred.material
	}
	occupied := f32(0)
	if ok {
		occupied = occurred.occupancy
	}
	if occupied <= 0 {
		material = enums.Material.Water
	}
	terrain_set_cell(service, x, y, z, occupied, water, material)
}


terrain_cache_occ :: proc(c: ^Terrain_Density_Cache, x, y, z: int) -> f32 {
	lx, ly, lz := x - c.ox, y - c.oy, z - c.oz
	if lx < 0 ||
	   ly < 0 ||
	   lz < 0 ||
	   lx >= TERRAIN_CACHE_DIM ||
	   ly >= TERRAIN_CACHE_DIM ||
	   lz >= TERRAIN_CACHE_DIM {
		return 0
	}
	return c.data[(lx * TERRAIN_CACHE_DIM + ly) * TERRAIN_CACHE_DIM + lz]
}


terrain_cache_neighborhood_has_solids :: proc(service: ^Terrain, key: Terrain_Chunk_Key) -> bool {
	for dx in -1 ..= 1 {
		for dy in -1 ..= 1 {
			for dz in -1 ..= 1 {
				k := Terrain_Chunk_Key{key.x + dx, key.y + dy, key.z + dz}
				if chunk, ok := service.chunks[k]; ok && chunk != nil {
					if chunk.data != nil && chunk.data.solid > 0 {
						return true
					}
				}
			}
		}
	}
	return false
}

terrain_fill_cache :: proc(
	service: ^Terrain,
	c: ^Terrain_Density_Cache,
	key: Terrain_Chunk_Key,
) -> bool {
	c.ox = key.x * TERRAIN_CHUNK_SIZE - TERRAIN_CACHE_PAD
	c.oy = key.y * TERRAIN_CHUNK_SIZE - TERRAIN_CACHE_PAD
	c.oz = key.z * TERRAIN_CHUNK_SIZE - TERRAIN_CACHE_PAD


	if !terrain_cache_neighborhood_has_solids(service, key) {
		return false
	}

	lo, hi := f32(1), f32(0)


	cur_key: Terrain_Chunk_Key
	cur_data: ^Terrain_Chunk_Data
	have_chunk := false
	for x in 0 ..< TERRAIN_CACHE_DIM {
		wx := c.ox + x
		kx := terrain_floor_div(wx, TERRAIN_CHUNK_SIZE)
		lx := wx - kx * TERRAIN_CHUNK_SIZE
		for y in 0 ..< TERRAIN_CACHE_DIM {
			wy := c.oy + y
			ky := terrain_floor_div(wy, TERRAIN_CHUNK_SIZE)
			ly := wy - ky * TERRAIN_CHUNK_SIZE
			for z in 0 ..< TERRAIN_CACHE_DIM {
				wz := c.oz + z
				kz := terrain_floor_div(wz, TERRAIN_CHUNK_SIZE)
				k := Terrain_Chunk_Key{kx, ky, kz}
				if !have_chunk || k != cur_key {
					if chunk, ok := service.chunks[k]; ok {
						cur_data = chunk.data
					} else {
						cur_data = nil
					}
					cur_key = k
					have_chunk = true
				}

				v: f32
				if cur_data != nil {
					lz := wz - kz * TERRAIN_CHUNK_SIZE
					idx := (lx * TERRAIN_CHUNK_SIZE + ly) * TERRAIN_CHUNK_SIZE + lz
					if !terrain_material_is_liquid(cur_data.material[idx]) {
						v = cur_data.occupancy[idx]
					}
				}
				c.data[(x * TERRAIN_CACHE_DIM + y) * TERRAIN_CACHE_DIM + z] = v
				lo = min(lo, v)
				hi = max(hi, v)
			}
		}
	}
	return hi >= service.iso_level && lo < service.iso_level
}

terrain_sample_occupancy :: proc(
	service: ^Terrain,
	voxel_position: datatypes.Vector3,
	cache: ^Terrain_Density_Cache = nil,
) -> f32 {
	x0 := int(math.floor(voxel_position.x))
	y0 := int(math.floor(voxel_position.y))
	z0 := int(math.floor(voxel_position.z))

	fx := voxel_position.x - f32(x0)
	fy := voxel_position.y - f32(y0)
	fz := voxel_position.z - f32(z0)

	result: f32
	for dx in 0 ..< 2 {
		wx := dx == 0 ? 1 - fx : fx
		for dy in 0 ..< 2 {
			wy := dy == 0 ? 1 - fy : fy
			for dz in 0 ..< 2 {
				wz := dz == 0 ? 1 - fz : fz
				o :=
					cache != nil ? terrain_cache_occ(cache, x0 + dx, y0 + dy, z0 + dz) : terrain_occupancy(service, x0 + dx, y0 + dy, z0 + dz)
				result += o * wx * wy * wz
			}
		}
	}
	return result
}

terrain_normal_at_world :: proc(
	service: ^Terrain,
	world: datatypes.Vector3,
	cache: ^Terrain_Density_Cache,
) -> datatypes.Vector3 {
	inv_voxel := 1.0 / service.voxel_size
	p := datatypes.Vector3{world.x * inv_voxel, world.y * inv_voxel, world.z * inv_voxel}
	eps: f32 = 0.5

	dx :=
		terrain_sample_occupancy(service, {p.x - eps, p.y, p.z}, cache) -
		terrain_sample_occupancy(service, {p.x + eps, p.y, p.z}, cache)
	dy :=
		terrain_sample_occupancy(service, {p.x, p.y - eps, p.z}, cache) -
		terrain_sample_occupancy(service, {p.x, p.y + eps, p.z}, cache)
	dz :=
		terrain_sample_occupancy(service, {p.x, p.y, p.z - eps}, cache) -
		terrain_sample_occupancy(service, {p.x, p.y, p.z + eps}, cache)

	n := datatypes.Vector3{dx, dy, dz}
	length := datatypes.Vec3_Magnitude(n)
	if length < 1.0e-6 {
		return datatypes.Vector3_YAxis
	}
	return datatypes.Vec3_Divide(n, length)
}

terrain_material_weights_at_world :: proc(service: ^Terrain, world: datatypes.Vector3) -> [8]f32 {
	inv_voxel := 1.0 / service.voxel_size
	vx := world.x * inv_voxel
	vy := world.y * inv_voxel
	vz := world.z * inv_voxel

	x0 := int(math.floor(vx))
	y0 := int(math.floor(vy))
	z0 := int(math.floor(vz))
	fx := vx - f32(x0)
	fy := vy - f32(y0)
	fz := vz - f32(z0)

	weights: [8]f32
	total: f32

	for dx in 0 ..< 2 {
		wx := dx == 0 ? 1 - fx : fx
		for dy in 0 ..< 2 {
			wy := dy == 0 ? 1 - fy : fy
			for dz in 0 ..< 2 {
				wz := dz == 0 ? 1 - fz : fz
				if cell, ok := terrain_get_cell(service, x0 + dx, y0 + dy, z0 + dz);
				   ok && cell.occupancy > 0 && !terrain_material_is_liquid(cell.material) {
					weight := wx * wy * wz * cell.occupancy
					weights[terrain_material_layer(cell.material)] += weight
					total += weight
				}
			}
		}
	}

	if total <= 1.0e-6 {
		weights[0] = 1
		return weights
	}
	for i in 0 ..< 6 {
		weights[i] /= total
	}
	return weights
}


Terrain_Edge_Key :: struct {
	x, y, z: i32,
	axis:    u8,
}

Terrain_Mesh_Builder :: struct {
	service:          ^Terrain,
	vertex_data:      ^[dynamic]f32,
	material_weights: ^[dynamic]f32,
	indices:          ^[dynamic]u16,
	cache:            ^Terrain_Density_Cache,
	edge_vertices:    map[Terrain_Edge_Key]u32,
	vertex_count:     u32,
	cell_x:           int,
	cell_y:           int,
	cell_z:           int,
}

terrain_append_vertex :: proc(
	service: ^Terrain,
	vertex_data: ^[dynamic]f32,
	material_weights: ^[dynamic]f32,
	position, normal: datatypes.Vector3,
) {
	append(vertex_data, position.x, position.y, position.z, normal.x, normal.y, normal.z, 0, 0)


	if material_weights != nil {
		weights := terrain_material_weights_at_world(service, position)
		for weight in weights {
			append(material_weights, weight)
		}
	}
}


terrain_edge_key_for_cube_edge :: proc(
	builder: ^Terrain_Mesh_Builder,
	edge: int,
) -> Terrain_Edge_Key {
	o0 := marching_cubes.MC_Corner_Offsets[marching_cubes.MC_Edge_Corners[edge][0]]
	o1 := marching_cubes.MC_Corner_Offsets[marching_cubes.MC_Edge_Corners[edge][1]]
	ax := builder.cell_x + int(o0.x)
	ay := builder.cell_y + int(o0.y)
	az := builder.cell_z + int(o0.z)
	bx := builder.cell_x + int(o1.x)
	by := builder.cell_y + int(o1.y)
	bz := builder.cell_z + int(o1.z)


	if bx < ax || (bx == ax && (by < ay || (by == ay && bz < az))) {
		ax, bx = bx, ax
		ay, by = by, ay
		az, bz = bz, az
	}

	axis: u8
	switch {
	case bx != ax:
		axis = 0
	case by != ay:
		axis = 1
	case:
		axis = 2
	}
	return Terrain_Edge_Key{x = i32(ax), y = i32(ay), z = i32(az), axis = axis}
}


terrain_edge_vertex :: proc(builder: ^Terrain_Mesh_Builder, key: Terrain_Edge_Key) -> u32 {
	if index, ok := builder.edge_vertices[key]; ok {
		return index
	}

	service := builder.service
	vs := service.voxel_size

	ax, ay, az := int(key.x), int(key.y), int(key.z)
	bx, by, bz := ax, ay, az
	switch key.axis {
	case 1:
		by += 1
	case 2:
		bz += 1
	case:
		bx += 1
	}

	pa := datatypes.Vector3{f32(ax) * vs, f32(ay) * vs, f32(az) * vs}
	pb := datatypes.Vector3{f32(bx) * vs, f32(by) * vs, f32(bz) * vs}

	d0 := terrain_cache_occ(builder.cache, ax, ay, az)
	d1 := terrain_cache_occ(builder.cache, bx, by, bz)
	t: f32 = 0.5
	denom := d1 - d0
	if math.abs(denom) > 1.0e-6 {
		t = clamp((service.iso_level - d0) / denom, 0, 1)
	}
	position := datatypes.Vector3 {
		pa.x + (pb.x - pa.x) * t,
		pa.y + (pb.y - pa.y) * t,
		pa.z + (pb.z - pa.z) * t,
	}

	normal := terrain_normal_at_world(service, position, builder.cache)

	index := builder.vertex_count
	terrain_append_vertex(service, builder.vertex_data, builder.material_weights, position, normal)
	builder.vertex_count += 1
	builder.edge_vertices[key] = index
	return index
}

terrain_vertex_position :: proc(builder: ^Terrain_Mesh_Builder, index: u32) -> datatypes.Vector3 {
	base := int(index) * 8
	data := builder.vertex_data
	return datatypes.Vector3{data[base], data[base + 1], data[base + 2]}
}

terrain_vertex_normal :: proc(builder: ^Terrain_Mesh_Builder, index: u32) -> datatypes.Vector3 {
	base := int(index) * 8
	data := builder.vertex_data
	return datatypes.Vector3{data[base + 3], data[base + 4], data[base + 5]}
}

terrain_mc_emit :: proc(p0, p1, p2: marching_cubes.Vec3, e0, e1, e2: int, user_data: rawptr) {
	builder := cast(^Terrain_Mesh_Builder)user_data
	if builder == nil || builder.service == nil {
		return
	}

	i0 := terrain_edge_vertex(builder, terrain_edge_key_for_cube_edge(builder, e0))
	i1 := terrain_edge_vertex(builder, terrain_edge_key_for_cube_edge(builder, e1))
	i2 := terrain_edge_vertex(builder, terrain_edge_key_for_cube_edge(builder, e2))


	v0 := terrain_vertex_position(builder, i0)
	v1 := terrain_vertex_position(builder, i1)
	v2 := terrain_vertex_position(builder, i2)
	n0 := terrain_vertex_normal(builder, i0)
	n1 := terrain_vertex_normal(builder, i1)
	n2 := terrain_vertex_normal(builder, i2)

	face := datatypes.Vec3_Cross(datatypes.Vec3_Subtract(v1, v0), datatypes.Vec3_Subtract(v2, v0))
	avg_normal := datatypes.Vec3_Add(datatypes.Vec3_Add(n0, n1), n2)
	if datatypes.Vec3_Dot(face, avg_normal) < 0 {
		append(builder.indices, u16(i0), u16(i2), u16(i1))
	} else {
		append(builder.indices, u16(i0), u16(i1), u16(i2))
	}
}

terrain_march_cell :: proc(service: ^Terrain, x, y, z: int, builder: ^Terrain_Mesh_Builder) {
	vs := service.voxel_size
	cell: marching_cubes.MC_Cell

	for i in 0 ..< 8 {
		offset := marching_cubes.MC_Corner_Offsets[i]
		ox, oy, oz := int(offset.x), int(offset.y), int(offset.z)
		cell.positions[i] = marching_cubes.Vec3 {
			f32(x + ox) * vs,
			f32(y + oy) * vs,
			f32(z + oz) * vs,
		}
		cell.densities[i] = terrain_cache_occ(builder.cache, x + ox, y + oy, z + oz)
	}

	builder.cell_x = x
	builder.cell_y = y
	builder.cell_z = z
	_ = marching_cubes.MC_March_Cube_Edges(&cell, service.iso_level, terrain_mc_emit, builder)
}


terrain_destroy_chunk_meshes :: proc(chunk: ^Terrain_Chunk, renderer: ^classes.Renderer_Object) {
	if chunk == nil {
		return
	}
	if renderer != nil && renderer.Filament != nil {
		for mesh in chunk.meshes {
			if mesh != nil {
				_ = kineffi.Kine_Filament_DestroyMesh(renderer.Filament, mesh)
			}
		}
	}
	delete(chunk.meshes)
	chunk.meshes = nil
}

terrain_upload_chunk_meshes :: proc(
	chunk: ^Terrain_Chunk,
	renderer: ^classes.Renderer_Object,
	vertex_data: []f32,
	material_weights: []f32,
	indices: []u16,
) {
	vertex_count := len(vertex_data) / 8
	index_count := len(indices)
	if vertex_count == 0 || index_count == 0 || renderer == nil || renderer.Filament == nil {
		return
	}

	chunk.meshes = make([dynamic]^kineffi.KineFilamentMesh)


	if vertex_count > TERRAIN_MAX_VERTICES_PER_MESH {
		return
	}

	mesh := kineffi.Kine_Filament_CreateTerrainMesh(
		renderer.Filament,
		cast(^f32)raw_data(vertex_data),
		cast(^f32)raw_data(material_weights),
		i32(vertex_count),
		cast(^u16)raw_data(indices),
		i32(index_count),
	)
	if mesh != nil {
		append(&chunk.meshes, mesh)
	}
}


Terrain_Build_Chunk_Mesh :: proc(
	service: ^Terrain,
	key: Terrain_Chunk_Key,
	vertex_data: ^[dynamic]f32,
	material_weights: ^[dynamic]f32,
	indices: ^[dynamic]u16,
) -> bool {
	if service == nil {
		return false
	}

	start_index := len(indices)

	builder := Terrain_Mesh_Builder {
		service          = service,
		vertex_data      = vertex_data,
		material_weights = material_weights,
		indices          = indices,
	}
	defer delete(builder.edge_vertices)

	cache: Terrain_Density_Cache
	if !terrain_fill_cache(service, &cache, key) {
		return false
	}
	builder.cache = &cache

	x0 := key.x * TERRAIN_CHUNK_SIZE
	y0 := key.y * TERRAIN_CHUNK_SIZE
	z0 := key.z * TERRAIN_CHUNK_SIZE

	for x in x0 ..< x0 + TERRAIN_CHUNK_SIZE {
		for y in y0 ..< y0 + TERRAIN_CHUNK_SIZE {
			for z in z0 ..< z0 + TERRAIN_CHUNK_SIZE {
				terrain_march_cell(service, x, y, z, &builder)
			}
		}
	}

	if len(indices) == start_index {
		return false
	}
	return true
}


Terrain_Build_Chunk_Mesh_GPU :: proc(
	service: ^Terrain,
	key: Terrain_Chunk_Key,
	compositor: ^kineffi.KineVulkanCompositor,
	vertex_data: ^[dynamic]f32,
	material_weights: ^[dynamic]f32,
	indices: ^[dynamic]u16,
) -> (
	meshed: bool,
	gpu_ok: bool,
) {
	if service == nil || compositor == nil {
		return false, false
	}

	cache: Terrain_Density_Cache
	if !terrain_fill_cache(service, &cache, key) {
		return false, true
	}

	cells := TERRAIN_CACHE_DIM * TERRAIN_CACHE_DIM * TERRAIN_CACHE_DIM
	occ := &service.gpu_occ
	mat := &service.gpu_mat
	verts := &service.gpu_verts
	weights := &service.gpu_weights
	out := &service.gpu_indices
	if len(occ) != cells {
		_ = resize(occ, cells)
		_ = resize(mat, cells)
		_ = resize(verts, TERRAIN_GPU_MAX_VERTICES * 8)
		_ = resize(weights, TERRAIN_GPU_MAX_VERTICES * 8)
		_ = resize(out, TERRAIN_GPU_MAX_INDICES)
	}


	for x in 0 ..< TERRAIN_CACHE_DIM {
		wx := cache.ox + x
		for y in 0 ..< TERRAIN_CACHE_DIM {
			wy := cache.oy + y
			for z in 0 ..< TERRAIN_CACHE_DIM {
				idx := (x * TERRAIN_CACHE_DIM + y) * TERRAIN_CACHE_DIM + z
				occ[idx] = cache.data[idx]
				layer: u32
				if cell, ok := terrain_get_cell(service, wx, wy, cache.oz + z); ok {
					layer = u32(terrain_material_layer(cell.material))
				}
				mat[idx] = layer
			}
		}
	}

	vertex_count, index_count: u32
	ok := kineffi.Kine_VulkanCompositor_MeshTerrainChunk(
		compositor,
		raw_data(occ[:]),
		raw_data(mat[:]),
		i32(key.x * TERRAIN_CHUNK_SIZE),
		i32(key.y * TERRAIN_CHUNK_SIZE),
		i32(key.z * TERRAIN_CHUNK_SIZE),
		service.voxel_size,
		service.iso_level,
		raw_data(verts[:]),
		raw_data(weights[:]),
		raw_data(out[:]),
		TERRAIN_GPU_MAX_VERTICES,
		TERRAIN_GPU_MAX_INDICES,
		&vertex_count,
		&index_count,
	)
	if ok == 0 {
		return false, false
	}
	if vertex_count == 0 || index_count == 0 {
		return false, true
	}

	append(vertex_data, ..verts[:int(vertex_count) * 8])
	append(material_weights, ..weights[:int(vertex_count) * 8])
	for i in 0 ..< int(index_count) {
		append(indices, u16(out[i]))
	}
	return true, true
}


Terrain_Mesh_Job :: struct {
	service:          ^Terrain,
	key:              Terrain_Chunk_Key,
	has_surface:      bool,
	vertex_data:      [dynamic]f32,
	material_weights: [dynamic]f32,
	indices:          [dynamic]u16,
}

terrain_mesh_job_run :: proc(t: ^thread.Thread) {
	job := cast(^Terrain_Mesh_Job)t.data
	if job == nil {
		return
	}
	job.has_surface = Terrain_Build_Chunk_Mesh(
		job.service,
		job.key,
		&job.vertex_data,
		&job.material_weights,
		&job.indices,
	)
}


terrain_build_jobs_parallel :: proc(jobs: []Terrain_Mesh_Job) {
	if len(jobs) == 0 {
		return
	}

	if len(jobs) == 1 {
		terrain_build_job(jobs[0].service, &jobs[0])
		return
	}

	threads: [TERRAIN_REBUILDS_PER_FRAME]^thread.Thread
	started := 0
	for &job in jobs {
		t := thread.create(terrain_mesh_job_run)
		if t == nil {


			terrain_build_job(job.service, &job)
			continue
		}
		t.data = &job
		thread.start(t)
		threads[started] = t
		started += 1
	}

	for i in 0 ..< started {
		thread.join(threads[i])
		thread.destroy(threads[i])
	}
}

terrain_build_job :: proc(service: ^Terrain, job: ^Terrain_Mesh_Job) {
	job.has_surface = Terrain_Build_Chunk_Mesh(
		service,
		job.key,
		&job.vertex_data,
		&job.material_weights,
		&job.indices,
	)
}


terrain_commit_job :: proc(
	service: ^Terrain,
	job: ^Terrain_Mesh_Job,
	renderer: ^classes.Renderer_Object,
) {
	if chunk, ok := service.chunks[job.key]; ok && chunk != nil {
		terrain_destroy_chunk_meshes(chunk, renderer)
		if job.has_surface {
			terrain_upload_chunk_meshes(
				chunk,
				renderer,
				job.vertex_data[:],
				job.material_weights[:],
				job.indices[:],
			)
		}
		chunk.dirty = false
	}
	service.draw_dirty = true

	delete(job.vertex_data)
	delete(job.material_weights)
	delete(job.indices)
	job.vertex_data = nil
	job.material_weights = nil
	job.indices = nil
}


terrain_ensure_texture_set :: proc(service: ^Terrain, renderer: ^classes.Renderer_Object) {
	if service == nil || renderer == nil || renderer.Filament == nil {
		return
	}
	if service.texture_set != nil && service.texture_context == renderer.Filament {
		return
	}

	if service.texture_set != nil && service.texture_context != nil {
		_ = kineffi.Kine_Filament_DestroyTex(service.texture_context, service.texture_set)
		service.texture_set = nil
	}

	materials.init(renderer)
	grass := materials.Get(enums.Material.Grass)
	sand := materials.Get(enums.Material.Sand)
	slate := materials.Get(enums.Material.Slate)
	concrete := materials.Get(enums.Material.Concrete)
	smooth := materials.Get(enums.Material.SmoothPlastic)
	wood := materials.Get(enums.Material.Wood)

	service.texture_set = kineffi.Kine_Filament_CreateTerrainTextureSet(
		renderer.Filament,
		grass.texture,
		sand.texture,
		slate.texture,
		concrete.texture,
		smooth.texture,
		wood.texture,
	)
	service.texture_context = renderer.Filament
	service.draw_dirty = true
}


terrain_destroy_surface_mesh :: proc(service: ^Terrain) {
	if service == nil {
		return
	}
	if service.surface_mesh != nil && service.renderer != nil && service.renderer.Filament != nil {
		_ = kineffi.Kine_Filament_DestroyMesh(service.renderer.Filament, service.surface_mesh)
	}
	service.surface_mesh = nil
}


terrain_append_surface_item :: proc(
	service: ^Terrain,
	data: ^Terrain_Chunk_Data,
	lx, ly, lz: int,
	x, y, z: int,
	water, occ: f32,
	material: enums.Material,
) {


	above_water, above_occ := f32(0), f32(0)
	if ly + 1 < TERRAIN_CHUNK_SIZE {
		above_index := (lx * TERRAIN_CHUNK_SIZE + ly + 1) * TERRAIN_CHUNK_SIZE + lz
		above_water = data.water[above_index]
		above_occ = data.occupancy[above_index]
	} else if above, has_above := terrain_get_cell(service, x, y + 1, z); has_above {
		above_water = above.water
		above_occ = above.occupancy
	}
	if above_water > 0 || above_occ > 0 {
		return
	}

	vs := service.voxel_size
	level := max(water, occ)
	if level <= 0 {
		return
	}
	surface_y := (f32(y) + level - 0.5) * vs

	kind := terrain_material_surface_kind(material)
	color := terrain_material_color(service, material)
	transmission := clamp(1.0 - service.water_transparency, 0.2, 1.0)
	param1: f32 = 0.08
	param2: f32 = 1.33
	param3: f32 = 0.5

	#partial switch enums.Material(material) {
	case .Glass:
		transmission = 0.85
		param1 = 0.05
		param2 = 1.52
		param3 = 0.35
	case .Neon:
		transmission = 0
		param1 = 1.0
	case:
		surface_y -= 0.35
	}


	translate := [16]f32 {
		vs,
		0,
		0,
		0,
		0,
		1,
		0,
		0,
		0,
		0,
		vs,
		0,
		(f32(x) + 0.5) * vs,
		surface_y,
		(f32(z) + 0.5) * vs,
		1,
	}

	append(
		&service.draw_items,
		kineffi.KineFilamentDrawItem {
			mesh = service.surface_mesh,
			tex = nil,
			transform = translate,
			r = color.R,
			g = color.G,
			b = color.B,
			param1 = param1,
			param2 = param2,
			param3 = param3,
			transmission = transmission,
			materialKind = kind,
			flags = u32(kineffi.KINE_FILAMENT_DRAW_CULLING),
		},
	)
}

terrain_append_surface_draw_items :: proc(service: ^Terrain) {
	if service.renderer == nil || service.renderer.Filament == nil {
		return
	}

	if service.surface_mesh == nil {
		service.surface_mesh = kineffi.Kine_Filament_CreateMesh(
			service.renderer.Filament,
			kineffi.KINE_MESH_WATER_GRID,
		)
		if service.surface_mesh == nil {
			return
		}
	}


	for key, chunk in service.chunks {
		if chunk == nil || chunk.data == nil || chunk.data.surface == 0 {
			continue
		}
		data := chunk.data
		base_x := key.x * TERRAIN_CHUNK_SIZE
		base_y := key.y * TERRAIN_CHUNK_SIZE
		base_z := key.z * TERRAIN_CHUNK_SIZE
		for lx in 0 ..< TERRAIN_CHUNK_SIZE {
			for ly in 0 ..< TERRAIN_CHUNK_SIZE {
				for lz in 0 ..< TERRAIN_CHUNK_SIZE {
					index := (lx * TERRAIN_CHUNK_SIZE + ly) * TERRAIN_CHUNK_SIZE + lz
					water := data.water[index]
					occ := data.occupancy[index]
					material := data.material[index]
					if !terrain_cell_has_surface(water, material) {
						continue
					}
					terrain_append_surface_item(
						service,
						data,
						lx,
						ly,
						lz,
						base_x + lx,
						base_y + ly,
						base_z + lz,
						water,
						occ,
						material,
					)
				}
			}
		}
	}
}

terrain_refresh_draw_items :: proc(service: ^Terrain) {
	delete(service.draw_items)
	service.draw_items = make([dynamic]kineffi.KineFilamentDrawItem, 0, 64)

	identity := [16]f32{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}

	terrain_append_surface_draw_items(service)

	for _, chunk in service.chunks {
		if chunk == nil {
			continue
		}
		for mesh in chunk.meshes {
			if mesh == nil {
				continue
			}
			append(
				&service.draw_items,
				kineffi.KineFilamentDrawItem {
					mesh = mesh,
					tex = service.texture_set,
					transform = identity,
					r = 1,
					g = 1,
					b = 1,
					param1 = 0.9,
					param2 = 0,
					param3 = 0.25,
					transmission = 0,
					materialKind = kineffi.KINE_MAT_TERRAIN,
					flags = u32(
						kineffi.KINE_FILAMENT_DRAW_CAST_SHADOWS |
						kineffi.KINE_FILAMENT_DRAW_RECEIVE_SHADOWS |
						kineffi.KINE_FILAMENT_DRAW_CULLING,
					),
				},
			)
		}
	}

	service.draw_version += 1
	service.draw_dirty = false
}

terrain_reset_queue :: proc(service: ^Terrain) {
	service.dirty_head = 0
	clear(&service.dirty_queue)
	clear(&service.dirty_lookup)
}

Terrain_Prepare_3D :: proc(service: ^Terrain, renderer: ^classes.Renderer_Object) {
	if service == nil || renderer == nil || renderer.Filament == nil {
		return
	}
	if service.preparing {
		return
	}
	service.preparing = true
	defer service.preparing = false

	service.renderer = renderer
	terrain_ensure_texture_set(service, renderer)


	jobs: [TERRAIN_REBUILDS_PER_FRAME]Terrain_Mesh_Job
	job_count := 0
	queue_len := len(service.dirty_queue)
	for service.dirty_head < queue_len && job_count < TERRAIN_REBUILDS_PER_FRAME {
		key := service.dirty_queue[service.dirty_head]
		service.dirty_head += 1
		delete_key(&service.dirty_lookup, key)

		if chunk, ok := service.chunks[key]; ok && chunk != nil && chunk.dirty {
			jobs[job_count] = Terrain_Mesh_Job {
				service = service,
				key     = key,
			}
			job_count += 1
		}
	}

	if job_count > 0 {


		if TERRAIN_GPU_MESHING && renderer.Compositor != nil {
			for i in 0 ..< job_count {
				job := &jobs[i]
				meshed, gpu_ok := Terrain_Build_Chunk_Mesh_GPU(
					service,
					job.key,
					renderer.Compositor,
					&job.vertex_data,
					&job.material_weights,
					&job.indices,
				)
				if gpu_ok {
					job.has_surface = meshed
				} else {
					job.has_surface = Terrain_Build_Chunk_Mesh(
						service,
						job.key,
						&job.vertex_data,
						&job.material_weights,
						&job.indices,
					)
				}
			}
		} else {
			terrain_build_jobs_parallel(jobs[:job_count])
		}
		for i in 0 ..< job_count {
			terrain_commit_job(service, &jobs[i], renderer)
		}
	}

	if service.dirty_head >= len(service.dirty_queue) {
		terrain_reset_queue(service)
	}
}

Terrain_Render_3D :: proc(service: ^Terrain, renderer: ^classes.Renderer_Object) {
	if service == nil || renderer == nil || renderer.Filament == nil {
		return
	}
	if service.draw_dirty {
		terrain_refresh_draw_items(service)
	}
	if len(service.draw_items) == 0 {
		return
	}
	shader, revision := classes.MaterialVariant_Resolve(
		service.signal_registry,
		service.material_variant,
		renderer.Filament,
	)
	changed := revision != service.shader_revision
	for &item in service.draw_items {
		if item.shader != shader {changed = true}
		item.shader = shader
	}
	if changed {service.draw_version += 1}
	service.shader_revision = revision

	_ = kineffi.Kine_Filament_DrawMeshListVersioned(
		renderer.Filament,
		raw_data(service.draw_items),
		u32(len(service.draw_items)),
		TERRAIN_STREAM_ID,
		service.draw_version,
	)
}


terrain_cell_from_world :: proc(
	service: ^Terrain,
	position: datatypes.Vector3,
) -> (
	int,
	int,
	int,
) {
	inv := 1.0 / service.voxel_size
	return int(
		math.floor(position.x * inv),
	), int(math.floor(position.y * inv)), int(math.floor(position.z * inv))
}

terrain_cell_center_world :: proc(service: ^Terrain, x, y, z: int) -> datatypes.Vector3 {
	return datatypes.Vector3 {
		(f32(x) + 0.5) * service.voxel_size,
		(f32(y) + 0.5) * service.voxel_size,
		(f32(z) + 0.5) * service.voxel_size,
	}
}

terrain_region_cells :: proc(
	region: datatypes.Region3,
	resolution: f32,
) -> (
	Terrain_Region_Cells,
	bool,
) {
	if resolution <= 0 || resolution != resolution {
		return {}, false
	}
	expanded, ok := datatypes.Region3_ExpandToGrid(region, resolution)
	if !ok {
		return {}, false
	}
	size := datatypes.Region3_Size(expanded)
	return Terrain_Region_Cells {
			origin = expanded.Min,
			resolution = resolution,
			count_x = max(0, int(math.round(size.x / resolution))),
			count_y = max(0, int(math.round(size.y / resolution))),
			count_z = max(0, int(math.round(size.z / resolution))),
		},
		true
}

terrain_region_cell_center :: proc(
	cells: Terrain_Region_Cells,
	x, y, z: int,
) -> datatypes.Vector3 {
	return datatypes.Vector3 {
		cells.origin.x + (f32(x) + 0.5) * cells.resolution,
		cells.origin.y + (f32(y) + 0.5) * cells.resolution,
		cells.origin.z + (f32(z) + 0.5) * cells.resolution,
	}
}

terrain_write_cell_at :: proc(
	service: ^Terrain,
	cells: Terrain_Region_Cells,
	x, y, z: int,
	occupancy: f32,
	water: f32,
	material: enums.Material,
) {
	center := terrain_region_cell_center(cells, x, y, z)
	cx, cy, cz := terrain_cell_from_world(service, center)
	terrain_set_cell(service, cx, cy, cz, occupancy, water, material)
}


terrain_fill_region :: proc(
	service: ^Terrain,
	region: datatypes.Region3,
	resolution: f32,
	material: enums.Material,
) {
	cells, ok := terrain_region_cells(region, resolution)
	if !ok {
		return
	}
	for x in 0 ..< cells.count_x {
		for y in 0 ..< cells.count_y {
			for z in 0 ..< cells.count_z {
				terrain_write_cell_at(service, cells, x, y, z, 1, 0, material)
			}
		}
	}
}

Terrain_Cell_Bounds :: struct {
	min_x, max_x: int,
	min_y, max_y: int,
	min_z, max_z: int,
}

terrain_cell_bounds :: proc(
	service: ^Terrain,
	world_min, world_max: datatypes.Vector3,
) -> Terrain_Cell_Bounds {
	vs := service.voxel_size
	return Terrain_Cell_Bounds {
		min_x = int(math.floor(world_min.x / vs)) - 1,
		max_x = int(math.floor(world_max.x / vs)) + 1,
		min_y = int(math.floor(world_min.y / vs)) - 1,
		max_y = int(math.floor(world_max.y / vs)) + 1,
		min_z = int(math.floor(world_min.z / vs)) - 1,
		max_z = int(math.floor(world_max.z / vs)) + 1,
	}
}

Terrain_SDF_Kind :: enum u8 {
	Sphere,
	Box,
	Cylinder,
	Wedge,
}

Terrain_SDF_Shape :: struct {
	kind:   Terrain_SDF_Kind,
	cframe: datatypes.CFrame,
	center: datatypes.Vector3,
	radius: f32,
	half:   datatypes.Vector3,
}

terrain_sdf_box :: proc(local, half: datatypes.Vector3) -> f32 {
	qx := math.abs(local.x) - half.x
	qy := math.abs(local.y) - half.y
	qz := math.abs(local.z) - half.z
	ox, oy, oz := max(qx, 0), max(qy, 0), max(qz, 0)
	outside := math.sqrt(ox * ox + oy * oy + oz * oz)
	inside := min(max(qx, max(qy, qz)), 0)
	return outside + inside
}

terrain_sdf_eval :: proc(shape: Terrain_SDF_Shape, world: datatypes.Vector3) -> f32 {
	if shape.kind == .Sphere {
		return(
			datatypes.Vec3_Magnitude(datatypes.Vec3_Subtract(world, shape.center)) -
			shape.radius \
		)
	}

	local := datatypes.CFrame_PointToObjectSpace(shape.cframe, world)
	switch shape.kind {
	case .Sphere:
		return 0
	case .Box:
		return terrain_sdf_box(local, shape.half)
	case .Cylinder:
		dx := math.sqrt(local.x * local.x + local.z * local.z) - shape.half.x
		dy := math.abs(local.y) - shape.half.y
		ox, oy := max(dx, 0), max(dy, 0)
		return min(max(dx, dy), 0) + math.sqrt(ox * ox + oy * oy)
	case .Wedge:
		slope := shape.half.y / shape.half.z
		plane :=
			(local.y - shape.half.y + (local.z + shape.half.z) * slope) /
			math.sqrt(1 + slope * slope)
		return max(terrain_sdf_box(local, shape.half), plane)
	}
	return 0
}

terrain_smooth_min :: proc(a, b, k: f32) -> f32 {
	if k <= 0 {
		return min(a, b)
	}
	h := max(k - math.abs(a - b), 0) / k
	return min(a, b) - h * h * k * 0.25
}

terrain_smooth_max :: proc(a, b, k: f32) -> f32 {
	return -terrain_smooth_min(-a, -b, k)
}


terrain_sdf_apply :: proc(
	service: ^Terrain,
	shape: Terrain_SDF_Shape,
	material: enums.Material,
	blend: f32 = 0,
) {
	vs := service.voxel_size
	iso := service.iso_level
	k := max(blend, 0)
	subtract := material == .Air

	bounds := terrain_sdf_bounds(service, shape, int(math.ceil(k / vs)))

	changed := false
	for x in int(bounds.Min.X) ..= int(bounds.Max.X) {
		for y in int(bounds.Min.Y) ..= int(bounds.Max.Y) {
			for z in int(bounds.Min.Z) ..= int(bounds.Max.Z) {
				center := terrain_cell_center_world(service, x, y, z)
				d_shape := terrain_sdf_eval(shape, center)

				if d_shape > vs + k {
					continue
				}

				cell, found := terrain_get_cell(service, x, y, z)
				if subtract && !found {
					continue
				}


				existing_occ := f32(0)
				if found && !terrain_material_is_liquid(cell.material) {
					existing_occ = cell.occupancy
				}
				d_existing := (iso - existing_occ) * vs

				d: f32
				out_material := material
				if subtract {
					d = terrain_smooth_max(d_existing, -d_shape, k)
					out_material = cell.material
				} else {
					d = terrain_smooth_min(d_existing, d_shape, k)
					if found && existing_occ > 0 && d_existing < d_shape {
						out_material = cell.material
					}
				}

				new_occ := clamp(iso - d / vs, 0, 1)


				if k <= 0 {
					if subtract {
						new_occ = d_shape <= 0 ? f32(0) : existing_occ
					} else {
						new_occ = d_shape <= 0 ? f32(1) : existing_occ
					}
				}

				if math.abs(new_occ - existing_occ) < 1.0e-4 &&
				   (!found || out_material == cell.material) {
					continue
				}

				water := f32(0)
				if found {
					water = cell.water
				}


				if terrain_store_cell(service, x, y, z, new_occ, water, out_material) {
					changed = true
				}
			}
		}
	}

	if changed {
		service.geometry_version += 1
		terrain_mark_voxel_region_dirty(
			service,
			int(bounds.Min.X),
			int(bounds.Min.Y),
			int(bounds.Min.Z),
			int(bounds.Max.X),
			int(bounds.Max.Y),
			int(bounds.Max.Z),
		)
	}
}

terrain_fill_ball :: proc(
	service: ^Terrain,
	center: datatypes.Vector3,
	radius: f32,
	material: enums.Material,
) {
	if radius <= 0 {
		return
	}
	terrain_sdf_apply(
		service,
		Terrain_SDF_Shape{kind = .Sphere, center = center, radius = radius},
		material,
	)
}

terrain_fill_box :: proc(
	service: ^Terrain,
	cframe: datatypes.CFrame,
	size: datatypes.Vector3,
	material: enums.Material,
) {
	half := datatypes.Vec3_Multiply(size, 0.5)
	if half.x <= 0 || half.y <= 0 || half.z <= 0 {
		return
	}
	terrain_sdf_apply(
		service,
		Terrain_SDF_Shape{kind = .Box, cframe = cframe, half = half},
		material,
	)
}

terrain_fill_cylinder :: proc(
	service: ^Terrain,
	cframe: datatypes.CFrame,
	height, radius: f32,
	material: enums.Material,
) {
	if height <= 0 || radius <= 0 {
		return
	}
	half := datatypes.Vector3{radius, height * 0.5, radius}
	terrain_sdf_apply(
		service,
		Terrain_SDF_Shape{kind = .Cylinder, cframe = cframe, half = half},
		material,
	)
}

terrain_fill_wedge :: proc(
	service: ^Terrain,
	cframe: datatypes.CFrame,
	size: datatypes.Vector3,
	material: enums.Material,
) {
	half := datatypes.Vec3_Multiply(size, 0.5)
	if half.x <= 0 || half.y <= 0 || half.z <= 0 {
		return
	}
	terrain_sdf_apply(
		service,
		Terrain_SDF_Shape{kind = .Wedge, cframe = cframe, half = half},
		material,
	)
}

terrain_replace_material :: proc(
	service: ^Terrain,
	region: datatypes.Region3,
	resolution: f32,
	source: enums.Material,
	target: enums.Material,
) {
	cells, ok := terrain_region_cells(region, resolution)
	if !ok {
		return
	}
	for x in 0 ..< cells.count_x {
		for y in 0 ..< cells.count_y {
			for z in 0 ..< cells.count_z {
				center := terrain_region_cell_center(cells, x, y, z)
				cx, cy, cz := terrain_cell_from_world(service, center)
				cell, found := terrain_get_cell(service, cx, cy, cz)
				if !found || cell.occupancy <= 0 || cell.material != source {
					continue
				}
				terrain_set_cell(service, cx, cy, cz, cell.occupancy, cell.water, target)
			}
		}
	}
}


terrain_fade :: proc(t: f32) -> f32 {
	return t * t * t * (t * (t * 6 - 15) + 10)
}

terrain_lerp :: proc(a, b, t: f32) -> f32 {
	return a + (b - a) * t
}

terrain_hash :: proc(x, y, z: int, seed: i64) -> f32 {


	h := u32(seed) ~ (u32(x) * 0x8DA6B343) ~ (u32(y) * 0xD8163841) ~ (u32(z) * 0xCB1AB31F)
	h ~= h >> 16
	h *= 0x7FEB352D
	h ~= h >> 15
	h *= 0x846CA68B
	h ~= h >> 16

	return f32(h >> 8) * (1.0 / 16777216.0)
}

terrain_value_noise_3d :: proc(x, y, z: f32, seed: i64) -> f32 {
	ix, iy, iz := int(math.floor(x)), int(math.floor(y)), int(math.floor(z))
	fx, fy, fz := x - f32(ix), y - f32(iy), z - f32(iz)
	ux, uy, uz := terrain_fade(fx), terrain_fade(fy), terrain_fade(fz)

	n000 := terrain_hash(ix, iy, iz, seed)
	n100 := terrain_hash(ix + 1, iy, iz, seed)
	n010 := terrain_hash(ix, iy + 1, iz, seed)
	n110 := terrain_hash(ix + 1, iy + 1, iz, seed)
	n001 := terrain_hash(ix, iy, iz + 1, seed)
	n101 := terrain_hash(ix + 1, iy, iz + 1, seed)
	n011 := terrain_hash(ix, iy + 1, iz + 1, seed)
	n111 := terrain_hash(ix + 1, iy + 1, iz + 1, seed)

	x00 := terrain_lerp(n000, n100, ux)
	x10 := terrain_lerp(n010, n110, ux)
	x01 := terrain_lerp(n001, n101, ux)
	x11 := terrain_lerp(n011, n111, ux)
	y0 := terrain_lerp(x00, x10, uy)
	y1 := terrain_lerp(x01, x11, uy)
	return terrain_lerp(y0, y1, uz)
}

terrain_fbm :: proc(x, y, z: f32, octaves: int, frequency, amplitude: f32, seed: i64) -> f32 {
	value, total: f32
	freq := frequency
	amp := amplitude
	for octave in 0 ..< octaves {
		value +=
			terrain_value_noise_3d(x * freq, y * freq, z * freq, seed + i64(octave) * 7919) * amp
		total += amp
		freq *= 2.1
		amp *= 0.5
	}
	if total <= 1.0e-6 {
		return 0
	}
	return value / total
}

terrain_default_fill_options :: proc() -> Terrain_Fill_Options {
	return Terrain_Fill_Options {
		terrain_type = .Hills,
		caves = true,
		seed = 49297,
		noise_scale = 1,
		roughness = 1,
		cave_density = 1,
		cave_size = 1,
	}
}

terrain_table_number :: proc(L: ^vm.State, table_index: int, key: string, fallback: f64) -> f64 {
	_ = vm.GetField(L, table_index, key)
	defer vm.Pop(L)
	if !vm.IsNumber(L, -1) {
		return fallback
	}
	return vm.ArgNumber(L, -1)
}

terrain_table_bool :: proc(L: ^vm.State, table_index: int, key: string, fallback: bool) -> bool {
	_ = vm.GetField(L, table_index, key)
	defer vm.Pop(L)
	if !vm.IsBoolean(L, -1) {
		return fallback
	}
	return vm.ArgBoolean(L, -1)
}

terrain_table_string :: proc(L: ^vm.State, table_index: int, key: string) -> (string, bool) {
	_ = vm.GetField(L, table_index, key)
	defer vm.Pop(L)
	if !vm.IsString(L, -1) {
		return "", false
	}
	return vm.ArgString(L, -1), true
}

terrain_equal_fold :: proc(a, b: string) -> bool {
	if len(a) != len(b) {
		return false
	}
	for i in 0 ..< len(a) {
		ca, cb := a[i], b[i]
		if ca >= 'A' && ca <= 'Z' {
			ca += 32
		}
		if cb >= 'A' && cb <= 'Z' {
			cb += 32
		}
		if ca != cb {
			return false
		}
	}
	return true
}

terrain_read_fill_options :: proc(
	L: ^vm.State,
	table_index: int,
	enum_registry: ^enums.Registry,
) -> Terrain_Fill_Options {
	options := terrain_default_fill_options()
	if !vm.IsTable(L, table_index) {
		return options
	}

	if terrain_type, ok := terrain_table_string(L, table_index, "terrainType"); ok {
		switch {
		case terrain_equal_fold(terrain_type, "flat"):
			options.terrain_type = .Flat
		case terrain_equal_fold(terrain_type, "mountains"):
			options.terrain_type = .Mountains
		case terrain_equal_fold(terrain_type, "hills"):
			options.terrain_type = .Hills
		}
	} else if terrain_table_bool(L, table_index, "mountains", false) {
		options.terrain_type = .Mountains
	}

	options.caves = terrain_table_bool(L, table_index, "caves", true)
	options.seed = i64(math.floor(terrain_table_number(L, table_index, "seed", 49297)))
	options.noise_scale = clamp(f32(terrain_table_number(L, table_index, "noiseScale", 1)), 0.1, 4)
	options.roughness = clamp(f32(terrain_table_number(L, table_index, "roughness", 1)), 0, 3)
	options.cave_density = clamp(f32(terrain_table_number(L, table_index, "caveDensity", 1)), 0, 4)
	options.cave_size = clamp(f32(terrain_table_number(L, table_index, "caveSize", 1)), 0.25, 3)

	if material, ok := terrain_table_material(L, table_index, enum_registry); ok {
		options.material_override = material
		options.has_material = true
	}

	return options
}

terrain_fill_generated :: proc(
	service: ^Terrain,
	pos_x, pos_y, pos_z, width, height: int,
	options: Terrain_Fill_Options,
) {
	if width < 1 || height < 1 {
		return
	}

	for x in pos_x - width ..= pos_x + width {
		for z in pos_z - width ..= pos_z + width {
			height_offset: f32
			mountain_height: f32

			switch options.terrain_type {
			case .Flat:
			case .Hills:
				n := terrain_fbm(
					f32(x),
					0,
					f32(z),
					4,
					0.035 * options.noise_scale,
					1,
					options.seed,
				)
				height_offset = (n - 0.5) * f32(height) * 0.8 * options.roughness
			case .Mountains:
				base := terrain_fbm(
					f32(x),
					0,
					f32(z),
					5,
					0.03 * options.noise_scale,
					1,
					options.seed,
				)
				ridge1 :=
					1 -
					math.abs(
						terrain_fbm(
							f32(x),
							10,
							f32(z),
							4,
							0.06 * options.noise_scale,
							1,
							options.seed + 17,
						) *
							2 -
						1,
					)
				ridge2 :=
					1 -
					math.abs(
						terrain_fbm(
							f32(x),
							20,
							f32(z),
							3,
							0.12 * options.noise_scale,
							1,
							options.seed + 31,
						) *
							2 -
						1,
					)
				ridge1 *= ridge1
				ridge2 *= ridge2
				mountain_height = (base * 0.4 + ridge1 * 0.4 + ridge2 * 0.2) * options.roughness
				height_offset = mountain_height * f32(height) * 1.4
			}

			surface_y := f32(pos_y + height) + height_offset
			for y in pos_y ..= pos_y + height * 2 + 10 {
				depth := surface_y - f32(y)
				surface_noise: f32
				if options.terrain_type != .Flat && options.roughness > 0 {


					surface_noise =
						(terrain_fbm(
								f32(x),
								0,
								f32(z),
								3,
								0.03 * options.noise_scale,
								1,
								options.seed + 101,
							) -
							0.5) *
						options.roughness
				}


				falloff := clamp(depth / 6, 0, 1)
				falloff = falloff * falloff * (3 - 2 * falloff)
				density := clamp(falloff + surface_noise * 0.25, 0, 1)

				if options.caves && options.cave_density > 0 && density > 0 && depth > 3 {
					cave_frequency := 0.055 * options.noise_scale / options.cave_size
					cave := terrain_fbm(
						f32(x),
						f32(y),
						f32(z),
						3,
						cave_frequency,
						1,
						options.seed + 4049,
					)
					threshold := clamp(0.78 - options.cave_density * 0.07, 0.48, 0.86)
					if cave > threshold {
						carve := clamp((cave - threshold) / 0.12, 0, 1)
						density *= 1 - carve
					}
				}

				if density <= 0 {
					terrain_erase_cell(service, x, y, z)
					continue
				}

				material := enums.Material.Grass
				if options.has_material {
					material = options.material_override
				} else if depth > 12 {
					material = .Concrete
				} else if depth > 4 {
					material = .Slate
				} else if depth > 2 &&
				   options.terrain_type == .Mountains &&
				   height_offset > f32(height) * 0.3 {
					material = .Slate
				}

				terrain_set_cell(service, x, y, z, density, 0, material)
			}
		}
	}
}


terrain_read_3d_value :: proc(L: ^vm.State, table_index, x, y, z: int) -> bool {
	if !vm.IsTable(L, table_index) {
		return false
	}
	_ = vm.RawGetIndex(L, table_index, x + 1)
	if !vm.IsTable(L, -1) {
		return false
	}
	_ = vm.RawGetIndex(L, -1, y + 1)
	if !vm.IsTable(L, -1) {
		return false
	}
	_ = vm.RawGetIndex(L, -1, z + 1)
	return !vm.IsNoneOrNil(L, -1)
}

terrain_push_occupancy_grid :: proc(
	L: ^vm.State,
	service: ^Terrain,
	cells: Terrain_Region_Cells,
	water: bool,
) {
	vm.NewTable(L, cells.count_x)
	for x in 0 ..< cells.count_x {
		vm.NewTable(L, cells.count_y)
		for y in 0 ..< cells.count_y {
			vm.NewTable(L, cells.count_z)
			for z in 0 ..< cells.count_z {
				center := terrain_region_cell_center(cells, x, y, z)
				cx, cy, cz := terrain_cell_from_world(service, center)
				value :=
					water ? terrain_water(service, cx, cy, cz) : terrain_occupancy(service, cx, cy, cz)
				vm.PushNumber(L, f64(value))
				vm.SetArrayValue(L, -2, z + 1)
			}
			vm.SetArrayValue(L, -2, y + 1)
		}
		vm.SetArrayValue(L, -2, x + 1)
	}
}

terrain_push_material_grid :: proc(
	L: ^vm.State,
	service: ^Terrain,
	cells: Terrain_Region_Cells,
	enum_registry: ^enums.Registry,
) {
	vm.NewTable(L, cells.count_x)
	for x in 0 ..< cells.count_x {
		vm.NewTable(L, cells.count_y)
		for y in 0 ..< cells.count_y {
			vm.NewTable(L, cells.count_z)
			for z in 0 ..< cells.count_z {
				center := terrain_region_cell_center(cells, x, y, z)
				cx, cy, cz := terrain_cell_from_world(service, center)
				material := enums.Material.Air
				if cell, ok := terrain_get_cell(service, cx, cy, cz); ok && cell.occupancy > 0 {
					material = cell.material
				}
				if enum_registry == nil ||
				   !enums.Push_Item_By_Value(L, enum_registry, "Material", i64(material)) {
					vm.PushNil(L)
				}
				vm.SetArrayValue(L, -2, z + 1)
			}
			vm.SetArrayValue(L, -2, y + 1)
		}
		vm.SetArrayValue(L, -2, x + 1)
	}
}


terrain_clear :: proc(service: ^Terrain, renderer: ^classes.Renderer_Object) {
	for _, chunk in service.chunks {
		if chunk == nil {
			continue
		}
		terrain_destroy_chunk_meshes(chunk, renderer)
		if chunk.data != nil {
			free(chunk.data)
		}
		free(chunk)
	}

	delete(service.chunks)
	delete(service.draw_items)

	service.chunks = make(map[Terrain_Chunk_Key]^Terrain_Chunk)
	service.draw_items = make([dynamic]kineffi.KineFilamentDrawItem, 0, 64)

	service.dirty_head = 0
	clear(&service.dirty_queue)
	clear(&service.dirty_lookup)

	service.draw_dirty = true
	service.draw_version += 1
	service.geometry_version += 1


	service.change_serial += 1
	service.dirty_epoch += 1
	clear(&service.replication_dirty)
}


Terrain_Write_Kine_Table :: proc(service: ^Terrain, out: ^serializer.Kine_Terrain) {
	if service == nil || out == nil {
		return
	}
	if !(service.voxel_size > 0) {
		return
	}

	out.voxel_size = service.voxel_size
	out.iso_level = service.iso_level
	out.decoration = service.decoration
	out.grass_length = service.grass_length
	out.water_color = service.water_color
	out.water_reflectance = service.water_reflectance
	out.water_transparency = service.water_transparency
	out.water_wave_size = service.water_wave_size
	out.water_wave_speed = service.water_wave_speed
	out.material_variant = strings.clone(service.material_variant)

	for material, colour in service.material_colors {
		if out.material_colours == nil {
			out.material_colours = make(map[u32]datatypes.Color3)
		}
		out.material_colours[u32(material)] = colour
	}


	entries := Terrain_Collect_Cells(service)
	defer delete(entries)
	out.cells = make([dynamic]serializer.Kine_Terrain_Cell, 0, len(entries))
	for entry in entries {
		append(
			&out.cells,
			serializer.Kine_Terrain_Cell {
				x = i32(entry.x),
				y = i32(entry.y),
				z = i32(entry.z),
				material = u32(entry.cell.material),
				occupancy = entry.cell.occupancy,
				water = entry.cell.water,
			},
		)
	}
}


Terrain_Read_Kine_Table :: proc(
	service: ^Terrain,
	renderer: ^classes.Renderer_Object,
	table: ^serializer.Kine_Terrain,
) -> bool {
	if service == nil || table == nil || !(table.voxel_size > 0) || !(table.iso_level > 0) {
		return false
	}


	terrain_clear(service, renderer)

	service.voxel_size = table.voxel_size
	service.iso_level = table.iso_level
	service.decoration = table.decoration
	service.grass_length = table.grass_length
	service.water_color = table.water_color
	service.water_reflectance = table.water_reflectance
	service.water_transparency = table.water_transparency
	service.water_wave_size = table.water_wave_size
	service.water_wave_speed = table.water_wave_speed
	delete(service.material_variant)
	service.material_variant = strings.clone(table.material_variant)

	for material, colour in table.material_colours {
		service.material_colors[enums.Material(material)] = colour
	}

	for cell in table.cells {
		terrain_set_cell(
			service,
			int(cell.x),
			int(cell.y),
			int(cell.z),
			cell.occupancy,
			cell.water,
			enums.Material(cell.material),
		)
	}

	service.draw_dirty = true
	service.draw_version += 1
	return true
}

terrain_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Terrain)
	service.service = Service_Init(&Terrain_Class, "Terrain", data_model)
	service.chunks = make(map[Terrain_Chunk_Key]^Terrain_Chunk)
	service.replication_dirty = make(map[Terrain_Voxel_Key]Terrain_Dirty_Cell)
	service.dirty_lookup = make(map[Terrain_Chunk_Key]bool)
	service.dirty_queue = make([dynamic]Terrain_Chunk_Key, 0, 64)
	service.draw_items = make([dynamic]kineffi.KineFilamentDrawItem, 0, 64)
	service.material_colors = make(map[enums.Material]datatypes.Color3)
	service.voxel_size = TERRAIN_DEFAULT_VOXEL_SIZE
	service.iso_level = TERRAIN_DEFAULT_ISO_LEVEL
	service.grass_length = 0.1
	service.water_color = datatypes.Color3{0.05, 0.29, 0.55}
	service.water_reflectance = 1
	service.water_transparency = 0.3
	service.water_wave_size = 1
	service.water_wave_speed = 10
	service.draw_dirty = true
	service.draw_version = 1
	service.renderer = renderer
	return &service.object
}

terrain_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^Terrain)object
	delete(service.material_variant)
	terrain_clear(service, renderer)

	delete(service.chunks)
	delete(service.dirty_lookup)
	delete(service.dirty_queue)
	delete(service.draw_items)
	delete(service.material_colors)
	delete(service.gpu_occ)
	delete(service.gpu_mat)
	delete(service.gpu_verts)
	delete(service.gpu_weights)
	delete(service.gpu_indices)

	if service.texture_set != nil && service.texture_context != nil {
		_ = kineffi.Kine_Filament_DestroyTex(service.texture_context, service.texture_set)
	}
	service.texture_set = nil
	service.texture_context = nil

	terrain_destroy_surface_mesh(service)

	classes.Object_Destroy(object)
	free(service)
}


terrain_push_material_colors :: proc(
	L: ^vm.State,
	service: ^Terrain,
	datatype_registry: ^datatypes.Registry,
) {
	vm.NewTable(L, 0, len(terrain_material_names))
	for index in 0 ..< len(terrain_material_names) {
		color := terrain_material_color(service, enums.Material(index))
		if datatype_registry != nil {
			datatypes.Push_Color3(L, datatype_registry, color)
		} else {
			vm.PushNil(L)
		}
		vm.SetField(L, -2, terrain_material_names[index])
	}
}

terrain_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^Terrain)object
	switch key {
	case "MaterialVariant":
		vm.PushString(L, service.material_variant)
	case "Decoration":
		vm.PushBoolean(L, service.decoration)
	case "GrassLength":
		vm.PushNumber(L, f64(service.grass_length))
	case "IsSmooth":
		vm.PushBoolean(L, true)
	case "MaterialColors":
		terrain_push_material_colors(L, service, datatype_registry)
	case "MaxExtents":
		if datatype_registry == nil {
			return false
		}
		datatypes.Push_Region3int16(L, datatype_registry, Terrain_Max_Extents)
	case "WaterColor":
		if datatype_registry == nil {
			return false
		}
		datatypes.Push_Color3(L, datatype_registry, service.water_color)
	case "WaterReflectance":
		vm.PushNumber(L, f64(service.water_reflectance))
	case "WaterTransparency":
		vm.PushNumber(L, f64(service.water_transparency))
	case "WaterWaveSize":
		vm.PushNumber(L, f64(service.water_wave_size))
	case "WaterWaveSpeed":
		vm.PushNumber(L, f64(service.water_wave_speed))
	case "VoxelSize":
		vm.PushNumber(L, f64(service.voxel_size))
	case "IsoLevel":
		vm.PushNumber(L, f64(service.iso_level))
	case "ChunkSize":
		vm.PushNumber(L, TERRAIN_CHUNK_SIZE)
	case "QueuedChunkCount":
		vm.PushNumber(L, f64(max(0, len(service.dirty_queue) - service.dirty_head)))
	case "SetVoxel", "GetVoxel", "Fill", "Clear", "GenerateMesh":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

terrain_service_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	service := cast(^Terrain)object
	switch key {
	case "MaterialVariant":
		copy := strings.clone(vm.ArgString(L, value_index))
		delete(service.material_variant)
		service.material_variant = copy
	case "Decoration":
		service.decoration = vm.ArgBoolean(L, value_index)
	case "GrassLength":
		service.grass_length = max(0, f32(vm.ArgNumber(L, value_index)))
	case "WaterColor":
		if datatype_registry == nil {
			return false
		}
		service.water_color = datatypes.Arg_Color3(L, value_index, datatype_registry)
	case "WaterReflectance":
		service.water_reflectance = clamp(f32(vm.ArgNumber(L, value_index)), 0, 1)
	case "WaterTransparency":
		service.water_transparency = clamp(f32(vm.ArgNumber(L, value_index)), 0, 1)
	case "WaterWaveSize":
		service.water_wave_size = clamp(f32(vm.ArgNumber(L, value_index)), 0, 1)
	case "WaterWaveSpeed":
		service.water_wave_speed = clamp(f32(vm.ArgNumber(L, value_index)), 0, 100)
	case "VoxelSize":
		value := f32(vm.ArgNumber(L, value_index))
		if value <= 0 {
			_ = vm.RaiseError(L, "Terrain.VoxelSize must be greater than zero")
			return true
		}
		service.voxel_size = value
		terrain_mark_all_dirty(service)
	case "IsoLevel":
		service.iso_level = clamp(f32(vm.ArgNumber(L, value_index)), 0.001, 0.999)
		terrain_mark_all_dirty(service)
	case:
		return false
	}
	return true
}


terrain_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^Terrain)object

	switch method {
	case "Clear":
		terrain_clear(service, service.renderer)
		return 0, true

	case "CountCells":
		vm.PushNumber(L, f64(Terrain_Cell_Count(service)))
		return 1, true

	case "CellCornerToWorld":
		x := vm.ArgOptionalNumber(L, 2, 0)
		y := vm.ArgOptionalNumber(L, 3, 0)
		z := vm.ArgOptionalNumber(L, 4, 0)
		datatypes.Push_Vector3(
			L,
			datatypes.Vector3 {
				f32(x) * service.voxel_size,
				f32(y) * service.voxel_size,
				f32(z) * service.voxel_size,
			},
		)
		return 1, true

	case "CellCenterToWorld":
		x := vm.ArgOptionalNumber(L, 2, 0)
		y := vm.ArgOptionalNumber(L, 3, 0)
		z := vm.ArgOptionalNumber(L, 4, 0)
		datatypes.Push_Vector3(L, terrain_cell_center_world(service, int(x), int(y), int(z)))
		return 1, true

	case "WorldToCell":
		position := datatypes.Arg_Vector3(L, 2)
		cx, cy, cz := terrain_cell_from_world(service, position)
		datatypes.Push_Vector3(L, datatypes.Vector3{f32(cx), f32(cy), f32(cz)})
		return 1, true

	case "WorldToCellPreferEmpty", "WorldToCellPreferSolid":
		position := datatypes.Arg_Vector3(L, 2)
		prefer_solid := method == "WorldToCellPreferSolid"
		cx, cy, cz := terrain_cell_from_world(service, position)
		if prefer_solid == (terrain_occupancy(service, cx, cy, cz) > 0) {
			datatypes.Push_Vector3(L, datatypes.Vector3{f32(cx), f32(cy), f32(cz)})
			return 1, true
		}


		for radius in 1 ..= TERRAIN_CHUNK_SIZE {
			for dx in -radius ..= radius {
				for dy in -radius ..= radius {
					for dz in -radius ..= radius {
						nx, ny, nz := cx + dx, cy + dy, cz + dz
						solid := terrain_occupancy(service, nx, ny, nz) > 0
						if solid == prefer_solid {
							datatypes.Push_Vector3(L, datatypes.Vector3{f32(nx), f32(ny), f32(nz)})
							return 1, true
						}
					}
				}
			}
		}
		datatypes.Push_Vector3(L, datatypes.Vector3{f32(cx), f32(cy), f32(cz)})
		return 1, true

	case "GetMaterialColor":
		material := terrain_arg_material(L, 2, enum_registry, .SmoothPlastic)
		if datatype_registry == nil {
			return vm.RaiseError(L, "datatype registry is unavailable"), true
		}
		datatypes.Push_Color3(L, datatype_registry, terrain_material_color(service, material))
		return 1, true

	case "SetMaterialColor":
		material := terrain_arg_material(L, 2, enum_registry, .SmoothPlastic)
		if datatype_registry == nil {
			return vm.RaiseError(L, "datatype registry is unavailable"), true
		}
		service.material_colors[material] = datatypes.Arg_Color3(L, 3, datatype_registry)
		terrain_mark_all_dirty(service)
		return 0, true

	case "FillBall":
		center := datatypes.Arg_Vector3(L, 2)
		radius := f32(vm.ArgNumber(L, 3))
		material := terrain_arg_material(L, 4, enum_registry, .Grass)
		terrain_fill_ball(service, center, radius, material)
		return 0, true

	case "FillBlock":
		if datatype_registry == nil {
			return vm.RaiseError(L, "datatype registry is unavailable"), true
		}
		cframe := datatypes.Arg_CFrame(L, 2, datatype_registry)
		size := datatypes.Arg_Vector3(L, 3)
		material := terrain_arg_material(L, 4, enum_registry, .Grass)
		terrain_fill_box(service, cframe, size, material)
		return 0, true

	case "FillWedge":
		if datatype_registry == nil {
			return vm.RaiseError(L, "datatype registry is unavailable"), true
		}
		cframe := datatypes.Arg_CFrame(L, 2, datatype_registry)
		size := datatypes.Arg_Vector3(L, 3)
		material := terrain_arg_material(L, 4, enum_registry, .Grass)
		terrain_fill_wedge(service, cframe, size, material)
		return 0, true

	case "FillCylinder":
		if datatype_registry == nil {
			return vm.RaiseError(L, "datatype registry is unavailable"), true
		}
		cframe := datatypes.Arg_CFrame(L, 2, datatype_registry)
		height := f32(vm.ArgNumber(L, 3))
		radius := f32(vm.ArgNumber(L, 4))
		material := terrain_arg_material(L, 5, enum_registry, .Grass)
		terrain_fill_cylinder(service, cframe, height, radius, material)
		return 0, true

	case "FillRegion":
		if datatype_registry == nil {
			return vm.RaiseError(L, "datatype registry is unavailable"), true
		}
		region := datatypes.Arg_Region3(L, 2, datatype_registry)
		resolution := f32(vm.ArgOptionalNumber(L, 3, f64(service.voxel_size)))
		material := terrain_arg_material(L, 4, enum_registry, .Grass)
		terrain_fill_region(service, region, resolution, material)
		return 0, true

	case "ReplaceMaterial":
		if datatype_registry == nil {
			return vm.RaiseError(L, "datatype registry is unavailable"), true
		}
		region := datatypes.Arg_Region3(L, 2, datatype_registry)
		resolution := f32(vm.ArgOptionalNumber(L, 3, f64(service.voxel_size)))
		source := terrain_arg_material(L, 4, enum_registry, .Grass)
		target := terrain_arg_material(L, 5, enum_registry, .Grass)
		terrain_replace_material(service, region, resolution, source, target)
		return 0, true

	case "ReadVoxels":
		if datatype_registry == nil {
			return vm.RaiseError(L, "datatype registry is unavailable"), true
		}
		region := datatypes.Arg_Region3(L, 2, datatype_registry)
		resolution := f32(vm.ArgOptionalNumber(L, 3, f64(service.voxel_size)))
		cells, ok := terrain_region_cells(region, resolution)
		if !ok {
			return vm.RaiseError(L, "invalid voxel region or resolution"), true
		}
		terrain_push_material_grid(L, service, cells, enum_registry)
		terrain_push_occupancy_grid(L, service, cells, false)
		return 2, true

	case "WriteVoxels":
		if datatype_registry == nil {
			return vm.RaiseError(L, "datatype registry is unavailable"), true
		}
		region := datatypes.Arg_Region3(L, 2, datatype_registry)
		resolution := f32(vm.ArgOptionalNumber(L, 3, f64(service.voxel_size)))
		cells, ok := terrain_region_cells(region, resolution)
		if !ok {
			return vm.RaiseError(L, "invalid voxel region or resolution"), true
		}
		if !vm.IsTable(L, 4) || !vm.IsTable(L, 5) {
			return vm.RaiseError(L, "WriteVoxels expects material and occupancy tables"), true
		}

		base := vm.StackTop(L)
		for x in 0 ..< cells.count_x {
			for y in 0 ..< cells.count_y {
				for z in 0 ..< cells.count_z {
					vm.SetStackTop(L, base)
					occupancy: f32
					if terrain_read_3d_value(L, 5, x, y, z) && vm.IsNumber(L, -1) {
						occupancy = clamp(f32(vm.ArgNumber(L, -1)), 0, 1)
					}
					vm.SetStackTop(L, base)

					material := enums.Material.Air
					if terrain_read_3d_value(L, 4, x, y, z) &&
					   enum_registry != nil &&
					   vm.IsUserdataType(L, -1, &enum_registry.item_binding) {
						item := enums.Arg_Item(L, -1, enum_registry, "Material")
						if item != nil {
							material = enums.Material(item.value)
						}
					}
					vm.SetStackTop(L, base)

					terrain_write_cell_at(service, cells, x, y, z, occupancy, 0, material)
				}
			}
		}
		vm.SetStackTop(L, base)
		return 0, true

	case "ReadVoxelChannels":
		if datatype_registry == nil {
			return vm.RaiseError(L, "datatype registry is unavailable"), true
		}
		region := datatypes.Arg_Region3(L, 2, datatype_registry)
		resolution := f32(vm.ArgOptionalNumber(L, 3, f64(service.voxel_size)))
		cells, ok := terrain_region_cells(region, resolution)
		if !ok {
			return vm.RaiseError(L, "invalid voxel region or resolution"), true
		}

		vm.NewTable(L, 0, 3)
		channel_count := vm.RawLen(L, 4)
		for channel_index in 1 ..= channel_count {
			_ = vm.RawGetIndex(L, 4, channel_index)
			if !vm.IsString(L, -1) {
				vm.Pop(L)
				continue
			}
			channel := vm.ArgString(L, -1)
			vm.Pop(L)

			switch {
			case terrain_equal_fold(channel, "SolidMaterial"):
				terrain_push_material_grid(L, service, cells, enum_registry)
				vm.SetField(L, -2, channel)
			case terrain_equal_fold(channel, "SolidOccupancy"):
				terrain_push_occupancy_grid(L, service, cells, false)
				vm.SetField(L, -2, channel)
			case terrain_equal_fold(channel, "LiquidOccupancy"):
				terrain_push_occupancy_grid(L, service, cells, true)
				vm.SetField(L, -2, channel)
			}
		}
		return 1, true

	case "WriteVoxelChannels":
		if datatype_registry == nil {
			return vm.RaiseError(L, "datatype registry is unavailable"), true
		}
		region := datatypes.Arg_Region3(L, 2, datatype_registry)
		resolution := f32(vm.ArgOptionalNumber(L, 3, f64(service.voxel_size)))
		cells, ok := terrain_region_cells(region, resolution)
		if !ok {
			return vm.RaiseError(L, "invalid voxel region or resolution"), true
		}
		if !vm.IsTable(L, 4) {
			return vm.RaiseError(L, "WriteVoxelChannels expects a channel dictionary"), true
		}

		base := vm.StackTop(L)
		occupancy_index, material_index, liquid_index: int

		_ = vm.GetField(L, 4, "SolidOccupancy")
		if vm.IsTable(L, -1) {occupancy_index = vm.StackTop(L)} else {vm.Pop(L)}
		_ = vm.GetField(L, 4, "SolidMaterial")
		if vm.IsTable(L, -1) {material_index = vm.StackTop(L)} else {vm.Pop(L)}
		_ = vm.GetField(L, 4, "LiquidOccupancy")
		if vm.IsTable(L, -1) {liquid_index = vm.StackTop(L)} else {vm.Pop(L)}
		loop_base := vm.StackTop(L)

		for x in 0 ..< cells.count_x {
			for y in 0 ..< cells.count_y {
				for z in 0 ..< cells.count_z {
					vm.SetStackTop(L, loop_base)
					center := terrain_region_cell_center(cells, x, y, z)
					cx, cy, cz := terrain_cell_from_world(service, center)

					occupancy := terrain_occupancy(service, cx, cy, cz)
					if occupancy_index > 0 &&
					   terrain_read_3d_value(L, occupancy_index, x, y, z) &&
					   vm.IsNumber(L, -1) {
						occupancy = clamp(f32(vm.ArgNumber(L, -1)), 0, 1)
					}
					vm.SetStackTop(L, loop_base)

					water := terrain_water(service, cx, cy, cz)
					if liquid_index > 0 &&
					   terrain_read_3d_value(L, liquid_index, x, y, z) &&
					   vm.IsNumber(L, -1) {
						water = clamp(f32(vm.ArgNumber(L, -1)), 0, 1)
					}
					vm.SetStackTop(L, loop_base)

					material := enums.Material.Grass
					if cell, found := terrain_get_cell(service, cx, cy, cz); found {
						material = cell.material
					}
					if material_index > 0 &&
					   terrain_read_3d_value(L, material_index, x, y, z) &&
					   enum_registry != nil &&
					   vm.IsUserdataType(L, -1, &enum_registry.item_binding) {
						item := enums.Arg_Item(L, -1, enum_registry, "Material")
						if item != nil {
							material = enums.Material(item.value)
						}
					}

					terrain_set_cell(service, cx, cy, cz, occupancy, water, material)
				}
			}
		}
		vm.SetStackTop(L, base)
		return 0, true

	case "CopyRegion":
		if datatype_registry == nil {
			return vm.RaiseError(L, "datatype registry is unavailable"), true
		}
		region := datatypes.Arg_Region3int16(L, 2, datatype_registry)
		nx := max(0, int(region.Max.X) - int(region.Min.X))
		ny := max(0, int(region.Max.Y) - int(region.Min.Y))
		nz := max(0, int(region.Max.Z) - int(region.Min.Z))

		snapshot := datatypes.TerrainRegion_New(datatypes.Vector3int16{i16(nx), i16(ny), i16(nz)})
		for x in 0 ..< nx {
			for y in 0 ..< ny {
				for z in 0 ..< nz {
					index, ok := datatypes.TerrainRegion_Index(&snapshot, x, y, z)
					if !ok {
						continue
					}
					if cell, found := terrain_get_cell(
						service,
						int(region.Min.X) + x,
						int(region.Min.Y) + y,
						int(region.Min.Z) + z,
					); found {
						snapshot.materials[index] = i64(cell.material)
						snapshot.occupancy[index] = cell.occupancy
					} else {
						snapshot.materials[index] = i64(enums.Material.Air)
					}
				}
			}
		}
		datatypes.Push_TerrainRegion(L, datatype_registry, snapshot)
		return 1, true

	case "PasteRegion":
		if datatype_registry == nil {
			return vm.RaiseError(L, "datatype registry is unavailable"), true
		}
		region := datatypes.Arg_TerrainRegion(L, 2, datatype_registry)
		if region == nil {
			return 0, true
		}
		corner := datatypes.Arg_Vector3int16(L, 3, datatype_registry)
		paste_empty := vm.ArgOptionalBoolean(L, 4, false)

		nx := max(0, int(region.size.X))
		ny := max(0, int(region.size.Y))
		nz := max(0, int(region.size.Z))
		for x in 0 ..< nx {
			for y in 0 ..< ny {
				for z in 0 ..< nz {
					index, ok := datatypes.TerrainRegion_Index(region, x, y, z)
					if !ok {
						continue
					}
					occupancy := region.occupancy[index]
					material := enums.Material(region.materials[index])
					if occupancy <= 0 {
						if !paste_empty {
							continue
						}
						terrain_erase_cell(
							service,
							int(corner.X) + x,
							int(corner.Y) + y,
							int(corner.Z) + z,
						)
						continue
					}
					terrain_set_cell(
						service,
						int(corner.X) + x,
						int(corner.Y) + y,
						int(corner.Z) + z,
						occupancy,
						0,
						material,
					)
				}
			}
		}
		return 0, true


	case "AutowedgeCell":
		vm.PushBoolean(L, false)
		return 1, true
	case "AutowedgeCells", "ConvertToSmooth":
		return 0, true
	case "GetCell":
		if datatype_registry == nil {
			return vm.RaiseError(L, "datatype registry is unavailable"), true
		}
		x := int(vm.ArgOptionalNumber(L, 2, 0))
		y := int(vm.ArgOptionalNumber(L, 3, 0))
		z := int(vm.ArgOptionalNumber(L, 4, 0))
		cell, ok := terrain_get_cell(service, x, y, z)
		material := enums.Material.Air
		occupancy := f32(0)
		if ok {
			material = cell.material
			occupancy = cell.occupancy
		}
		if enum_registry != nil {
			_ = enums.Push_Item_By_Value(L, enum_registry, "Material", i64(material))
		} else {
			vm.PushNil(L)
		}
		vm.PushNumber(L, f64(occupancy))
		return 2, true
	case "GetWaterCell":
		x := int(vm.ArgOptionalNumber(L, 2, 0))
		y := int(vm.ArgOptionalNumber(L, 3, 0))
		z := int(vm.ArgOptionalNumber(L, 4, 0))
		if enum_registry != nil {
			_ = enums.Push_Item_By_Value(L, enum_registry, "Material", i64(enums.Material.Water))
		} else {
			vm.PushNil(L)
		}
		vm.PushNumber(L, f64(terrain_water(service, x, y, z)))
		return 2, true
	case "SetCell":
		x := int(vm.ArgOptionalNumber(L, 2, 0))
		y := int(vm.ArgOptionalNumber(L, 3, 0))
		z := int(vm.ArgOptionalNumber(L, 4, 0))
		material := terrain_arg_material(L, 5, enum_registry, .Grass)
		terrain_set_cell(service, x, y, z, 1, 0, material)
		return 0, true
	case "SetCells":
		if datatype_registry == nil {
			return vm.RaiseError(L, "datatype registry is unavailable"), true
		}
		region := datatypes.Arg_Region3int16(L, 2, datatype_registry)
		material := terrain_arg_material(L, 3, enum_registry, .Grass)
		for x in int(region.Min.X) ..< int(region.Max.X) {
			for y in int(region.Min.Y) ..< int(region.Max.Y) {
				for z in int(region.Min.Z) ..< int(region.Max.Z) {
					terrain_set_cell(service, x, y, z, 1, 0, material)
				}
			}
		}
		return 0, true
	case "SetWaterCell":
		x := int(vm.ArgOptionalNumber(L, 2, 0))
		y := int(vm.ArgOptionalNumber(L, 3, 0))
		z := int(vm.ArgOptionalNumber(L, 4, 0))
		terrain_set_water(service, x, y, z, 1)
		return 0, true


	case "SetVoxel":
		x := int(vm.ArgOptionalNumber(L, 2, 0))
		y := int(vm.ArgOptionalNumber(L, 3, 0))
		z := int(vm.ArgOptionalNumber(L, 4, 0))
		occupancy := clamp(f32(vm.ArgNumber(L, 5)), 0, 1)
		material := terrain_arg_material(L, 6, enum_registry, .Grass)
		terrain_set_cell(service, x, y, z, occupancy, 0, material)
		return 0, true

	case "GetVoxel":
		if datatype_registry == nil {
			return vm.RaiseError(L, "datatype registry is unavailable"), true
		}
		x := int(vm.ArgOptionalNumber(L, 2, 0))
		y := int(vm.ArgOptionalNumber(L, 3, 0))
		z := int(vm.ArgOptionalNumber(L, 4, 0))
		cell, ok := terrain_get_cell(service, x, y, z)
		if !ok {
			vm.PushNil(L)
			return 1, true
		}
		vm.NewTable(L, 0, 2)
		vm.PushNumber(L, f64(cell.occupancy))
		vm.SetField(L, -2, "occupancy")
		if enum_registry != nil {
			_ = enums.Push_Item_By_Value(L, enum_registry, "Material", i64(cell.material))
		} else {
			vm.PushNil(L)
		}
		vm.SetField(L, -2, "material")
		return 1, true

	case "Fill":
		pos_x := int(math.floor(vm.ArgOptionalNumber(L, 2, 0)))
		pos_y := int(math.floor(vm.ArgOptionalNumber(L, 3, 0)))
		pos_z := int(math.floor(vm.ArgOptionalNumber(L, 4, 0)))
		width := max(1, int(math.floor(vm.ArgOptionalNumber(L, 5, 20))))
		height := max(1, int(math.floor(vm.ArgOptionalNumber(L, 6, 20))))
		options := terrain_default_fill_options()
		if vm.IsTable(L, 7) {
			options = terrain_read_fill_options(L, 7, enum_registry)
		}
		terrain_fill_generated(service, pos_x, pos_y, pos_z, width, height, options)
		return 0, true

	case "GenerateMesh":
		terrain_mark_all_dirty(service)
		return 0, true
	}

	return 0, false
}

Register_Terrain_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Terrain_Class,
		terrain_service_construct,
		terrain_service_destroy,
		creatable = false,
		get = terrain_service_get,
		set = terrain_service_set,
		namecall = terrain_service_namecall,
		properties = []string {
			"Decoration",
			"GrassLength",
			"IsSmooth",
			"MaterialColors",
			"MaterialVariant",
			"MaxExtents",
			"WaterColor",
			"WaterReflectance",
			"WaterTransparency",
			"WaterWaveSize",
			"WaterWaveSpeed",
			"VoxelSize",
			"IsoLevel",
			"ChunkSize",
			"QueuedChunkCount",
		},
	)
}
