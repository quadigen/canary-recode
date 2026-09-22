package services

// wire:service global="terrain"

import "core:math"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import kineffi "../bindings"
import materials "../material"
import vm "../vm"

TERRAIN_CHUNK_SIZE             :: 16
TERRAIN_REBUILDS_PER_FRAME     :: 2
TERRAIN_MAX_VERTICES_PER_MESH :: 65532 // uint16 indices, kept divisible by 3
TERRAIN_STREAM_ID              :: u64(0x5445525241494E) // "TERRAIN"

Terrain_Class := classes.Class_Info{
	name   = "Terrain",
	parent = &Service_Class,
}

Terrain_Material :: enum u8 {
	Grass,
	Sand,
	Dirt,
	Slate,
	Stone,
	Concrete,
	Snow,
	SmoothPlastic,
	Water,
	Wood,
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

Terrain_Voxel :: struct {
	density:  f32,
	material: Terrain_Material,
}

Terrain_Chunk :: struct {
	key:    Terrain_Chunk_Key,
	dirty:  bool,
	meshes: [dynamic]^kineffi.KineFilamentMesh,
}

Terrain_Sample :: struct {
	position: datatypes.Vector3,
	density:  f32,
}

Terrain_Fill_Options :: struct {
	terrain_type:      Terrain_Type,
	caves:             bool,
	seed:              i64,
	noise_scale:       f32,
	roughness:         f32,
	cave_density:      f32,
	cave_size:         f32,
	material_override: Terrain_Material,
	has_material:      bool,
}

Terrain :: struct {
	using service: Service,

	voxels:       map[Terrain_Voxel_Key]Terrain_Voxel,
	chunks:       map[Terrain_Chunk_Key]^Terrain_Chunk,
	dirty_lookup: map[Terrain_Chunk_Key]bool,
	dirty_queue:  [dynamic]Terrain_Chunk_Key,
	dirty_head:   int,

	voxel_size: f32,
	iso_level:  f32,

	texture_set:     ^kineffi.KineFilamentTex,
	texture_context: ^kineffi.KineFilamentContext,
	draw_items:      [dynamic]kineffi.KineFilamentDrawItem,
	draw_dirty:      bool,
	draw_version:    u64,
	renderer:        ^classes.Renderer_Object,
}

TERRAIN_TETRAHEDRA := [6][4]int{
	{0, 5, 1, 6},
	{0, 1, 2, 6},
	{0, 2, 3, 6},
	{0, 3, 7, 6},
	{0, 7, 4, 6},
	{0, 4, 5, 6},
}

terrain_ascii_lower :: proc(c: u8) -> u8 {
	if c >= 'A' && c <= 'Z' {
		return c + 32
	}
	return c
}

terrain_equal_fold :: proc(a, b: string) -> bool {
	if len(a) != len(b) {
		return false
	}
	for i in 0..<len(a) {
		if terrain_ascii_lower(a[i]) != terrain_ascii_lower(b[i]) {
			return false
		}
	}
	return true
}

terrain_material_from_string :: proc(value: string) -> (Terrain_Material, bool) {
	switch {
	case terrain_equal_fold(value, "grass"):
		return .Grass, true
	case terrain_equal_fold(value, "sand"):
		return .Sand, true
	case terrain_equal_fold(value, "dirt"):
		return .Dirt, true
	case terrain_equal_fold(value, "slate"):
		return .Slate, true
	case terrain_equal_fold(value, "stone"):
		return .Stone, true
	case terrain_equal_fold(value, "concrete"):
		return .Concrete, true
	case terrain_equal_fold(value, "snow"):
		return .Snow, true
	case terrain_equal_fold(value, "smoothplastic"):
		return .SmoothPlastic, true
	case terrain_equal_fold(value, "water"):
		return .Water, true
	case terrain_equal_fold(value, "wood"):
		return .Wood, true
	}
	return .Grass, false
}

terrain_material_name :: proc(material: Terrain_Material) -> string {
	switch material {
	case .Grass:         return "grass"
	case .Sand:          return "sand"
	case .Dirt:          return "dirt"
	case .Slate:         return "slate"
	case .Stone:         return "stone"
	case .Concrete:      return "concrete"
	case .Snow:          return "snow"
	case .SmoothPlastic: return "smoothplastic"
	case .Water:         return "water"
	case .Wood:          return "wood"
	}
	return "grass"
}

terrain_material_layer :: proc(material: Terrain_Material) -> int {
	switch material {
	case .Grass:                  return 0
	case .Sand, .Dirt:            return 1
	case .Slate, .Stone:          return 2
	case .Concrete:               return 3
	case .Snow, .SmoothPlastic,
	     .Water:                  return 4
	case .Wood:                   return 5
	}
	return 0
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
	key := terrain_chunk_key_for_voxel(x, y, z)
	terrain_mark_chunk_dirty(service, key)

	lx := terrain_floor_mod(x, TERRAIN_CHUNK_SIZE)
	ly := terrain_floor_mod(y, TERRAIN_CHUNK_SIZE)
	lz := terrain_floor_mod(z, TERRAIN_CHUNK_SIZE)

	// Border samples affect a neighboring chunk's last/first marching cell too.
	if lx == 0                         { terrain_mark_chunk_dirty(service, {key.x-1, key.y, key.z}) }
	if lx == TERRAIN_CHUNK_SIZE-1      { terrain_mark_chunk_dirty(service, {key.x+1, key.y, key.z}) }
	if ly == 0                         { terrain_mark_chunk_dirty(service, {key.x, key.y-1, key.z}) }
	if ly == TERRAIN_CHUNK_SIZE-1      { terrain_mark_chunk_dirty(service, {key.x, key.y+1, key.z}) }
	if lz == 0                         { terrain_mark_chunk_dirty(service, {key.x, key.y, key.z-1}) }
	if lz == TERRAIN_CHUNK_SIZE-1      { terrain_mark_chunk_dirty(service, {key.x, key.y, key.z+1}) }
}

terrain_get_voxel :: proc(service: ^Terrain, x, y, z: int) -> (Terrain_Voxel, bool) {
	return service.voxels[Terrain_Voxel_Key{x, y, z}]
}

terrain_density :: proc(service: ^Terrain, x, y, z: int) -> f32 {
	if voxel, ok := terrain_get_voxel(service, x, y, z); ok {
		return voxel.density
	}
	return 0
}

terrain_set_voxel_native :: proc(
	service: ^Terrain,
	x, y, z: int,
	density: f32,
	material: Terrain_Material,
) {
	key := Terrain_Voxel_Key{x, y, z}
	_, existed := service.voxels[key]

	if density <= 0 {
		if !existed {
			return
		}
		delete_key(&service.voxels, key)
		terrain_mark_voxel_dirty(service, x, y, z)
		return
	}

	service.voxels[key] = Terrain_Voxel{
		density  = clamp(density, 0, 1),
		material = material,
	}
	terrain_mark_voxel_dirty(service, x, y, z)
}

terrain_mark_all_dirty :: proc(service: ^Terrain) {
	for key, _ in service.chunks {
		terrain_mark_chunk_dirty(service, key)
	}
}

terrain_sample_density :: proc(service: ^Terrain, voxel_position: datatypes.Vector3) -> f32 {
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
				result += terrain_density(service, x0+dx, y0+dy, z0+dz) * wx * wy * wz
			}
		}
	}
	return result
}

terrain_normal_at_world :: proc(service: ^Terrain, world: datatypes.Vector3) -> datatypes.Vector3 {
	inv_voxel := 1.0 / service.voxel_size
	p := datatypes.Vector3{world.x*inv_voxel, world.y*inv_voxel, world.z*inv_voxel}
	eps: f32 = 0.5

	dx := terrain_sample_density(service, {p.x-eps, p.y, p.z}) -
	      terrain_sample_density(service, {p.x+eps, p.y, p.z})
	dy := terrain_sample_density(service, {p.x, p.y-eps, p.z}) -
	      terrain_sample_density(service, {p.x, p.y+eps, p.z})
	dz := terrain_sample_density(service, {p.x, p.y, p.z-eps}) -
	      terrain_sample_density(service, {p.x, p.y, p.z+eps})

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
				if voxel, ok := terrain_get_voxel(service, x0+dx, y0+dy, z0+dz); ok && voxel.density > 0 {
					weight := wx * wy * wz * voxel.density
					weights[terrain_material_layer(voxel.material)] += weight
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

terrain_interpolate :: proc(service: ^Terrain, a, b: Terrain_Sample) -> datatypes.Vector3 {
	delta := b.density - a.density
	t: f32 = 0.5
	if math.abs(delta) > 1.0e-6 {
		t = clamp((service.iso_level-a.density)/delta, 0, 1)
	}
	return datatypes.Vec3_Lerp(a.position, b.position, t)
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

terrain_emit_tetrahedron :: proc(
	service: ^Terrain,
	samples: [8]Terrain_Sample,
	tetrahedron: [4]int,
	vertex_data: ^[dynamic]f32,
	material_weights: ^[dynamic]f32,
) {
	inside: [4]int
	outside: [4]int
	inside_count, outside_count: int

	for vertex_index in tetrahedron {
		if samples[vertex_index].density > service.iso_level {
			inside[inside_count] = vertex_index
			inside_count += 1
		} else {
			outside[outside_count] = vertex_index
			outside_count += 1
		}
	}

	if inside_count == 0 || inside_count == 4 {
		return
	}

	if inside_count == 1 {
		i := inside[0]
		p0 := terrain_interpolate(service, samples[i], samples[outside[0]])
		p1 := terrain_interpolate(service, samples[i], samples[outside[1]])
		p2 := terrain_interpolate(service, samples[i], samples[outside[2]])
		terrain_emit_triangle(service, vertex_data, material_weights, p0, p1, p2)
		return
	}

	if inside_count == 3 {
		o := outside[0]
		p0 := terrain_interpolate(service, samples[o], samples[inside[0]])
		p1 := terrain_interpolate(service, samples[o], samples[inside[1]])
		p2 := terrain_interpolate(service, samples[o], samples[inside[2]])
		terrain_emit_triangle(service, vertex_data, material_weights, p0, p1, p2)
		return
	}

	// Two inside + two outside => a quad, triangulated into two triangles.
	i0, i1 := inside[0], inside[1]
	o0, o1 := outside[0], outside[1]
	a := terrain_interpolate(service, samples[i0], samples[o0])
	b := terrain_interpolate(service, samples[i0], samples[o1])
	c := terrain_interpolate(service, samples[i1], samples[o0])
	d := terrain_interpolate(service, samples[i1], samples[o1])
	terrain_emit_triangle(service, vertex_data, material_weights, a, c, b)
	terrain_emit_triangle(service, vertex_data, material_weights, b, c, d)
}

terrain_march_cell :: proc(
	service: ^Terrain,
	x, y, z: int,
	vertex_data: ^[dynamic]f32,
	material_weights: ^[dynamic]f32,
) {
	vs := service.voxel_size
	x0, y0, z0 := f32(x)*vs, f32(y)*vs, f32(z)*vs
	x1, y1, z1 := x0+vs, y0+vs, z0+vs

	samples := [8]Terrain_Sample{
		{{x0, y0, z0}, terrain_density(service, x,   y,   z)},
		{{x1, y0, z0}, terrain_density(service, x+1, y,   z)},
		{{x1, y0, z1}, terrain_density(service, x+1, y,   z+1)},
		{{x0, y0, z1}, terrain_density(service, x,   y,   z+1)},
		{{x0, y1, z0}, terrain_density(service, x,   y+1, z)},
		{{x1, y1, z0}, terrain_density(service, x+1, y+1, z)},
		{{x1, y1, z1}, terrain_density(service, x+1, y+1, z+1)},
		{{x0, y1, z1}, terrain_density(service, x,   y+1, z+1)},
	}

	all_outside := true
	all_inside := true
	for sample in samples {
		inside := sample.density > service.iso_level
		all_outside = all_outside && !inside
		all_inside = all_inside && inside
	}
	if all_outside || all_inside {
		return
	}

	for tetrahedron in TERRAIN_TETRAHEDRA {
		terrain_emit_tetrahedron(service, samples, tetrahedron, vertex_data, material_weights)
	}
}

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

	x0 := chunk.key.x * TERRAIN_CHUNK_SIZE
	y0 := chunk.key.y * TERRAIN_CHUNK_SIZE
	z0 := chunk.key.z * TERRAIN_CHUNK_SIZE

	for x in x0..<x0+TERRAIN_CHUNK_SIZE {
		for y in y0..<y0+TERRAIN_CHUNK_SIZE {
			for z in z0..<z0+TERRAIN_CHUNK_SIZE {
				terrain_march_cell(service, x, y, z, &vertex_data, &material_weights)
			}
		}
	}

	terrain_upload_chunk_meshes(chunk, renderer, vertex_data[:], material_weights[:])
	chunk.dirty = false
	service.draw_dirty = true
}

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

terrain_refresh_draw_items :: proc(service: ^Terrain) {
	delete(service.draw_items)
	service.draw_items = make([dynamic]kineffi.KineFilamentDrawItem, 0, 64)

	identity := [16]f32{
		1, 0, 0, 0,
		0, 1, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}

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
	delete(service.dirty_queue)
	service.dirty_queue = make([dynamic]Terrain_Chunk_Key, 0, 64)
	service.dirty_head = 0
}

Terrain_Prepare_3D :: proc(
	service: ^Terrain,
	renderer: ^classes.Renderer_Object,
) {
	if service == nil || renderer == nil || renderer.Filament == nil {
		return
	}

	service.renderer = renderer
	terrain_ensure_texture_set(service, renderer)

	rebuilt := 0
	for service.dirty_head < len(service.dirty_queue) && rebuilt < TERRAIN_REBUILDS_PER_FRAME {
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

terrain_read_fill_options :: proc(L: ^vm.State, table_index: int) -> Terrain_Fill_Options {
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

	if material_name, ok := terrain_table_string(L, table_index, "material"); ok &&
	   !terrain_equal_fold(material_name, "") &&
	   !terrain_equal_fold(material_name, "auto") {
		if material, material_ok := terrain_material_from_string(material_name); material_ok {
			options.material_override = material
			options.has_material = true
		}
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

			// Native version uses deterministic volumetric cave noise instead of
			// Canary's random-walk sphere carving. It is cheaper and chunk-friendly.
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
				terrain_set_voxel_native(service, x, y, z, 0, .Grass)
				continue
			}

			material := Terrain_Material.Grass
			if options.has_material {
				material = options.material_override
			} else if depth > 12 {
				material = .Concrete
			} else if depth > 4 {
				material = .Dirt
			} else if depth > 2 && options.terrain_type == .Mountains && height_offset > f32(height)*0.6 {
				material = .Snow
			} else if depth > 2 && options.terrain_type == .Mountains && height_offset > f32(height)*0.3 {
				material = .Stone
			}

			terrain_set_voxel_native(service, x, y, z, density, material)
		}
		}
	}
}

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
	delete(service.dirty_lookup)
	delete(service.dirty_queue)
	delete(service.draw_items)

	service.voxels = make(map[Terrain_Voxel_Key]Terrain_Voxel)
	service.chunks = make(map[Terrain_Chunk_Key]^Terrain_Chunk)
	service.dirty_lookup = make(map[Terrain_Chunk_Key]bool)
	service.dirty_queue = make([dynamic]Terrain_Chunk_Key, 0, 64)
	service.draw_items = make([dynamic]kineffi.KineFilamentDrawItem, 0, 64)
	service.dirty_head = 0
	service.draw_dirty = true
	service.draw_version += 1
}

terrain_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Terrain)
	service.service = Service_Init(&Terrain_Class, "Terrain", data_model)
	service.voxels = make(map[Terrain_Voxel_Key]Terrain_Voxel)
	service.chunks = make(map[Terrain_Chunk_Key]^Terrain_Chunk)
	service.dirty_lookup = make(map[Terrain_Chunk_Key]bool)
	service.dirty_queue = make([dynamic]Terrain_Chunk_Key, 0, 64)
	service.draw_items = make([dynamic]kineffi.KineFilamentDrawItem, 0, 64)
	service.voxel_size = 2
	service.iso_level = 0.2
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

	// terrain_clear recreates containers because it is also the public Clear path.
	delete(service.voxels)
	delete(service.chunks)
	delete(service.dirty_lookup)
	delete(service.dirty_queue)
	delete(service.draw_items)

	if service.texture_set != nil && service.texture_context != nil {
		_ = kineffi.Kine_Filament_DestroyTex(service.texture_context, service.texture_set)
	}
	service.texture_set = nil
	service.texture_context = nil

	classes.Object_Destroy(object)
	free(service)
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
	case "VoxelSize":
		vm.PushNumber(L, f64(service.voxel_size))
	case "IsoLevel":
		vm.PushNumber(L, f64(service.iso_level))
	case "ChunkSize":
		vm.PushNumber(L, TERRAIN_CHUNK_SIZE)
	case "QueuedChunkCount":
		vm.PushNumber(L, f64(max(0, len(service.dirty_queue)-service.dirty_head)))
	case "SetVoxel", "GetVoxel", "FillBlock", "Fill", "Clear", "GenerateMesh":
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
) -> (i32, bool) {
	service := cast(^Terrain)object

	switch method {
	case "SetVoxel":
		x := int(vm.ArgInteger(L, 2))
		y := int(vm.ArgInteger(L, 3))
		z := int(vm.ArgInteger(L, 4))
		density := clamp(f32(vm.ArgNumber(L, 5)), 0, 1)
		material := Terrain_Material.Grass
		if !vm.IsNoneOrNil(L, 6) {
			name := vm.ArgString(L, 6)
			parsed, ok := terrain_material_from_string(name)
			if !ok {
				return vm.RaiseError(L, "unknown terrain material"), true
			}
			material = parsed
		}
		terrain_set_voxel_native(service, x, y, z, density, material)
		return 0, true

	case "GetVoxel":
		x := int(vm.ArgInteger(L, 2))
		y := int(vm.ArgInteger(L, 3))
		z := int(vm.ArgInteger(L, 4))
		voxel, ok := terrain_get_voxel(service, x, y, z)
		if !ok {
			vm.PushNil(L)
			return 1, true
		}
		vm.NewTable(L, 0, 2)
		vm.PushNumber(L, f64(voxel.density))
		vm.SetField(L, -2, "density")
		vm.PushString(L, terrain_material_name(voxel.material))
		vm.SetField(L, -2, "material")
		return 1, true

	case "FillBlock":
		if datatype_registry == nil {
			return vm.RaiseError(L, "datatype registry is unavailable"), true
		}
		min_pos := datatypes.Arg_Vector3(L, 2)
		max_pos := datatypes.Arg_Vector3(L, 3)
		if !vm.IsTable(L, 4) {
			return vm.RaiseError(L, "FillBlock expects a block table"), true
		}
		density := clamp(f32(terrain_table_number(L, 4, "density", 1)), 0, 1)
		material := Terrain_Material.Grass
		if material_name, has_material := terrain_table_string(L, 4, "material"); has_material {
			parsed, ok := terrain_material_from_string(material_name)
			if !ok {
				return vm.RaiseError(L, "unknown terrain material"), true
			}
			material = parsed
		}

		min_x, min_y, min_z := int(math.floor(min_pos.x)), int(math.floor(min_pos.y)), int(math.floor(min_pos.z))
		max_x, max_y, max_z := int(math.floor(max_pos.x)), int(math.floor(max_pos.y)), int(math.floor(max_pos.z))
		for x in min_x..=max_x {
			for y in min_y..=max_y {
				for z in min_z..=max_z {
					terrain_set_voxel_native(service, x, y, z, density, material)
				}
			}
		}
		return 0, true

	case "Fill":
		pos_x := int(math.floor(vm.ArgOptionalNumber(L, 2, 0)))
		pos_y := int(math.floor(vm.ArgOptionalNumber(L, 3, 0)))
		pos_z := int(math.floor(vm.ArgOptionalNumber(L, 4, 0)))
		width := max(1, int(math.floor(vm.ArgOptionalNumber(L, 5, 20))))
		height := max(1, int(math.floor(vm.ArgOptionalNumber(L, 6, 20))))
		options := terrain_default_fill_options()
		if vm.IsTable(L, 7) {
			options = terrain_read_fill_options(L, 7)
		}
		terrain_fill_generated(service, pos_x, pos_y, pos_z, width, height, options)
		return 0, true

	case "Clear":
		terrain_clear(service, service.renderer)
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
			"VoxelSize",
			"IsoLevel",
			"ChunkSize",
			"QueuedChunkCount",
		},
	)
}
