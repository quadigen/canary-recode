package services

// wire:service global="terrain"

import "core:math"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import kineffi "../bindings"
import materials "../material"
import marching_cubes "../util/marching_cubes"
import serializer "../serializer"
import vm "../vm"

TERRAIN_CHUNK_SIZE             :: 16
TERRAIN_REBUILDS_PER_FRAME     :: 2
TERRAIN_MAX_VERTICES_PER_MESH :: 65532 // uint16 indices, kept divisible by 3
TERRAIN_STREAM_ID              :: u64(0x5445525241494E) // "TERRAIN"

TERRAIN_DEFAULT_VOXEL_SIZE :: f32(4)
TERRAIN_DEFAULT_ISO_LEVEL  :: f32(0.5)

// Roblox exposes MaxExtents as the largest region terrain can occupy. It is a
// fixed bound rather than the bounds of the stored cells.
TERRAIN_MAX_EXTENTS :: datatypes.Region3int16{
	Min = datatypes.Vector3int16{-16000, -16000, -16000},
	Max = datatypes.Vector3int16{16000, 16000, 16000},
}

Terrain_Class := classes.Class_Info{
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

// Terrain_Cell is a single voxel. occupancy is the solid fill fraction in
// [0, 1] (0 means empty), and water is the independent liquid fill fraction.
// Missing map entries are empty cells.
Terrain_Cell :: struct {
	occupancy: f32,
	water:     f32,
	material:  enums.Material,
}

Terrain_Chunk :: struct {
	key:    Terrain_Chunk_Key,
	dirty:  bool,
	meshes: [dynamic]^kineffi.KineFilamentMesh,
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

// Terrain_Region_Cells describes a Region3 expanded to a resolution grid.
Terrain_Region_Cells :: struct {
	origin:               datatypes.Vector3,
	resolution:           f32,
	count_x, count_y, count_z: int,
}

// Terrain_Cell_Record is the wire form of one voxel. Terrain replication needs
// absolute coordinates, so it is a separate type from the key-addressed
// Terrain_Cell rather than reusing it.
Terrain_Cell_Record :: struct {
	x, y, z:   i32,
	occupancy: f32,
	water:     f32,
	material:  enums.Material,
}

// Terrain_Dirty_Cell is a voxel awaiting delivery to clients, tagged with the
// serial of the edit that last touched it.
Terrain_Dirty_Cell :: struct {
	record: Terrain_Cell_Record,
	serial: u64,
}

// TERRAIN_DIRTY_LIMIT bounds the pending-change map. A long-running server that
// edits terrain forever would otherwise accumulate every voxel it ever touched.
// Hitting the cap invalidates every peer and forces a full resend, which is
// more expensive once but bounded, instead of growing without limit.
TERRAIN_DIRTY_LIMIT: int = 262144

Terrain :: struct {
	using service: Service,

	voxels:       map[Terrain_Voxel_Key]Terrain_Cell,
	chunks:       map[Terrain_Chunk_Key]^Terrain_Chunk,
	dirty_lookup: map[Terrain_Chunk_Key]bool,
	dirty_queue:  [dynamic]Terrain_Chunk_Key,
	dirty_head:   int,
	preparing:    bool,

	voxel_size: f32,
	iso_level:  f32,

	// Replication change tracking.
	//
	// The connect-time snapshot is not enough on its own: a server that edits
	// terrain after a client has joined would otherwise leave that client on a
	// world that no longer exists, which reads as a physics desync rather than a
	// missing update.
	//
	// Every mutation stamps the voxel into replication_dirty with the serial it
	// was changed at, so repeated edits to one voxel coalesce into a single
	// entry. Each peer holds the last serial it was sent, which is all the
	// bookkeeping a delta needs.
	//
	// dirty_tracking is only armed once a server has actually pushed a snapshot.
	// Before that the full snapshot already covers every change, and on a client
	// the map would only accumulate voxels nobody will ever read.
	replication_dirty:      map[Terrain_Voxel_Key]Terrain_Dirty_Cell,
	change_serial:          u64,
	dirty_epoch:            u64,
	dirty_tracking:         bool,

	decoration:   bool,
	grass_length: f32,

	water_color:        datatypes.Color3,
	water_reflectance:  f32,
	water_transparency: f32,
	water_wave_size:    f32,
	water_wave_speed:   f32,

	material_colors: map[enums.Material]datatypes.Color3,

	texture_set:     ^kineffi.KineFilamentTex,
	texture_context: ^kineffi.KineFilamentContext,
	draw_items:      [dynamic]kineffi.KineFilamentDrawItem,
	draw_dirty:      bool,
	draw_version:    u64,
	// geometry_version advances on every stored voxel change, unlike draw_version
	// which only advances once the renderer has caught up. Collision reads this
	// one: a client applying replicated voxels has new ground a frame or more
	// before the mesher has rebuilt anything.
	geometry_version: u64,
	renderer:        ^classes.Renderer_Object,

	// Water-surface renderable. Water voxels are drawn as a single dense grid
	// per column top surface, displaced by the GPU water material; this is the
	// reusable grid mesh for those draw items.
	surface_mesh:      ^kineffi.KineFilamentMesh,
}

terrain_material_names := [12]string{
	"SmoothPlastic",
	"Wood",
	"Brick",
	"Grass",
	"Concrete",
	"Slate",
	"Glass",
	"Neon",
	"Sand",
	"Water",
	"debug",
	"Air",
}

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
	return Terrain_Chunk_Key{
		terrain_floor_div(x, TERRAIN_CHUNK_SIZE),
		terrain_floor_div(y, TERRAIN_CHUNK_SIZE),
		terrain_floor_div(z, TERRAIN_CHUNK_SIZE),
	}
}

terrain_get_or_create_chunk :: proc(
	service: ^Terrain,
	key: Terrain_Chunk_Key,
) -> ^Terrain_Chunk {
	if chunk, ok := service.chunks[key]; ok {
		return chunk
	}

	chunk := new(Terrain_Chunk)
	chunk.key = key
	chunk.dirty = true
	chunk.meshes = make([dynamic]^kineffi.KineFilamentMesh)
	service.chunks[key] = chunk
	return chunk
}

terrain_mark_chunk_dirty :: proc(service: ^Terrain, key: Terrain_Chunk_Key) {
	chunk := terrain_get_or_create_chunk(service, key)
	chunk.dirty = true

	if _, queued := service.dirty_lookup[key]; !queued {
		service.dirty_lookup[key] = true
		append(&service.dirty_queue, key)
	}
}

terrain_mark_voxel_dirty :: proc(service: ^Terrain, x, y, z: int) {
	service.geometry_version += 1
	key := terrain_chunk_key_for_voxel(x, y, z)
	terrain_mark_chunk_dirty(service, key)

	lx := terrain_floor_mod(x, TERRAIN_CHUNK_SIZE)
	ly := terrain_floor_mod(y, TERRAIN_CHUNK_SIZE)
	lz := terrain_floor_mod(z, TERRAIN_CHUNK_SIZE)

	// Border samples affect a neighboring chunk's last/first marching cell too.
	if lx == 0                    { terrain_mark_chunk_dirty(service, {key.x-1, key.y, key.z}) }
	if lx == TERRAIN_CHUNK_SIZE-1 { terrain_mark_chunk_dirty(service, {key.x+1, key.y, key.z}) }
	if ly == 0                    { terrain_mark_chunk_dirty(service, {key.x, key.y-1, key.z}) }
	if ly == TERRAIN_CHUNK_SIZE-1 { terrain_mark_chunk_dirty(service, {key.x, key.y+1, key.z}) }
	if lz == 0                    { terrain_mark_chunk_dirty(service, {key.x, key.y, key.z-1}) }
	if lz == TERRAIN_CHUNK_SIZE-1 { terrain_mark_chunk_dirty(service, {key.x, key.y, key.z+1}) }
}

terrain_mark_all_dirty :: proc(service: ^Terrain) {
	for key, _ in service.chunks {
		terrain_mark_chunk_dirty(service, key)
	}
}

// ---------------------------------------------------------------------------
// Material helpers
// ---------------------------------------------------------------------------

// terrain_material_layer maps an engine Material onto one of the six triplanar
// terrain shader layers: grass, sand, slate, concrete, smooth plastic, wood.
terrain_material_layer :: proc(material: enums.Material) -> int {
	switch material {
	case .Grass:
		return 0
	case .Sand:
		return 1
	case .Slate, .Glass:
		return 2
	case .Concrete, .Brick:
		return 3
	case .Wood:
		return 5
	case .SmoothPlastic, .Neon, .Water, .Air, .debug:
		return 4
	case:
		return 4
	}
}

// terrain_material_is_liquid reports whether a filled voxel is a fluid rather
// than rock. Liquid voxels are excluded from the solid marching-cubes surface
// and are drawn by terrain_append_surface_draw_items instead, which is what
// lets a Water or Glass fill render as a translucent surface at all.
terrain_material_is_liquid :: proc(material: enums.Material) -> bool {
	return material == .Water || material == .Glass
}

// terrain_material_surface_kind picks the GPU material for a liquid voxel's
// surface. Neon is a solid emissive fill, so it keeps its voxel in the solid
// mesh and gets a surface quad drawn over it.
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
	switch material {
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
) -> (enums.Material, bool) {
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

// ---------------------------------------------------------------------------
// Voxel storage
// ---------------------------------------------------------------------------

terrain_get_cell :: proc(service: ^Terrain, x, y, z: int) -> (Terrain_Cell, bool) {
	return service.voxels[Terrain_Voxel_Key{x, y, z}]
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

terrain_erase_cell :: proc(service: ^Terrain, x, y, z: int) {
	key := Terrain_Voxel_Key{x, y, z}
	if _, ok := service.voxels[key]; !ok {
		return
	}
	delete_key(&service.voxels, key)
	terrain_mark_voxel_dirty(service, x, y, z)
}

terrain_set_cell :: proc(
	service: ^Terrain,
	x, y, z: int,
	occupancy, water: f32,
	material: enums.Material,
) {
	occ := clamp(occupancy, 0, 1)
	wat := clamp(water, 0, 1)

	// A liquid fill is stored in the water channel rather than as solid rock.
	// Terrain:Fill(region, Water) has no separate water argument, so this is the
	// only place a Water material can become a surface the renderer will draw.
	if terrain_material_is_liquid(material) && occ > 0 {
		wat = max(wat, occ)
		occ = 0
	}

	if occ <= 0 && wat <= 0 {
		// A removal has to reach clients too, and an empty record is how: the
		// client runs the same normalization and erases the voxel it holds.
		terrain_note_change(service, x, y, z, 0, 0, material)
		terrain_erase_cell(service, x, y, z)
		return
	}

	service.voxels[Terrain_Voxel_Key{x, y, z}] = Terrain_Cell{
		occupancy = occ,
		water     = wat,
		material  = material,
	}
	terrain_note_change(service, x, y, z, occ, wat, material)
	terrain_mark_voxel_dirty(service, x, y, z)
}

// terrain_note_change stamps a voxel as pending for replication. It records the
// state the caller actually stored, not the state it was asked for, so the
// client reproduces the same normalization this service applied rather than
// diverging on the second edit.
terrain_note_change :: proc(
	service: ^Terrain,
	x, y, z: int,
	occupancy, water: f32,
	material: enums.Material,
) {
	if !service.dirty_tracking {return}
	service.change_serial += 1
	service.replication_dirty[Terrain_Voxel_Key{x, y, z}] = Terrain_Dirty_Cell{
		record = Terrain_Cell_Record{
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

// ---------------------------------------------------------------------------
// Sampling, normals and material weights
// ---------------------------------------------------------------------------

terrain_sample_occupancy :: proc(service: ^Terrain, voxel_position: datatypes.Vector3) -> f32 {
	x0 := int(math.floor(voxel_position.x))
	y0 := int(math.floor(voxel_position.y))
	z0 := int(math.floor(voxel_position.z))

	fx := voxel_position.x - f32(x0)
	fy := voxel_position.y - f32(y0)
	fz := voxel_position.z - f32(z0)

	result: f32
	for dx in 0..<2 {
		wx := dx == 0 ? 1-fx : fx
		for dy in 0..<2 {
			wy := dy == 0 ? 1-fy : fy
			for dz in 0..<2 {
				wz := dz == 0 ? 1-fz : fz
				result += terrain_occupancy(service, x0+dx, y0+dy, z0+dz) * wx * wy * wz
			}
		}
	}
	return result
}

terrain_normal_at_world :: proc(service: ^Terrain, world: datatypes.Vector3) -> datatypes.Vector3 {
	inv_voxel := 1.0 / service.voxel_size
	p := datatypes.Vector3{world.x*inv_voxel, world.y*inv_voxel, world.z*inv_voxel}
	eps: f32 = 0.5

	dx := terrain_sample_occupancy(service, {p.x-eps, p.y, p.z}) -
	      terrain_sample_occupancy(service, {p.x+eps, p.y, p.z})
	dy := terrain_sample_occupancy(service, {p.x, p.y-eps, p.z}) -
	      terrain_sample_occupancy(service, {p.x, p.y+eps, p.z})
	dz := terrain_sample_occupancy(service, {p.x, p.y, p.z-eps}) -
	      terrain_sample_occupancy(service, {p.x, p.y, p.z+eps})

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

	for dx in 0..<2 {
		wx := dx == 0 ? 1-fx : fx
		for dy in 0..<2 {
			wy := dy == 0 ? 1-fy : fy
			for dz in 0..<2 {
				wz := dz == 0 ? 1-fz : fz
			if cell, ok := terrain_get_cell(service, x0+dx, y0+dy, z0+dz); ok &&
			   cell.occupancy > 0 &&
			   !terrain_material_is_liquid(cell.material) {
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
	for i in 0..<6 {
		weights[i] /= total
	}
	return weights
}

// ---------------------------------------------------------------------------
// Marching cubes meshing
// ---------------------------------------------------------------------------

Terrain_Mesh_Builder :: struct {
	service:          ^Terrain,
	vertex_data:      ^[dynamic]f32,
	material_weights: ^[dynamic]f32,
}

terrain_append_vertex :: proc(
	service: ^Terrain,
	vertex_data: ^[dynamic]f32,
	material_weights: ^[dynamic]f32,
	position, normal: datatypes.Vector3,
) {
	append(vertex_data,
		position.x, position.y, position.z,
		normal.x, normal.y, normal.z,
		0, 0,
	)

	weights := terrain_material_weights_at_world(service, position)
	for weight in weights {
		append(material_weights, weight)
	}
}

terrain_emit_triangle :: proc(
	service: ^Terrain,
	vertex_data: ^[dynamic]f32,
	material_weights: ^[dynamic]f32,
	p0, p1, p2: datatypes.Vector3,
) {
	v0 := p0
	v1 := p1
	v2 := p2

	n0 := terrain_normal_at_world(service, v0)
	n1 := terrain_normal_at_world(service, v1)
	n2 := terrain_normal_at_world(service, v2)

	face := datatypes.Vec3_Cross(
		datatypes.Vec3_Subtract(v1, v0),
		datatypes.Vec3_Subtract(v2, v0),
	)
	avg_normal := datatypes.Vec3_Add(datatypes.Vec3_Add(n0, n1), n2)
	if datatypes.Vec3_Dot(face, avg_normal) < 0 {
		swap_v1 := v1
		swap_n1 := n1
		v1 = v2
		n1 = n2
		v2 = swap_v1
		n2 = swap_n1
	}

	terrain_append_vertex(service, vertex_data, material_weights, v0, n0)
	terrain_append_vertex(service, vertex_data, material_weights, v1, n1)
	terrain_append_vertex(service, vertex_data, material_weights, v2, n2)
}

terrain_mc_emit :: proc(p0, p1, p2: marching_cubes.Vec3, user_data: rawptr) {
	builder := cast(^Terrain_Mesh_Builder)user_data
	if builder == nil || builder.service == nil {
		return
	}

	terrain_emit_triangle(
		builder.service,
		builder.vertex_data,
		builder.material_weights,
		datatypes.Vector3{p0.x, p0.y, p0.z},
		datatypes.Vector3{p1.x, p1.y, p1.z},
		datatypes.Vector3{p2.x, p2.y, p2.z},
	)
}

terrain_march_cell :: proc(
	service: ^Terrain,
	x, y, z: int,
	builder: ^Terrain_Mesh_Builder,
) {
	vs := service.voxel_size
	cell: marching_cubes.MC_Cell

	for i in 0..<8 {
		offset := marching_cubes.MC_Corner_Offsets[i]
		ox, oy, oz := int(offset.x), int(offset.y), int(offset.z)
		cell.positions[i] = marching_cubes.Vec3{
			f32(x+ox) * vs,
			f32(y+oy) * vs,
			f32(z+oz) * vs,
		}
		cell.densities[i] = terrain_occupancy(service, x+ox, y+oy, z+oz)
	}

	_ = marching_cubes.MC_March_Cube(
		&cell,
		service.iso_level,
		terrain_mc_emit,
		builder,
	)
}

// ---------------------------------------------------------------------------
// Chunk mesh upload and rebuild
// ---------------------------------------------------------------------------

terrain_destroy_chunk_meshes :: proc(
	chunk: ^Terrain_Chunk,
	renderer: ^classes.Renderer_Object,
) {
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
) {
	vertex_count := len(vertex_data) / 8
	if vertex_count == 0 || renderer == nil || renderer.Filament == nil {
		return
	}

	chunk.meshes = make([dynamic]^kineffi.KineFilamentMesh)
	start := 0
	for start < vertex_count {
		count := min(vertex_count-start, TERRAIN_MAX_VERTICES_PER_MESH)
		count -= count % 3
		if count <= 0 {
			break
		}

		vertex_slice := vertex_data[start*8:(start+count)*8]
		weight_slice := material_weights[start*8:(start+count)*8]
		indices := make([]u16, count)
		for i in 0..<count {
			indices[i] = u16(i)
		}

		mesh := kineffi.Kine_Filament_CreateTerrainMesh(
			renderer.Filament,
			cast(^f32)raw_data(vertex_slice),
			cast(^f32)raw_data(weight_slice),
			i32(count),
			cast(^u16)raw_data(indices),
			i32(count),
		)
		delete(indices)

		if mesh != nil {
			append(&chunk.meshes, mesh)
		}
		start += count
	}
}

terrain_rebuild_chunk :: proc(
	service: ^Terrain,
	chunk: ^Terrain_Chunk,
	renderer: ^classes.Renderer_Object,
) {
	if service == nil || chunk == nil {
		return
	}

	terrain_destroy_chunk_meshes(chunk, renderer)

	vertex_data := make([dynamic]f32, 0, 8192*8)
	material_weights := make([dynamic]f32, 0, 8192*8)
	defer delete(vertex_data)
	defer delete(material_weights)

	builder := Terrain_Mesh_Builder{
		service          = service,
		vertex_data      = &vertex_data,
		material_weights = &material_weights,
	}

	x0 := chunk.key.x * TERRAIN_CHUNK_SIZE
	y0 := chunk.key.y * TERRAIN_CHUNK_SIZE
	z0 := chunk.key.z * TERRAIN_CHUNK_SIZE

	for x in x0..<x0+TERRAIN_CHUNK_SIZE {
		for y in y0..<y0+TERRAIN_CHUNK_SIZE {
			for z in z0..<z0+TERRAIN_CHUNK_SIZE {
				terrain_march_cell(service, x, y, z, &builder)
			}
		}
	}

	terrain_upload_chunk_meshes(chunk, renderer, vertex_data[:], material_weights[:])
	chunk.dirty = false
	service.draw_dirty = true
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

terrain_ensure_texture_set :: proc(
	service: ^Terrain,
	renderer: ^classes.Renderer_Object,
) {
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

// ---------------------------------------------------------------------------
// Water surface rendering
//
// Water voxels are data-only for the marching-cubes solid mesh; their visible
// surface is emitted here as flat quads on the KINE_MESH_WATER_GRID, drawn
// with the GPU-displaced water material (Gerstner waves in the vertex shader).
// ---------------------------------------------------------------------------

terrain_destroy_surface_mesh :: proc(service: ^Terrain) {
	if service == nil {
		return
	}
	if service.surface_mesh != nil && service.renderer != nil && service.renderer.Filament != nil {
		_ = kineffi.Kine_Filament_DestroyMesh(service.renderer.Filament, service.surface_mesh)
	}
	service.surface_mesh = nil
}

terrain_append_surface_draw_items :: proc(service: ^Terrain) {
	if len(service.voxels) == 0 || service.renderer == nil || service.renderer.Filament == nil {
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

	vs := service.voxel_size

	for key, cell in &service.voxels {
		is_neon := cell.material == .Neon
		if cell.water <= 0 && !is_neon {
			continue
		}

		// Only an exposed top face is drawn. Anything occupying the cell above
		// hides this surface: more liquid means this is an interior face inside
		// the body of the water, and solid rock means the waterline is covered.
		// Drawing those anyway is both invisible and, because every surface shares
		// one displaced material, the hidden copies poke through the geometry in
		// front of them as the waves move.
		above, has_above := service.voxels[Terrain_Voxel_Key{key.x, key.y + 1, key.z}]
		if has_above && (above.water > 0 || above.occupancy > 0) {
			continue
		}

		level := max(cell.water, cell.occupancy)
		if level <= 0 {
			continue
		}
		surface_y := (f32(key.y) + level - 0.5) * vs

		kind := terrain_material_surface_kind(cell.material)
		color := terrain_material_color(service, cell.material)
		transmission := clamp(1.0 - service.water_transparency, 0.2, 1.0)
		param1: f32 = 0.08 // roughness
		param2: f32 = 1.33 // ior
		param3: f32 = 0.5  // thickness

		#partial switch enums.Material(cell.material) {
		case .Glass:
			transmission = 0.85
			param1 = 0.05
			param2 = 1.52
			param3 = 0.35
		case .Neon:
			transmission = 0
			param1 = 1.0
		case:
			// The water material's Gerstner waves travel roughly +/-0.7 studs peak
			// to trough, so the surface is sunk a little to keep crests from
			// poking through terrain at the waterline.
			surface_y -= 0.35
		}

		// KINE_MESH_WATER_GRID is a unit 1x1 top face at mesh y = +0.5, built to
		// be scaled by its draw transform the way a water Part scales it. Emitting
		// it at unit scale left every cell covered by a single stud of water
		// sitting in the middle of a voxel_size cell, with the full wave amplitude
		// applied to it: neighbouring cells ended up at unrelated wave phases, so
		// the surface read as flickering fragments rather than a continuous body
		// of water.
		//
		// Y is deliberately left unscaled. The waves displace along Y in world
		// units, and scaling Y would change how far they travel.
		translate := [16]f32{
			vs, 0, 0, 0,
			0, 1, 0, 0,
			0, 0, vs, 0,
			(f32(key.x) + 0.5) * vs,
			surface_y,
			(f32(key.z) + 0.5) * vs,
			1,
		}

		append(&service.draw_items, kineffi.KineFilamentDrawItem{
			mesh         = service.surface_mesh,
			tex          = nil,
			transform    = translate,
			r            = color.R,
			g            = color.G,
			b            = color.B,
			param1       = param1,
			param2       = param2,
			param3       = param3,
			transmission = transmission,
			materialKind = kind,
			flags        = u32(kineffi.KINE_FILAMENT_DRAW_CULLING),
		})
	}
}

terrain_refresh_draw_items :: proc(service: ^Terrain) {
	delete(service.draw_items)
	service.draw_items = make([dynamic]kineffi.KineFilamentDrawItem, 0, 64)

	identity := [16]f32{
		1, 0, 0, 0,
		0, 1, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}

	terrain_append_surface_draw_items(service)

	for _, chunk in service.chunks {
		if chunk == nil {
			continue
		}
		for mesh in chunk.meshes {
			if mesh == nil {
				continue
			}
			append(&service.draw_items, kineffi.KineFilamentDrawItem{
				mesh         = mesh,
				tex          = service.texture_set,
				transform    = identity,
				r            = 1,
				g            = 1,
				b            = 1,
				param1       = 0.9,  // roughness
				param2       = 0,
				param3       = 0.25, // triplanar tile scale
				transmission = 0,
				materialKind = kineffi.KINE_MAT_TERRAIN,
				flags = u32(
					kineffi.KINE_FILAMENT_DRAW_CAST_SHADOWS |
					kineffi.KINE_FILAMENT_DRAW_RECEIVE_SHADOWS |
					kineffi.KINE_FILAMENT_DRAW_CULLING,
				),
			})
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

Terrain_Prepare_3D :: proc(
	service: ^Terrain,
	renderer: ^classes.Renderer_Object,
) {
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

	rebuilt := 0
	queue_len := len(service.dirty_queue)
	for service.dirty_head < queue_len && rebuilt < TERRAIN_REBUILDS_PER_FRAME {
		key := service.dirty_queue[service.dirty_head]
		service.dirty_head += 1
		delete_key(&service.dirty_lookup, key)

		if chunk, ok := service.chunks[key]; ok && chunk != nil && chunk.dirty {
			terrain_rebuild_chunk(service, chunk, renderer)
			rebuilt += 1
		}
	}

	if service.dirty_head >= len(service.dirty_queue) {
		terrain_reset_queue(service)
	}
}

Terrain_Render_3D :: proc(
	service: ^Terrain,
	renderer: ^classes.Renderer_Object,
) {
	if service == nil || renderer == nil || renderer.Filament == nil {
		return
	}
	if service.draw_dirty {
		terrain_refresh_draw_items(service)
	}
	if len(service.draw_items) == 0 {
		return
	}

	_ = kineffi.Kine_Filament_DrawMeshListVersioned(
		renderer.Filament,
		raw_data(service.draw_items),
		u32(len(service.draw_items)),
		TERRAIN_STREAM_ID,
		service.draw_version,
	)
}

// ---------------------------------------------------------------------------
// World / cell conversion
// ---------------------------------------------------------------------------

terrain_cell_from_world :: proc(service: ^Terrain, position: datatypes.Vector3) -> (int, int, int) {
	inv := 1.0 / service.voxel_size
	return int(math.floor(position.x*inv)),
	       int(math.floor(position.y*inv)),
	       int(math.floor(position.z*inv))
}

terrain_cell_center_world :: proc(service: ^Terrain, x, y, z: int) -> datatypes.Vector3 {
	return datatypes.Vector3{
		(f32(x)+0.5) * service.voxel_size,
		(f32(y)+0.5) * service.voxel_size,
		(f32(z)+0.5) * service.voxel_size,
	}
}

terrain_region_cells :: proc(
	region: datatypes.Region3,
	resolution: f32,
) -> (Terrain_Region_Cells, bool) {
	if resolution <= 0 || resolution != resolution {
		return {}, false
	}
	expanded, ok := datatypes.Region3_ExpandToGrid(region, resolution)
	if !ok {
		return {}, false
	}
	size := datatypes.Region3_Size(expanded)
	return Terrain_Region_Cells{
		origin     = expanded.Min,
		resolution = resolution,
		count_x    = max(0, int(math.round(size.x/resolution))),
		count_y    = max(0, int(math.round(size.y/resolution))),
		count_z    = max(0, int(math.round(size.z/resolution))),
	}, true
}

terrain_region_cell_center :: proc(
	cells: Terrain_Region_Cells,
	x, y, z: int,
) -> datatypes.Vector3 {
	return datatypes.Vector3{
		cells.origin.x + (f32(x)+0.5)*cells.resolution,
		cells.origin.y + (f32(y)+0.5)*cells.resolution,
		cells.origin.z + (f32(z)+0.5)*cells.resolution,
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

// ---------------------------------------------------------------------------
// Fill primitives
// ---------------------------------------------------------------------------

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
	for x in 0..<cells.count_x {
		for y in 0..<cells.count_y {
			for z in 0..<cells.count_z {
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
	return Terrain_Cell_Bounds{
		min_x = int(math.floor(world_min.x/vs)) - 1,
		max_x = int(math.floor(world_max.x/vs)) + 1,
		min_y = int(math.floor(world_min.y/vs)) - 1,
		max_y = int(math.floor(world_max.y/vs)) + 1,
		min_z = int(math.floor(world_min.z/vs)) - 1,
		max_z = int(math.floor(world_max.z/vs)) + 1,
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
	outside := math.sqrt(ox*ox + oy*oy + oz*oz)
	inside := min(max(qx, max(qy, qz)), 0)
	return outside + inside
}

terrain_sdf_eval :: proc(shape: Terrain_SDF_Shape, world: datatypes.Vector3) -> f32 {
	if shape.kind == .Sphere {
		return datatypes.Vec3_Magnitude(datatypes.Vec3_Subtract(world, shape.center)) - shape.radius
	}

	local := datatypes.CFrame_PointToObjectSpace(shape.cframe, world)
	switch shape.kind {
	case .Sphere:
		return 0
	case .Box:
		return terrain_sdf_box(local, shape.half)
	case .Cylinder:
		dx := math.sqrt(local.x*local.x + local.z*local.z) - shape.half.x
		dy := math.abs(local.y) - shape.half.y
		ox, oy := max(dx, 0), max(dy, 0)
		return min(max(dx, dy), 0) + math.sqrt(ox*ox + oy*oy)
	case .Wedge:
		slope := shape.half.y / shape.half.z
		plane := (local.y - shape.half.y + (local.z + shape.half.z)*slope) /
		         math.sqrt(1 + slope*slope)
		return max(terrain_sdf_box(local, shape.half), plane)
	}
	return 0
}

terrain_smooth_min :: proc(a, b, k: f32) -> f32 {
	if k <= 0 {
		return min(a, b)
	}
	h := max(k - math.abs(a-b), 0) / k
	return min(a, b) - h*h*k*0.25
}

terrain_smooth_max :: proc(a, b, k: f32) -> f32 {
	return -terrain_smooth_min(-a, -b, k)
}

terrain_sdf_bounds :: proc(
	service: ^Terrain,
	shape: Terrain_SDF_Shape,
	pad_cells: int,
) -> Terrain_Cell_Bounds {
	world_min, world_max: datatypes.Vector3

	if shape.kind == .Sphere {
		r := shape.radius
		world_min = datatypes.Vector3{shape.center.x-r, shape.center.y-r, shape.center.z-r}
		world_max = datatypes.Vector3{shape.center.x+r, shape.center.y+r, shape.center.z+r}
	} else {
		h := shape.half
		corners := [8]datatypes.Vector3{
			{-h.x, -h.y, -h.z}, {h.x, -h.y, -h.z}, {h.x, h.y, -h.z}, {-h.x, h.y, -h.z},
			{-h.x, -h.y, h.z},  {h.x, -h.y, h.z},  {h.x, h.y, h.z},  {-h.x, h.y, h.z},
		}
		world_min = datatypes.Vector3{math.INF_F32, math.INF_F32, math.INF_F32}
		world_max = datatypes.Vector3{-math.INF_F32, -math.INF_F32, -math.INF_F32}
		for corner in corners {
			world := datatypes.CFrame_Mul_Vector3(shape.cframe, corner)
			world_min = datatypes.Vec3_Min(world_min, world)
			world_max = datatypes.Vec3_Max(world_max, world)
		}
	}

	b := terrain_cell_bounds(service, world_min, world_max)
	b.min_x -= pad_cells
	b.max_x += pad_cells
	b.min_y -= pad_cells
	b.max_y += pad_cells
	b.min_z -= pad_cells
	b.max_z += pad_cells
	return b
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

	bounds := terrain_sdf_bounds(service, shape, int(math.ceil(k/vs)))

	for x in bounds.min_x..=bounds.max_x {
		for y in bounds.min_y..=bounds.max_y {
			for z in bounds.min_z..=bounds.max_z {
				center := terrain_cell_center_world(service, x, y, z)
				d_shape := terrain_sdf_eval(shape, center)

				if d_shape > vs + k {
					continue
				}

				cell, found := terrain_get_cell(service, x, y, z)
				if subtract && !found {
					continue
				}

				existing_occ := terrain_occupancy(service, x, y, z)
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

				new_occ := clamp(iso - d/vs, 0, 1)

				// A shape drawn with no blend is a hard volume, and hard volumes
				// have to land on the cell grid as fully solid or fully absent.
				// The density ramp exists to give blended and CSG'd shapes a
				// falloff, but applied to an unblended shape it leaves a
				// one-voxel skirt of half-density cells around the outside and
				// never reaches solid inside, because a shape no thicker than one
				// voxel has no cell centre deep enough inside it to saturate. That
				// rendered as a shell rather than the block that was asked for.
				if k <= 0 {
					if subtract {
						new_occ = d_shape <= 0 ? f32(0) : existing_occ
					} else {
						new_occ = d_shape <= 0 ? f32(1) : existing_occ
					}
				}

				if math.abs(new_occ-existing_occ) < 1.0e-4 && (!found || out_material == cell.material) {
					continue
				}

				water := f32(0)
				if found {
					water = cell.water
				}
				terrain_set_cell(service, x, y, z, new_occ, water, out_material)
			}
		}
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
	terrain_sdf_apply(service, Terrain_SDF_Shape{kind = .Sphere, center = center, radius = radius}, material)
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
	terrain_sdf_apply(service, Terrain_SDF_Shape{kind = .Box, cframe = cframe, half = half}, material)
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
	terrain_sdf_apply(service, Terrain_SDF_Shape{kind = .Cylinder, cframe = cframe, half = half}, material)
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
	terrain_sdf_apply(service, Terrain_SDF_Shape{kind = .Wedge, cframe = cframe, half = half}, material)
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
	for x in 0..<cells.count_x {
		for y in 0..<cells.count_y {
			for z in 0..<cells.count_z {
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

// ---------------------------------------------------------------------------
// Legacy procedural generation (engine extension, not Roblox API)
// ---------------------------------------------------------------------------

terrain_fade :: proc(t: f32) -> f32 {
	return t*t*t*(t*(t*6-15)+10)
}

terrain_lerp :: proc(a, b, t: f32) -> f32 {
	return a + (b-a)*t
}

terrain_hash :: proc(x, y, z: int, seed: i64) -> f32 {
	n := math.sin(
		f32(x)*127.1 + f32(y)*311.7 + f32(z)*74.3 + f32(seed)*19.19,
	) * 43758.5453
	return n - math.floor(n)
}

terrain_value_noise_3d :: proc(x, y, z: f32, seed: i64) -> f32 {
	ix, iy, iz := int(math.floor(x)), int(math.floor(y)), int(math.floor(z))
	fx, fy, fz := x-f32(ix), y-f32(iy), z-f32(iz)
	ux, uy, uz := terrain_fade(fx), terrain_fade(fy), terrain_fade(fz)

	n000 := terrain_hash(ix,   iy,   iz,   seed)
	n100 := terrain_hash(ix+1, iy,   iz,   seed)
	n010 := terrain_hash(ix,   iy+1, iz,   seed)
	n110 := terrain_hash(ix+1, iy+1, iz,   seed)
	n001 := terrain_hash(ix,   iy,   iz+1, seed)
	n101 := terrain_hash(ix+1, iy,   iz+1, seed)
	n011 := terrain_hash(ix,   iy+1, iz+1, seed)
	n111 := terrain_hash(ix+1, iy+1, iz+1, seed)

	x00 := terrain_lerp(n000, n100, ux)
	x10 := terrain_lerp(n010, n110, ux)
	x01 := terrain_lerp(n001, n101, ux)
	x11 := terrain_lerp(n011, n111, ux)
	y0 := terrain_lerp(x00, x10, uy)
	y1 := terrain_lerp(x01, x11, uy)
	return terrain_lerp(y0, y1, uz)
}

terrain_fbm :: proc(
	x, y, z: f32,
	octaves: int,
	frequency, amplitude: f32,
	seed: i64,
) -> f32 {
	value, total: f32
	freq := frequency
	amp := amplitude
	for octave in 0..<octaves {
		value += terrain_value_noise_3d(x*freq, y*freq, z*freq, seed+i64(octave)*7919) * amp
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
	return Terrain_Fill_Options{
		terrain_type = .Hills,
		caves        = true,
		seed         = 49297,
		noise_scale  = 1,
		roughness    = 1,
		cave_density = 1,
		cave_size    = 1,
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
	for i in 0..<len(a) {
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

	for x in pos_x-width..=pos_x+width {
		for z in pos_z-width..=pos_z+width {
			height_offset: f32
			mountain_height: f32

			switch options.terrain_type {
			case .Flat:
			case .Hills:
				n := terrain_fbm(f32(x), 0, f32(z), 4, 0.035*options.noise_scale, 1, options.seed)
				height_offset = (n-0.5) * f32(height) * 0.8 * options.roughness
			case .Mountains:
				base := terrain_fbm(f32(x), 0, f32(z), 5, 0.03*options.noise_scale, 1, options.seed)
				ridge1 := 1 - math.abs(terrain_fbm(f32(x), 10, f32(z), 4, 0.06*options.noise_scale, 1, options.seed+17)*2-1)
				ridge2 := 1 - math.abs(terrain_fbm(f32(x), 20, f32(z), 3, 0.12*options.noise_scale, 1, options.seed+31)*2-1)
				ridge1 *= ridge1
				ridge2 *= ridge2
				mountain_height = (base*0.4 + ridge1*0.4 + ridge2*0.2) * options.roughness
				height_offset = mountain_height * f32(height) * 1.4
			}

			surface_y := f32(pos_y+height) + height_offset
			for y in pos_y..=pos_y+height*2+10 {
				depth := surface_y - f32(y)
				surface_noise: f32
				if options.terrain_type != .Flat && options.roughness > 0 {
					surface_noise = (
						terrain_fbm(f32(x), f32(y), f32(z), 4, 0.08*options.noise_scale, 1, options.seed+101)*4 - 2
					) * options.roughness
				}

				density := clamp(depth/5 + surface_noise*0.3, 0, 1)

				if options.caves && options.cave_density > 0 && density > 0 && depth > 3 {
					cave_frequency := 0.055 * options.noise_scale / options.cave_size
					cave := terrain_fbm(f32(x), f32(y), f32(z), 3, cave_frequency, 1, options.seed+4049)
					threshold := clamp(0.78-options.cave_density*0.07, 0.48, 0.86)
					if cave > threshold {
						carve := clamp((cave-threshold)/0.12, 0, 1)
						density *= 1-carve
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
				} else if depth > 2 && options.terrain_type == .Mountains && height_offset > f32(height)*0.3 {
					material = .Slate
				}

				terrain_set_cell(service, x, y, z, density, 0, material)
			}
		}
	}
}

// ---------------------------------------------------------------------------
// Region read / write channels
// ---------------------------------------------------------------------------

terrain_read_3d_value :: proc(L: ^vm.State, table_index, x, y, z: int) -> bool {
	if !vm.IsTable(L, table_index) {
		return false
	}
	_ = vm.RawGetIndex(L, table_index, x+1)
	if !vm.IsTable(L, -1) {
		return false
	}
	_ = vm.RawGetIndex(L, -1, y+1)
	if !vm.IsTable(L, -1) {
		return false
	}
	_ = vm.RawGetIndex(L, -1, z+1)
	return !vm.IsNoneOrNil(L, -1)
}

terrain_push_occupancy_grid :: proc(
	L: ^vm.State,
	service: ^Terrain,
	cells: Terrain_Region_Cells,
	water: bool,
) {
	vm.NewTable(L, cells.count_x)
	for x in 0..<cells.count_x {
		vm.NewTable(L, cells.count_y)
		for y in 0..<cells.count_y {
			vm.NewTable(L, cells.count_z)
			for z in 0..<cells.count_z {
				center := terrain_region_cell_center(cells, x, y, z)
				cx, cy, cz := terrain_cell_from_world(service, center)
				value := water ? terrain_water(service, cx, cy, cz) : terrain_occupancy(service, cx, cy, cz)
				vm.PushNumber(L, f64(value))
				vm.SetArrayValue(L, -2, z+1)
			}
			vm.SetArrayValue(L, -2, y+1)
		}
		vm.SetArrayValue(L, -2, x+1)
	}
}

terrain_push_material_grid :: proc(
	L: ^vm.State,
	service: ^Terrain,
	cells: Terrain_Region_Cells,
	enum_registry: ^enums.Registry,
) {
	vm.NewTable(L, cells.count_x)
	for x in 0..<cells.count_x {
		vm.NewTable(L, cells.count_y)
		for y in 0..<cells.count_y {
			vm.NewTable(L, cells.count_z)
			for z in 0..<cells.count_z {
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
				vm.SetArrayValue(L, -2, z+1)
			}
			vm.SetArrayValue(L, -2, y+1)
		}
		vm.SetArrayValue(L, -2, x+1)
	}
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

terrain_clear :: proc(service: ^Terrain, renderer: ^classes.Renderer_Object) {
	for _, chunk in service.chunks {
		if chunk == nil {
			continue
		}
		terrain_destroy_chunk_meshes(chunk, renderer)
		free(chunk)
	}

	delete(service.voxels)
	delete(service.chunks)
	delete(service.draw_items)

	service.voxels = make(map[Terrain_Voxel_Key]Terrain_Cell)
	service.chunks = make(map[Terrain_Chunk_Key]^Terrain_Chunk)
	service.draw_items = make([dynamic]kineffi.KineFilamentDrawItem, 0, 64)

	service.dirty_head = 0
	clear(&service.dirty_queue)
	clear(&service.dirty_lookup)

	service.draw_dirty = true
	service.draw_version += 1
	service.geometry_version += 1

	// Wiping the map is a change no delta can express, so every peer is told to
	// start over rather than being handed a list of individual removals.
	service.change_serial += 1
	service.dirty_epoch += 1
	clear(&service.replication_dirty)
}

// ---------------------------------------------------------------------------
// Save-file persistence
// ---------------------------------------------------------------------------

// Terrain_Write_Kine_Table copies the map's voxel grid and terrain settings into
// a .kine terrain table. out must be an unowned table the caller destroys.
//
// The settings are written even when there are no voxels, because a map is
// allowed to save a custom voxel size or palette and load it into an otherwise
// empty grid.
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

	for material, colour in service.material_colors {
		if out.material_colours == nil {
			out.material_colours = make(map[u32]datatypes.Color3)
		}
		out.material_colours[u32(material)] = colour
	}

	// The reserve is the map's own cell count, so a large map does not spend the
	// save repeatedly growing the table.
	out.cells = make([dynamic]serializer.Kine_Terrain_Cell, 0, len(service.voxels))
	for key, cell in service.voxels {
		append(&out.cells, serializer.Kine_Terrain_Cell {
			x = i32(key.x),
			y = i32(key.y),
			z = i32(key.z),
			material = u32(cell.material),
			occupancy = cell.occupancy,
			water = cell.water,
		})
	}
}

// Terrain_Read_Kine_Table replaces the service's grid with a saved one.
//
// The grid is written through terrain_set_cell rather than poked into the voxel
// map directly, so every restored voxel bumps geometry_version and dirties its
// chunk and face neighbours. That is what makes the Jolt collider rebuild and the
// mesher regenerate without any extra work here; touching the map directly
// would restore voxels that collision and rendering never learn about.
Terrain_Read_Kine_Table :: proc(
	service: ^Terrain,
	renderer: ^classes.Renderer_Object,
	table: ^serializer.Kine_Terrain,
) -> bool {
	if service == nil || table == nil || !(table.voxel_size > 0) || !(table.iso_level > 0) {
		return false
	}

	// Whatever was in the world belongs to the map that is being replaced, so it
	// is wiped before the new grid goes in.
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
	service.voxels = make(map[Terrain_Voxel_Key]Terrain_Cell)
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

terrain_service_destroy :: proc(
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
) {
	service := cast(^Terrain)object
	terrain_clear(service, renderer)

	delete(service.voxels)
	delete(service.chunks)
	delete(service.dirty_lookup)
	delete(service.dirty_queue)
	delete(service.draw_items)
	delete(service.material_colors)

	if service.texture_set != nil && service.texture_context != nil {
		_ = kineffi.Kine_Filament_DestroyTex(service.texture_context, service.texture_set)
	}
	service.texture_set = nil
	service.texture_context = nil

	terrain_destroy_surface_mesh(service)

	classes.Object_Destroy(object)
	free(service)
}

// ---------------------------------------------------------------------------
// Properties
// ---------------------------------------------------------------------------

terrain_push_material_colors :: proc(
	L: ^vm.State,
	service: ^Terrain,
	datatype_registry: ^datatypes.Registry,
) {
	vm.NewTable(L, 0, len(terrain_material_names))
	for index in 0..<len(terrain_material_names) {
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
		datatypes.Push_Region3int16(L, datatype_registry, TERRAIN_MAX_EXTENTS)
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
	// Engine extensions.
	case "VoxelSize":
		vm.PushNumber(L, f64(service.voxel_size))
	case "IsoLevel":
		vm.PushNumber(L, f64(service.iso_level))
	case "ChunkSize":
		vm.PushNumber(L, TERRAIN_CHUNK_SIZE)
	case "QueuedChunkCount":
		vm.PushNumber(L, f64(max(0, len(service.dirty_queue)-service.dirty_head)))
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

// ---------------------------------------------------------------------------
// Methods
// ---------------------------------------------------------------------------

terrain_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	service := cast(^Terrain)object

	switch method {
	case "Clear":
		terrain_clear(service, service.renderer)
		return 0, true

	case "CountCells":
		vm.PushNumber(L, f64(len(service.voxels)))
		return 1, true

	case "CellCornerToWorld":
		x := vm.ArgOptionalNumber(L, 2, 0)
		y := vm.ArgOptionalNumber(L, 3, 0)
		z := vm.ArgOptionalNumber(L, 4, 0)
		datatypes.Push_Vector3(L, datatypes.Vector3{
			f32(x)*service.voxel_size,
			f32(y)*service.voxel_size,
			f32(z)*service.voxel_size,
		})
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
		// Spiral outward through a bounded neighborhood for the nearest cell
		// matching the preference.
		for radius in 1..=TERRAIN_CHUNK_SIZE {
			for dx in -radius..=radius {
				for dy in -radius..=radius {
					for dz in -radius..=radius {
						nx, ny, nz := cx+dx, cy+dy, cz+dz
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
		for x in 0..<cells.count_x {
			for y in 0..<cells.count_y {
				for z in 0..<cells.count_z {
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
		for channel_index in 1..=channel_count {
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
		if vm.IsTable(L, -1) { occupancy_index = vm.StackTop(L) } else { vm.Pop(L) }
		_ = vm.GetField(L, 4, "SolidMaterial")
		if vm.IsTable(L, -1) { material_index = vm.StackTop(L) } else { vm.Pop(L) }
		_ = vm.GetField(L, 4, "LiquidOccupancy")
		if vm.IsTable(L, -1) { liquid_index = vm.StackTop(L) } else { vm.Pop(L) }
		loop_base := vm.StackTop(L)

		for x in 0..<cells.count_x {
			for y in 0..<cells.count_y {
				for z in 0..<cells.count_z {
					vm.SetStackTop(L, loop_base)
					center := terrain_region_cell_center(cells, x, y, z)
					cx, cy, cz := terrain_cell_from_world(service, center)

					occupancy := terrain_occupancy(service, cx, cy, cz)
					if occupancy_index > 0 && terrain_read_3d_value(L, occupancy_index, x, y, z) && vm.IsNumber(L, -1) {
						occupancy = clamp(f32(vm.ArgNumber(L, -1)), 0, 1)
					}
					vm.SetStackTop(L, loop_base)

					water := terrain_water(service, cx, cy, cz)
					if liquid_index > 0 && terrain_read_3d_value(L, liquid_index, x, y, z) && vm.IsNumber(L, -1) {
						water = clamp(f32(vm.ArgNumber(L, -1)), 0, 1)
					}
					vm.SetStackTop(L, loop_base)

					material := enums.Material.Grass
					if cell, found := terrain_get_cell(service, cx, cy, cz); found {
						material = cell.material
					}
					if material_index > 0 && terrain_read_3d_value(L, material_index, x, y, z) &&
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
		nx := max(0, int(region.Max.X)-int(region.Min.X))
		ny := max(0, int(region.Max.Y)-int(region.Min.Y))
		nz := max(0, int(region.Max.Z)-int(region.Min.Z))

		snapshot := datatypes.TerrainRegion_New(datatypes.Vector3int16{i16(nx), i16(ny), i16(nz)})
		for x in 0..<nx {
			for y in 0..<ny {
				for z in 0..<nz {
					index, ok := datatypes.TerrainRegion_Index(&snapshot, x, y, z)
					if !ok {
						continue
					}
					if cell, found := terrain_get_cell(
						service,
						int(region.Min.X)+x,
						int(region.Min.Y)+y,
						int(region.Min.Z)+z,
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
		for x in 0..<nx {
			for y in 0..<ny {
				for z in 0..<nz {
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
						terrain_erase_cell(service, int(corner.X)+x, int(corner.Y)+y, int(corner.Z)+z)
						continue
					}
					terrain_set_cell(
						service,
						int(corner.X)+x,
						int(corner.Y)+y,
						int(corner.Z)+z,
						occupancy,
						0,
						material,
					)
				}
			}
		}
		return 0, true

	// Deprecated members retained for API parity.
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
		for x in int(region.Min.X)..<int(region.Max.X) {
			for y in int(region.Min.Y)..<int(region.Max.Y) {
				for z in int(region.Min.Z)..<int(region.Max.Z) {
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

	// Engine extensions.
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
		properties = []string{
			"Decoration",
			"GrassLength",
			"IsSmooth",
			"MaterialColors",
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
