package services

import enums "../enum"
import tracy "../util/odin-tracy"
import vm "../vm"
import "core:math"
import "core:slice"
import "core:sync"
import "core:thread"

TERRAIN_GEN_COLUMN_DIM :: TERRAIN_CHUNK_SIZE + 2
TERRAIN_GEN_COMMIT_PER_FRAME :: 48
// Noise frequencies below were tuned at 4 studs per unit; this keeps them world-space.
TERRAIN_GEN_REF :: f32(4)
// Swap for your platform's core count (e.g. os.get_processor_core_count()) if you prefer.
TERRAIN_GEN_DEFAULT_WORKERS :: #config(KINE_TERRAIN_GEN_WORKERS, 4)

Terrain_Biome :: enum u8 {
	Ocean,
	Beach,
	Plains,
	Forest,
	Swamp,
	Desert,
	Tundra,
	Alpine,
	Snow,
}

// Heights and levels are in STUDS.
Terrain_Chunk_Gen_Options :: struct {
	seed:            i64,
	voxel_size:      f32, // studs per voxel; <= 0 keeps the service's current size
	flat_shading:    Maybe(bool), // unset keeps the service's current setting
	sea_level:       f32,
	base_height:     f32, // continent relief: ocean floor .. inland plateau
	mountain_height: f32,
	hill_height:     f32,
	snow_line:       f32, // studs above sea level at temperature 0.5
	min_y, max_y:    f32, // vertical extent generated
	feature_scale:   f32, // frequency multiplier (bigger = smaller features)
	cave_size:       f32,
	caves:           bool,
	overhangs:       bool,
	biomes:          bool,
	workers:         int,

	// Filled in by Terrain_Generate_Chunks (don't set).
	min_chunk_y:     int,
	max_chunk_y:     int,
}

Terrain_Gen_Column :: struct {
	height:   f32, // reference units (studs / TERRAIN_GEN_REF)
	mountain: f32,
	temp:     f32,
	moist:    f32,
	gx, gz:   f32,
	biome:    Terrain_Biome,
}

Terrain_Gen_Columns :: [TERRAIN_GEN_COLUMN_DIM * TERRAIN_GEN_COLUMN_DIM]Terrain_Gen_Column

Terrain_Gen_Column_Job :: struct {
	cx, cz: int,
	dist2:  int,
	ready:  int, // atomic; 1 once `chunks` is final
	chunks: [dynamic]^Terrain_Chunk_Data, // index = cy - min_chunk_y, nil = empty air
}

Terrain_Chunk_Generation :: struct {
	options:      Terrain_Chunk_Gen_Options,
	jobs:         []Terrain_Gen_Column_Job,
	workers:      [dynamic]^thread.Thread,
	next_job:     int, // atomic
	cancel:       int, // atomic
	commit_job:   int,
	commit_chunk: int,
}

terrain_default_chunk_gen_options :: proc() -> Terrain_Chunk_Gen_Options {
	return Terrain_Chunk_Gen_Options {
		seed = 49297,
		sea_level = 48,
		base_height = 200,
		mountain_height = 360,
		hill_height = 56,
		snow_line = 220,
		min_y = -192,
		max_y = 704,
		feature_scale = 1,
		cave_size = 1,
		caves = true,
		overhangs = true,
		biomes = true,
		workers = TERRAIN_GEN_DEFAULT_WORKERS,
	}
}

// ---------------------------------------------------------------------------------------------
// Noise helpers
// ---------------------------------------------------------------------------------------------

terrain_value_noise_2d :: proc(x, z: f32, seed: i64) -> f32 {
	ix, iz := int(math.floor(x)), int(math.floor(z))
	ux, uz := terrain_fade(x - f32(ix)), terrain_fade(z - f32(iz))
	a := terrain_lerp(terrain_hash(ix, 0, iz, seed), terrain_hash(ix + 1, 0, iz, seed), ux)
	b := terrain_lerp(terrain_hash(ix, 0, iz + 1, seed), terrain_hash(ix + 1, 0, iz + 1, seed), ux)
	return terrain_lerp(a, b, uz)
}

// Normalised 0..1 fractal noise, lacunarity 2.
terrain_fbm2 :: proc(x, z: f32, octaves: int, frequency: f32, seed: i64) -> f32 {
	sum, total: f32
	freq, amp := frequency, f32(1)
	for octave in 0 ..< octaves {
		sum += terrain_value_noise_2d(x * freq, z * freq, seed + i64(octave) * 7919) * amp
		total += amp
		freq *= 2
		amp *= 0.5
	}
	return sum / total
}

// Ridged multifractal with softened creases (no hard V at the crest). 0..1.
terrain_ridged2 :: proc(x, z: f32, octaves: int, frequency: f32, seed: i64) -> f32 {
	sum, total: f32
	freq, amp := frequency, f32(1)
	for octave in 0 ..< octaves {
		n := terrain_value_noise_2d(x * freq, z * freq, seed + i64(octave) * 104729)
		t := 2 * n - 1
		r := clamp(1 - math.sqrt(t * t + 0.02) + 0.141, 0, 1)
		sum += r * r * amp
		total += amp
		freq *= 2.03
		amp *= 0.5
	}
	return sum / total
}

terrain_stretch :: proc(v, k: f32) -> f32 {
	return clamp((v - 0.5) * k + 0.5, 0, 1)
}

terrain_smoothstep :: proc(edge0, edge1, v: f32) -> f32 {
	t := clamp((v - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
}

// ---------------------------------------------------------------------------------------------
// Heightfield + biome model (world-space in, reference units out)
// ---------------------------------------------------------------------------------------------

terrain_gen_sample_column :: proc(
	o: ^Terrain_Chunk_Gen_Options,
	world_x, world_z: f32,
) -> Terrain_Gen_Column {
	k := 1 / TERRAIN_GEN_REF
	x, z := world_x * k, world_z * k
	s := o.feature_scale
	sea := o.sea_level * k
	vref := o.voxel_size * k // reference units per voxel

	// Fade out features the voxel grid can't represent, so coarse grids don't alias.
	detail_fade := terrain_smoothstep(2.5, 6, (1 / (0.09 * s)) / vref)
	ridge_octaves := vref <= 2 ? 4 : (vref <= 4 ? 3 : 2)

	wx := x + (terrain_fbm2(x, z, 2, 0.007 * s, o.seed + 11) - 0.5) * 70
	wz := z + (terrain_fbm2(x, z, 2, 0.007 * s, o.seed + 12) - 0.5) * 70

	continent := terrain_stretch(terrain_fbm2(wx, wz, 4, 0.004 * s, o.seed + 1), 2.4)
	land := terrain_smoothstep(0.38, 0.5, continent)

	range_noise := terrain_stretch(terrain_fbm2(wx, wz, 3, 0.007 * s, o.seed + 2), 2.2)
	mountain :=
		terrain_smoothstep(0.55, 0.85, range_noise) * terrain_smoothstep(0.5, 0.65, continent)

	h := sea + (continent - 0.45) * o.base_height * k * 1.6
	hills :=
		(terrain_fbm2(wx, wz, 4, 0.018 * s, o.seed + 3) - 0.5) *
		2 *
		o.hill_height *
		k *
		(1 - 0.6 * mountain)
	crests := terrain_ridged2(wx, wz, ridge_octaves, 0.012 * s, o.seed + 4)
	peaks := mountain * (0.25 + 0.75 * crests) * o.mountain_height * k
	detail := (terrain_fbm2(x, z, 2, 0.09 * s, o.seed + 5) - 0.5) * 1.5 * detail_fade
	h += (hills + detail) * land + peaks

	river_noise := math.abs(terrain_fbm2(wx, wz, 3, 0.006 * s, o.seed + 6) - 0.5)
	river :=
		(1 - terrain_smoothstep(0.01, 0.035, river_noise)) *
		land *
		(1 - mountain) *
		(1 - terrain_smoothstep(sea + 6, sea + 18, h))
	h = terrain_lerp(h, min(h, sea - 2), river)

	temp := terrain_stretch(terrain_fbm2(wx, wz, 3, 0.005 * s, o.seed + 7), 2.0)
	temp = clamp(temp - max(h - sea, 0) * 0.006, 0, 1)
	moist := terrain_stretch(terrain_fbm2(wx, wz, 3, 0.006 * s, o.seed + 8), 2.0)

	return Terrain_Gen_Column{height = h, mountain = mountain, temp = temp, moist = moist}
}

terrain_gen_pick_biome :: proc(
	o: ^Terrain_Chunk_Gen_Options,
	c: ^Terrain_Gen_Column,
) -> Terrain_Biome {
	k := 1 / TERRAIN_GEN_REF
	elev := c.height - o.sea_level * k
	slope := math.sqrt(c.gx * c.gx + c.gz * c.gz)
	if !o.biomes {
		return elev < -0.5 ? Terrain_Biome.Ocean : Terrain_Biome.Plains
	}
	snow_line := o.snow_line * k + (c.temp - 0.5) * 40
	switch {
	case elev < -0.5:
		return .Ocean
	case elev < 2.5 && c.mountain < 0.2:
		return .Beach
	case elev > snow_line:
		return .Snow
	case c.mountain > 0.45 || (slope > 1.0 && elev > 8):
		return .Alpine
	case c.temp < 0.3:
		return .Tundra
	case c.temp > 0.62 && c.moist < 0.45:
		return .Desert
	case c.moist > 0.6:
		if elev < 5 && c.moist > 0.72 {return .Swamp}
		return .Forest
	}
	return .Plains
}

// `dist` = distance below the surface in reference units. The whole near-surface shell gets one
// material (no per-voxel-row flipping), and `steep` is decided per column by the caller.
// Snow uses SmoothPlastic; return .Snow here if your Material enum has it.
terrain_gen_material :: proc(biome: Terrain_Biome, dist: f32, steep: bool) -> enums.Material {
	if dist > 28 {return .Basalt}
	if dist > 6 {
		if (biome == .Desert || biome == .Beach) && dist < 12 {return .Sandstone}
		return .Slate
	}
	shell := dist <= 3
	if steep && biome != .Ocean {return shell ? .Rock : .Slate}
	switch biome {
	case .Ocean, .Beach, .Desert:
		return shell ? .Sand : .Sandstone
	case .Plains:
		return shell ? .Grass : .Ground
	case .Forest:
		return shell ? .LeafyGrass : .Ground
	case .Swamp:
		return shell ? .Mud : .Ground
	case .Tundra:
		return shell ? .Ground : .Slate
	case .Alpine:
		return shell ? .Rock : .Slate
	case .Snow:
		return shell ? .SmoothPlastic : .Rock
	}
	return .Grass
}

// ---------------------------------------------------------------------------------------------
// Chunk filling (runs on worker threads)
// ---------------------------------------------------------------------------------------------

terrain_gen_fill_chunk :: proc(
	o: ^Terrain_Chunk_Gen_Options,
	cols: ^Terrain_Gen_Columns,
	max_h: f32, // reference units
	key: Terrain_Chunk_Key,
) -> ^Terrain_Chunk_Data {
	S :: TERRAIN_CHUNK_SIZE
	vs := o.voxel_size
	scale := vs / TERRAIN_GEN_REF // reference units per voxel
	x0, y0, z0 := key.x * S, key.y * S, key.z * S
	margin: f32 = o.overhangs ? 12 : 2
	sea_ref := o.sea_level / TERRAIN_GEN_REF
	if f32(y0) * scale > max(max_h + margin, sea_ref) {return nil}

	sea_vox := o.sea_level / vs
	caves := o.caves && scale <= 2.5 // tunnels thinner than a voxel are just noise
	data := new(Terrain_Chunk_Data)
	for lx in 0 ..< S {
		for lz in 0 ..< S {
			col := cols[(lx + 1) * TERRAIN_GEN_COLUMN_DIM + lz + 1]
			wx, wz := x0 + lx, z0 + lz
			hv := col.height / scale // surface height in voxels
			slope := math.sqrt(col.gx * col.gx + col.gz * col.gz)
			// Dividing by |grad| approximates a true distance field: smooth steep slopes.
			norm := 1 / math.sqrt(1 + slope * slope)

			// Cliff decision per column, jittered so the boundary is patchy, not contour lines.
			jitter :=
				(terrain_value_noise_2d(
						f32(wx) * scale * 0.08,
						f32(wz) * scale * 0.08,
						o.seed + 21,
					) -
					0.5) *
				0.5
			steep := slope + jitter > 1.1

			for ly in 0 ..< S {
				wy := y0 + ly
				depth := hv - f32(wy) // voxels below the heightfield
				d := depth * norm

				if o.overhangs && col.mountain > 0.6 && math.abs(d) * scale < 6 {
					n := terrain_fbm(
						f32(wx) * scale,
						f32(wy) * scale,
						f32(wz) * scale,
						2,
						0.03 * o.feature_scale,
						1,
						o.seed + 9,
					)
					d += (n - 0.5) * col.mountain * 4 / scale
				}
				occ := clamp(0.5 + d, 0, 1)

				if caves && depth * scale > 6 && occ > 0 {
					cf := 0.045 * o.feature_scale
					px, py, pz := f32(wx) * scale, f32(wy) * scale, f32(wz) * scale
					a := terrain_fbm(px, py, pz, 2, cf, 1, o.seed + 4049) - 0.5
					b := terrain_fbm(px, py, pz, 2, cf, 1, o.seed + 8101) - 0.5
					radius := 0.04 * o.cave_size
					r := math.sqrt(a * a + b * b)
					if r < radius {
						tunnel := clamp((1 - r / radius) * 3, 0, 1)
						tunnel *= terrain_smoothstep(6, 12, depth * scale)
						occ = min(occ, 1 - tunnel)
					}
				}

				water: f32
				if f32(wy) + 1 <= sea_vox && occ < 1 && depth < 1 {
					water = 1 // open water above the surface only (no flooded caves)
				}
				if occ <= 0 && water <= 0 {continue}

				material := enums.Material.Water
				if occ > 0 {
					material = terrain_gen_material(col.biome, max(depth * norm, 0) * scale, steep)
				}

				idx := (lx * S + ly) * S + lz
				data.occupancy[idx] = occ
				data.water[idx] = water
				data.material[idx] = material
				data.present += 1
				if occ > 0 {data.solid += 1}
				if terrain_cell_has_surface(water, material) {data.surface += 1}
			}
		}
	}
	if data.present == 0 {
		free(data)
		return nil
	}
	return data
}

terrain_gen_height :: proc(cols: ^Terrain_Gen_Columns, i, j: int) -> f32 {
	return cols[i * TERRAIN_GEN_COLUMN_DIM + j].height
}

terrain_gen_run_column :: proc(o: ^Terrain_Chunk_Gen_Options, job: ^Terrain_Gen_Column_Job) {
	S :: TERRAIN_CHUNK_SIZE
	DIM :: TERRAIN_GEN_COLUMN_DIM
	vs := o.voxel_size
	scale := vs / TERRAIN_GEN_REF
	x0, z0 := job.cx * S, job.cz * S

	cols: Terrain_Gen_Columns
	for i in 0 ..< DIM {
		for j in 0 ..< DIM {
			cols[i * DIM + j] = terrain_gen_sample_column(
				o,
				f32(x0 - 1 + i) * vs,
				f32(z0 - 1 + j) * vs,
			)
		}
	}

	// Sobel gradient (rise/run, dimensionless): smoother than a plain central difference.
	inv := 0.125 / scale
	max_h := f32(-1.0e9)
	for i in 1 ..< DIM - 1 {
		for j in 1 ..< DIM - 1 {
			c := &cols[i * DIM + j]
			c.gx =
				((terrain_gen_height(&cols, i + 1, j - 1) +
						2 * terrain_gen_height(&cols, i + 1, j) +
						terrain_gen_height(&cols, i + 1, j + 1)) -
					(terrain_gen_height(&cols, i - 1, j - 1) +
							2 * terrain_gen_height(&cols, i - 1, j) +
							terrain_gen_height(&cols, i - 1, j + 1))) *
				inv
			c.gz =
				((terrain_gen_height(&cols, i - 1, j + 1) +
						2 * terrain_gen_height(&cols, i, j + 1) +
						terrain_gen_height(&cols, i + 1, j + 1)) -
					(terrain_gen_height(&cols, i - 1, j - 1) +
							2 * terrain_gen_height(&cols, i, j - 1) +
							terrain_gen_height(&cols, i + 1, j - 1))) *
				inv
			c.biome = terrain_gen_pick_biome(o, c)
			max_h = max(max_h, c.height)
		}
	}

	count := o.max_chunk_y - o.min_chunk_y + 1
	job.chunks = make([dynamic]^Terrain_Chunk_Data, 0, count)
	for cy in o.min_chunk_y ..= o.max_chunk_y {
		append(
			&job.chunks,
			terrain_gen_fill_chunk(o, &cols, max_h, Terrain_Chunk_Key{job.cx, cy, job.cz}),
		)
	}
}

terrain_chunk_gen_worker :: proc(t: ^thread.Thread) {
	when tracy.TRACY_ENABLE {
		context.allocator = tracy.DefaultContext().allocator
	}
	tracy.ZoneNC("Terrain Chunk Gen Worker", 0xC678DD)
	gen := cast(^Terrain_Chunk_Generation)t.data
	for {
		if sync.atomic_load(&gen.cancel) != 0 {break}
		i := sync.atomic_add(&gen.next_job, 1)
		if i >= len(gen.jobs) {break}
		terrain_gen_run_column(&gen.options, &gen.jobs[i])
		sync.atomic_store(&gen.jobs[i].ready, 1)
	}
}

// ---------------------------------------------------------------------------------------------
// Main-thread side: start / poll / release
// ---------------------------------------------------------------------------------------------

// Applies voxel size / shading to the service and derives the chunk-space vertical range.
// Changing the voxel size rescales the world, so existing terrain is cleared first.
terrain_gen_apply_resolution :: proc(service: ^Terrain, o: ^Terrain_Chunk_Gen_Options) {
	if o.voxel_size > 0 {
		o.voxel_size = clamp(o.voxel_size, 1, 64)
		if o.voxel_size != service.voxel_size {
			terrain_clear(service, service.renderer)
			service.voxel_size = o.voxel_size
		}
	} else {
		o.voxel_size = service.voxel_size
	}
	if fs, ok := o.flat_shading.?; ok && fs != service.flat_shading {
		service.flat_shading = fs
		terrain_mark_all_dirty(service)
	}
	span := f32(TERRAIN_CHUNK_SIZE) * o.voxel_size
	o.min_chunk_y = int(math.floor(o.min_y / span))
	o.max_chunk_y = max(int(math.floor(o.max_y / span)), o.min_chunk_y)
}

// World-space entry point: generate everything within `radius` studs of (x, z).
Terrain_Generate_Area :: proc(
	service: ^Terrain,
	x, z, radius: f32,
	options: Terrain_Chunk_Gen_Options,
) {
	if service == nil {return}
	vs := options.voxel_size > 0 ? clamp(options.voxel_size, 1, 64) : service.voxel_size
	span := f32(TERRAIN_CHUNK_SIZE) * vs
	r := max(radius, 0)
	Terrain_Generate_Chunks(
		service,
		int(math.floor((x - r) / span)),
		int(math.floor((z - r) / span)),
		int(math.floor((x + r) / span)),
		int(math.floor((z + r) / span)),
		options,
	)
}

// Chunk-space entry point: columns [min_cx..max_cx] x [min_cz..max_cz]. One chunk spans
// 16 * VoxelSize studs, so the same chunk range covers more world at lower detail.
Terrain_Generate_Chunks :: proc(
	service: ^Terrain,
	min_cx, min_cz, max_cx, max_cz: int,
	options: Terrain_Chunk_Gen_Options,
) {
	if service == nil || max_cx < min_cx || max_cz < min_cz {return}
	terrain_release_chunk_generation(service)

	gen := new(Terrain_Chunk_Generation)
	gen.options = options
	terrain_gen_apply_resolution(service, &gen.options)

	count_x := max_cx - min_cx + 1
	count_z := max_cz - min_cz + 1
	gen.jobs = make([]Terrain_Gen_Column_Job, count_x * count_z)

	mid_x, mid_z := (min_cx + max_cx) / 2, (min_cz + max_cz) / 2
	n := 0
	for cx in min_cx ..= max_cx {
		for cz in min_cz ..= max_cz {
			gen.jobs[n].cx = cx
			gen.jobs[n].cz = cz
			gen.jobs[n].dist2 = (cx - mid_x) * (cx - mid_x) + (cz - mid_z) * (cz - mid_z)
			n += 1
		}
	}
	slice.sort_by(gen.jobs, proc(a, b: Terrain_Gen_Column_Job) -> bool {return a.dist2 < b.dist2})

	worker_count := min(clamp(options.workers, 1, 32), len(gen.jobs))
	for _ in 0 ..< worker_count {
		worker := thread.create(terrain_chunk_gen_worker)
		if worker == nil {break}
		worker.data = gen
		append(&gen.workers, worker)
	}
	if len(gen.workers) == 0 {
		for i in 0 ..< len(gen.jobs) {
			terrain_gen_run_column(&gen.options, &gen.jobs[i])
			gen.jobs[i].ready = 1
		}
	} else {
		for worker in gen.workers {thread.start(worker)}
	}
	service.chunk_gen = gen
}

terrain_commit_gen_chunk :: proc(
	service: ^Terrain,
	key: Terrain_Chunk_Key,
	data: ^Terrain_Chunk_Data,
) {
	existing, ok := service.chunks[key]
	if data == nil && (!ok || existing == nil || existing.data == nil) {
		return
	}
	chunk := terrain_get_or_create_chunk(service, key)
	if chunk.data != nil {free(chunk.data)}
	chunk.data = data
	terrain_mark_chunk_dirty(service, key)

	for dx in -1 ..= 1 {
		for dy in -1 ..= 1 {
			for dz in -1 ..= 1 {
				if dx == 0 && dy == 0 && dz == 0 {continue}
				nk := Terrain_Chunk_Key{key.x + dx, key.y + dy, key.z + dz}
				if neighbour, found := service.chunks[nk]; found && neighbour != nil {
					neighbour.dirty = true
					neighbour.collision_dirty = true
					terrain_queue_chunk_dirty(service, nk)
				}
			}
		}
	}
}

// True while generation is pending (Prepare_3D holds off meshing until the region is in).
terrain_poll_chunk_generation :: proc(service: ^Terrain) -> bool {
	gen := service.chunk_gen
	if gen == nil {return false}
	tracy.ZoneNC("Terrain Chunk Gen Commit", 0xB48EAD)

	budget := TERRAIN_GEN_COMMIT_PER_FRAME
	committed := false
	for gen.commit_job < len(gen.jobs) && budget > 0 {
		job := &gen.jobs[gen.commit_job]
		if sync.atomic_load(&job.ready) == 0 {break}
		for gen.commit_chunk < len(job.chunks) && budget > 0 {
			cy := gen.options.min_chunk_y + gen.commit_chunk
			terrain_commit_gen_chunk(
				service,
				Terrain_Chunk_Key{job.cx, cy, job.cz},
				job.chunks[gen.commit_chunk],
			)
			job.chunks[gen.commit_chunk] = nil
			gen.commit_chunk += 1
			budget -= 1
			committed = true
		}
		if gen.commit_chunk >= len(job.chunks) {
			delete(job.chunks)
			job.chunks = nil
			gen.commit_job += 1
			gen.commit_chunk = 0
		}
	}

	if committed {
		service.geometry_version += 1
		if service.dirty_tracking {
			service.change_serial += 1
			service.dirty_epoch += 1
			clear(&service.replication_dirty)
		}
	}
	if gen.commit_job >= len(gen.jobs) {
		terrain_release_chunk_generation(service)
		return false
	}
	return true
}

terrain_release_chunk_generation :: proc(service: ^Terrain) {
	gen := service.chunk_gen
	if gen == nil {return}
	sync.atomic_store(&gen.cancel, 1)
	for worker in gen.workers {
		thread.join(worker)
		thread.destroy(worker)
	}
	delete(gen.workers)
	for &job in gen.jobs {
		for data in job.chunks {
			if data != nil {free(data)}
		}
		delete(job.chunks)
	}
	delete(gen.jobs)
	free(gen)
	service.chunk_gen = nil
}

// ---------------------------------------------------------------------------------------------
// Luau binding helper
// ---------------------------------------------------------------------------------------------

terrain_read_chunk_gen_options :: proc(
	L: ^vm.State,
	table_index: int,
) -> Terrain_Chunk_Gen_Options {
	o := terrain_default_chunk_gen_options()
	if !vm.IsTable(L, table_index) {return o}

	// Presets first; explicit voxelSize / flatShading below override them.
	if preset, ok := terrain_table_string(L, table_index, "detail"); ok {
		switch {
		case terrain_equal_fold(preset, "lowpoly"):
			o.voxel_size = 16
			o.flat_shading = true
			o.caves = false
			o.overhangs = false
		case terrain_equal_fold(preset, "medium"):
			o.voxel_size = 8
			o.flat_shading = false
		case terrain_equal_fold(preset, "high"):
			o.voxel_size = 4
			o.flat_shading = false
		case terrain_equal_fold(preset, "ultra"):
			o.voxel_size = 2
			o.flat_shading = false
		}
	}
	vsize := terrain_table_number(L, table_index, "voxelSize", f64(o.voxel_size))
	o.voxel_size = vsize > 0 ? clamp(f32(vsize), 1, 64) : 0
	_ = vm.GetField(L, table_index, "flatShading")
	if vm.IsBoolean(L, -1) {o.flat_shading = vm.ArgBoolean(L, -1)}
	vm.Pop(L)

	o.seed = i64(math.floor(terrain_table_number(L, table_index, "seed", f64(o.seed))))
	o.sea_level = f32(terrain_table_number(L, table_index, "seaLevel", f64(o.sea_level)))
	o.base_height = clamp(
		f32(terrain_table_number(L, table_index, "baseHeight", f64(o.base_height))),
		0,
		2000,
	)
	o.mountain_height = clamp(
		f32(terrain_table_number(L, table_index, "mountainHeight", f64(o.mountain_height))),
		0,
		3000,
	)
	o.hill_height = clamp(
		f32(terrain_table_number(L, table_index, "hillHeight", f64(o.hill_height))),
		0,
		1000,
	)
	o.snow_line = f32(terrain_table_number(L, table_index, "snowLine", f64(o.snow_line)))
	o.min_y = f32(terrain_table_number(L, table_index, "minY", f64(o.min_y)))
	o.max_y = f32(terrain_table_number(L, table_index, "maxY", f64(o.max_y)))
	o.feature_scale = clamp(f32(terrain_table_number(L, table_index, "featureScale", 1)), 0.1, 8)
	o.cave_size = clamp(f32(terrain_table_number(L, table_index, "caveSize", 1)), 0.25, 3)
	o.workers = int(math.floor(terrain_table_number(L, table_index, "workers", f64(o.workers))))
	o.caves = terrain_table_bool(L, table_index, "caves", o.caves)
	o.overhangs = terrain_table_bool(L, table_index, "overhangs", o.overhangs)
	o.biomes = terrain_table_bool(L, table_index, "biomes", o.biomes)
	return o
}
