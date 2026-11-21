package services

import enums "../enum"
import "core:math"

Terrain_Raymarch_Brick :: struct {
	samples:                [][4]f32,
	size, origin:           [3]i32,
	bounds_min, bounds_max: [3]i32,
}

terrain_uses_raymarching :: proc(service: ^Terrain) -> bool {
	return service.raymarching && !service.flat_shading
}

terrain_set_raymarching :: proc(service: ^Terrain, enabled: bool) {
	if enabled == service.raymarching {return}
	service.raymarching = enabled
	for key, chunk in service.chunks {
		chunk.dirty = true
		terrain_queue_chunk_dirty(service, key)
	}
}


terrain_queue_raymarch_neighbors :: proc(service: ^Terrain, chunk: ^Terrain_Chunk) {
	data := chunk.data
	if data == nil || data.solid == 0 {return}
	added := false
	for dx in 0 ..= 1 {
		for dy in 0 ..= 1 {

			neighbor_z: for dz in 0 ..= 1 {
				if dx == 0 && dy == 0 && dz == 0 {continue}
				key := Terrain_Chunk_Key{chunk.key.x - dx, chunk.key.y - dy, chunk.key.z - dz}
				if key in service.chunks {continue}
				for x in 0 ..< (dx == 1 ? 1 : TERRAIN_CHUNK_SIZE) {
					for y in 0 ..< (dy == 1 ? 1 : TERRAIN_CHUNK_SIZE) {
						for z in 0 ..< (dz == 1 ? 1 : TERRAIN_CHUNK_SIZE) {
							i := (x * TERRAIN_CHUNK_SIZE + y) * TERRAIN_CHUNK_SIZE + z
							if data.occupancy[i] >= service.iso_level &&
							   !terrain_material_is_liquid(data.material[i]) {
								terrain_mark_chunk_dirty(service, key)
								added = true
								continue neighbor_z
							}
						}
					}
				}
			}
		}
	}
	if added {service.geometry_version += 1}
}

terrain_build_raymarch_brick :: proc(
	service: ^Terrain,
	cache: ^Terrain_Density_Cache,
	vertices: []f32,
	brick: ^Terrain_Raymarch_Brick,
) {
	lo: [3]f32 = {TERRAIN_CHUNK_SIZE, TERRAIN_CHUNK_SIZE, TERRAIN_CHUNK_SIZE}
	hi: [3]f32
	for i := 0; i < len(vertices); i += 8 {
		for axis in 0 ..< 3 {
			p := vertices[i + axis] / service.voxel_size
			lo[axis] = min(lo[axis], p)
			hi[axis] = max(hi[axis], p)
		}
	}
	for axis in 0 ..< 3 {


		brick.bounds_min[axis] = max(i32(math.floor(lo[axis])) - 1, 0)
		brick.bounds_max[axis] = min(i32(math.ceil(hi[axis])) + 1, TERRAIN_CHUNK_SIZE)
		brick.origin[axis] = brick.bounds_min[axis] - TERRAIN_CACHE_PAD
		brick.size[axis] =
			brick.bounds_max[axis] - brick.bounds_min[axis] + 1 + 2 * TERRAIN_CACHE_PAD
	}


	palette: [enums.MATERIAL_COUNT][3]f32
	for &rgb, id in palette {
		color := terrain_material_color(service, enums.Material(id))
		rgb = {color.R, color.G, color.B}
		for &channel in rgb {
			channel = clamp(channel, 0, 1)
			channel =
				channel / 12.92 if channel < 0.04045 else math.pow((channel + 0.055) / 1.055, 2.4)
		}
	}
	nx, ny, nz := int(brick.size.x), int(brick.size.y), int(brick.size.z)
	start_x := int(brick.origin.x) + TERRAIN_CACHE_PAD
	start_y := int(brick.origin.y) + TERRAIN_CACHE_PAD
	start_z := int(brick.origin.z) + TERRAIN_CACHE_PAD
	brick.samples = make([][4]f32, nx * ny * nz)
	for z in 0 ..< nz {
		for y in 0 ..< ny {
			for x in 0 ..< nx {
				i :=
					((start_x + x) * TERRAIN_CACHE_DIM + start_y + y) * TERRAIN_CACHE_DIM +
					start_z +
					z
				occ := cache.data[i]
				rgb := palette[cache.material_ids[i]]
				brick.samples[(z * ny + y) * nx + x] = {
					occ,
					rgb[0] * occ,
					rgb[1] * occ,
					rgb[2] * occ,
				}
			}
		}
	}
}
