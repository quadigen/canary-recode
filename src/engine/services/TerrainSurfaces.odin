package services

import kineffi "../bindings"
import enums "../enum"
import datatypes "../datatypes"

Terrain_Surface_Kind :: enum {
	Water,
	Glass,
	Neon,
}

Terrain_Surface_Geometry :: struct {
	vertices: [dynamic]f32,
	indices:  [dynamic]u32,
}

TERRAIN_WATER_SEGMENTS :: 4

Terrain_Build_Chunk_Surfaces :: proc(
	service: ^Terrain,
	key: Terrain_Chunk_Key,
	output: ^[Terrain_Surface_Kind]Terrain_Surface_Geometry,
	local_coordinates: bool = false,
) {
	chunk := service.chunks[key]
	if chunk == nil || chunk.data == nil {return}
	data := chunk.data
	above_chunk := service.chunks[{key.x, key.y + 1, key.z}]
	base_x := key.x * TERRAIN_CHUNK_SIZE
	base_y := key.y * TERRAIN_CHUNK_SIZE
	base_z := key.z * TERRAIN_CHUNK_SIZE
	if data.surface > 0 {
		terrain_append_exposed_surfaces(service, data, above_chunk, base_x, base_y, base_z, output, local_coordinates)
	}
	if data.solid > 0 {
		terrain_extend_water_under_shore(service, key, &output[.Water], local_coordinates)
	}
}

terrain_append_exposed_surfaces :: proc(
	service: ^Terrain,
	data: ^Terrain_Chunk_Data,
	above_chunk: ^Terrain_Chunk,
	base_x, base_y, base_z: int,
	output: ^[Terrain_Surface_Kind]Terrain_Surface_Geometry,
	local_coordinates: bool = false,
) {
	vs := service.voxel_size
	for lx in 0 ..< TERRAIN_CHUNK_SIZE {
		for ly in 0 ..< TERRAIN_CHUNK_SIZE {
			for lz in 0 ..< TERRAIN_CHUNK_SIZE {
				index := (lx * TERRAIN_CHUNK_SIZE + ly) * TERRAIN_CHUNK_SIZE + lz
				water := data.water[index]
				material := data.material[index]
				if !terrain_cell_has_surface(water, material) {continue}

				above_data := data
				above_index := index + TERRAIN_CHUNK_SIZE
				if ly + 1 == TERRAIN_CHUNK_SIZE {
					above_data = above_chunk.data if above_chunk != nil else nil
					above_index = lx * TERRAIN_CHUNK_SIZE * TERRAIN_CHUNK_SIZE + lz
				}
				if above_data != nil {
					above_solid := above_data.occupancy[above_index]
					if water > 0 && material != .Glass && material != .Neon {
						if above_data.water[above_index] > 0 {continue}
						below := data.occupancy[index]
						if below + (above_solid - below) * water >= service.iso_level &&
						   above_solid >= service.iso_level {continue}
					} else if above_data.water[above_index] > 0 || above_solid > 0 {continue}
				}

				kind: Terrain_Surface_Kind
				level := water
				#partial switch material {
				case .Glass:
					kind = .Glass
				case .Neon:
					kind = .Neon
					level = max(water, data.occupancy[index])
				}
				segments := TERRAIN_WATER_SEGMENTS if kind == .Water else 1
				terrain_append_surface_grid(
					&output[kind],
					(lx if local_coordinates else base_x + lx),
					(lz if local_coordinates else base_z + lz),
					(f32(ly if local_coordinates else base_y + ly) + level) * vs,
					vs,
					segments,
				)
			}
		}
	}
}

terrain_extend_water_under_shore :: proc(
	service: ^Terrain,
	key: Terrain_Chunk_Key,
	surface: ^Terrain_Surface_Geometry,
	local_coordinates: bool = false,
) {
	S :: TERRAIN_CHUNK_SIZE
	base_x, base_y, base_z := key.x * S, key.y * S, key.z * S
	chunks: [2][2][2]^Terrain_Chunk_Data
	for dx in 0 ..< 2 {
		for dy in 0 ..< 2 {
			for dz in 0 ..< 2 {
				if chunk := service.chunks[{key.x + dx, key.y + dy, key.z + dz}]; chunk != nil {
					chunks[dx][dy][dz] = chunk.data
				}
			}
		}
	}
	// The solid mesh samples density at lattice points. A water tile owned by a
	// voxel at (x,z) extends toward +X/+Z, so its dry neighbors on the opposite
	// sides can have visible water between the tile boundary and the rock mesh.
	for ly in 0 ..< S {
		y := base_y + ly
		water: [S + 1][S + 1]f32
		for row, lx in water {
			for _, lz in row {
				data := chunks[lx / S][0][lz / S]
				if data == nil {continue}
				index := ((lx % S) * S + ly) * S + lz % S
				level, material := data.water[index], data.material[index]
				if level <= 0 || material == .Glass || material == .Neon {continue}
				above := chunks[lx / S][(ly + 1) / S][lz / S]
				above_index := ((lx % S) * S + (ly + 1) % S) * S + lz % S
				if above == nil || above.water[above_index] <= 0 {
					if above != nil && above.occupancy[above_index] >= service.iso_level {continue}
					water[lx][lz] = level
				}
			}
		}
		for lx in 0 ..< S {
			for lz in 0 ..< S {
				if water[lx][lz] > 0 {continue}
				levels := [4]f32{0, water[lx + 1][lz], water[lx][lz + 1], water[lx + 1][lz + 1]}
				level := max(levels[1], levels[2], levels[3])
				if level <= 0 {continue}
				x, z := base_x + lx, base_z + lz
				if terrain_water(service, x, y, z) > 0 {continue}
				has_land, has_shore := false, false
				for corner in 0 ..< 4 {
					cx, cz := x + corner % 2, z + corner / 2
					below := terrain_occupancy(service, cx, y, cz)
					above := terrain_occupancy(service, cx, y + 1, cz)
					density := below + (above - below) * level
					has_shore = has_shore || density < service.iso_level
					// A fully occupied lower sample can still have a shallow
					// layer of water above the interpolated solid surface.
					has_land = has_land || max(below, density) >= service.iso_level
				}
				if !has_land || !has_shore {continue}
				terrain_append_surface_grid(
					surface,
					(lx if local_coordinates else x),
					(lz if local_coordinates else z),
					(f32(ly if local_coordinates else y) + level) * service.voxel_size,
					service.voxel_size,
					TERRAIN_WATER_SEGMENTS,
				)
			}
		}
	}
}

terrain_append_surface_grid :: proc(
	surface: ^Terrain_Surface_Geometry,
	x, z: int,
	height, voxel_size: f32,
	segments: int,
) {
	base := u32(len(surface.vertices) / 8)
	step := voxel_size / f32(segments)
	for sz in 0 ..= segments {
		for sx in 0 ..= segments {
			append(
				&surface.vertices,
				f32(x * segments + sx) * step,
				height,
				f32(z * segments + sz) * step,
				0,
				1,
				0,
				f32(sx) / f32(segments),
				f32(sz) / f32(segments),
			)
		}
	}
	row := u32(segments + 1)
	for sz in 0 ..< segments {
		for sx in 0 ..< segments {
			i := base + u32(sz) * row + u32(sx)
			append(&surface.indices, i, i + row, i + 1, i + 1, i + row, i + row + 1)
		}
	}
}

terrain_append_chunk_surfaces :: proc(
	service: ^Terrain,
	chunk: ^Terrain_Chunk,
	transform: [16]f32,
	origin: datatypes.Vector3,
) {
	for mesh, kind in chunk.surface_meshes {
		if mesh == nil {continue}
		material_kind := kineffi.KINE_MAT_WATER
		color := service.water_color
		transmission := clamp(1.0 - service.water_transparency, 0.2, 1.0)
		param1, param2, param3 := f32(0.08), f32(1.33), f32(0.5)
		switch kind {
		case .Water:
			if override, found := service.material_colors[.Water]; found {color = override}
		case .Glass:
			material_kind = kineffi.KINE_MAT_GLASS
			color = terrain_material_color(service, enums.Material.Glass)
			transmission, param1, param2, param3 = 0.85, 0.05, 1.52, 0.35
		case .Neon:
			material_kind = kineffi.KINE_MAT_NEON
			color = terrain_material_color(service, enums.Material.Neon)
			transmission, param1 = 0, 1
		}
		append(
			&service.draw_items,
			kineffi.KineFilamentDrawItem {
				mesh = mesh,
				transform = transform,
				r = color.R,
				g = color.G,
				b = color.B,
				param1 = param1,
				param2 = param2,
				param3 = param3,
				transmission = transmission,
				materialKind = i32(material_kind),
				flags = u32(kineffi.KINE_FILAMENT_DRAW_CULLING | kineffi.KINE_FILAMENT_DRAW_WORLD_POSITION),
				worldPosition = {origin.x, origin.y, origin.z},
			},
		)
	}
}
