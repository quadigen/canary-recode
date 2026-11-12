package services

import kineffi "../bindings"
import enums "../enum"

Terrain_Surface_Kind :: enum { Water, Glass, Neon }

Terrain_Surface_Geometry :: struct {
	vertices: [dynamic]f32,
	indices:  [dynamic]u32,
}

// Water still needs vertices for wave displacement. Four subdivisions per voxel
// give one-stud spacing at the default resolution, down from 32 subdivisions.
TERRAIN_WATER_SEGMENTS :: 4

Terrain_Build_Chunk_Surfaces :: proc(
	service: ^Terrain,
	key: Terrain_Chunk_Key,
	output: ^[Terrain_Surface_Kind]Terrain_Surface_Geometry,
) {
	chunk := service.chunks[key]
	if chunk == nil || chunk.data == nil || chunk.data.surface == 0 {return}
	data := chunk.data
	above_chunk := service.chunks[{key.x, key.y + 1, key.z}]
	base_x := key.x * TERRAIN_CHUNK_SIZE
	base_y := key.y * TERRAIN_CHUNK_SIZE
	base_z := key.z * TERRAIN_CHUNK_SIZE
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
				if above_data != nil &&
				   (above_data.water[above_index] > 0 || above_data.occupancy[above_index] > 0) {continue}

				kind: Terrain_Surface_Kind
				level := water
				#partial switch material {
				case .Glass: kind = .Glass
				case .Neon:
					kind = .Neon
					level = max(water, data.occupancy[index])
				}
				segments := TERRAIN_WATER_SEGMENTS if kind == .Water else 1
				terrain_append_surface_grid(
					&output[kind], base_x + lx, base_z + lz, (f32(base_y + ly) + level) * vs, vs, segments,
				)
			}
		}
	}
}

terrain_append_surface_grid :: proc(
	surface: ^Terrain_Surface_Geometry, x, z: int, height, voxel_size: f32, segments: int,
) {
	base := u32(len(surface.vertices) / 8)
	step := voxel_size / f32(segments)
	for sz in 0 ..= segments {
		for sx in 0 ..= segments {
			append(
				&surface.vertices,
				f32(x * segments + sx) * step, height, f32(z * segments + sz) * step,
				0, 1, 0, f32(sx) / f32(segments), f32(sz) / f32(segments),
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

terrain_append_chunk_surfaces :: proc(service: ^Terrain, chunk: ^Terrain_Chunk, transform: [16]f32) {
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
		append(&service.draw_items, kineffi.KineFilamentDrawItem{
			mesh = mesh,
			transform = transform,
			r = color.R, g = color.G, b = color.B,
			param1 = param1, param2 = param2, param3 = param3,
			transmission = transmission,
			materialKind = i32(material_kind),
			flags = u32(kineffi.KINE_FILAMENT_DRAW_CULLING),
		})
	}
}
