package services

import "core:math"

terrain_sdf_fbm2 :: proc(o: ^Terrain_Chunk_Gen_Options, x, z, frequency: f32, seed: i64) -> f32 {
	sum, total: f32
	amp := f32(1)
	freq := frequency
	for i in 0 ..< o.sdf_octaves {
		// Remove octaves too small to represent on the selected voxel lattice.
		weight := clamp((1.0 / (freq * o.voxel_size) - 2) / 2, 0, 1)
		if weight <= 0 {break}
		sum +=
			(terrain_value_noise_2d(x * freq, z * freq, seed + i64(i) * 7919) * 2 - 1) *
			amp *
			weight
		total += amp * weight
		freq *= o.sdf_lacunarity
		amp *= o.sdf_gain
	}
	return sum / max(total, 1e-6)
}

terrain_sdf_fbm3 :: proc(
	o: ^Terrain_Chunk_Gen_Options,
	x, y, z, frequency: f32,
	seed: i64,
) -> f32 {
	sum, total: f32
	amp := f32(1)
	freq := frequency
	for i in 0 ..< o.sdf_octaves {
		weight := clamp((1.0 / (freq * o.voxel_size) - 2) / 2, 0, 1)
		if weight <= 0 {break}
		sum +=
			(terrain_value_noise_3d(x * freq, y * freq, z * freq, seed + i64(i) * 7919) * 2 - 1) *
			amp *
			weight
		total += amp * weight
		freq *= o.sdf_lacunarity
		amp *= o.sdf_gain
	}
	return sum / max(total, 1e-6)
}

// Height is only the broad landscape; the actual surface can fold back on
// itself because the subsequent 3D density is not a heightfield.
Terrain_SDF_Height :: proc(o: ^Terrain_Chunk_Gen_Options, x, z: f32) -> f32 {
	f := o.feature_scale / max(o.sdf_scale, 1)
	warp_x := terrain_sdf_fbm2(o, x, z, f * 0.65, o.seed + 31) * o.sdf_scale * 0.18
	warp_z := terrain_sdf_fbm2(o, x, z, f * 0.65, o.seed + 32) * o.sdf_scale * 0.18
	wx, wz := x + warp_x, z + warp_z
	broad := terrain_sdf_fbm2(o, wx, wz, f, o.seed + 33)
	hills := terrain_sdf_fbm2(o, wx, wz, f * 2, o.seed + 34)
	return(
		o.sea_level +
		o.base_height * 0.5 +
		broad * o.mountain_height * 0.5 +
		hills * o.hill_height \
	)
}

// Max displacement plus the smooth-union bulge bounds the surface band.
terrain_sdf_band :: proc(o: ^Terrain_Chunk_Gen_Options) -> f32 {
	return o.sdf_amplitude + o.sdf_blend + 2 * o.voxel_size
}

// Density is in studs. Use the same sampled field for rendering and collision.
Terrain_SDF_Density :: proc(o: ^Terrain_Chunk_Gen_Options, x, y, z, height: f32) -> f32 {
	depth := height - y
	band := terrain_sdf_band(o)
	d := depth
	if abs(depth) <= band {
		frequency := o.feature_scale / max(o.sdf_scale * 0.20, 1)
		n := terrain_sdf_fbm3(o, x, y, z, frequency, o.seed + 41)
		// Fade the displacement near the guard band for continuity.
		fade := 1 - terrain_smoothstep(max(band - o.voxel_size, 0), band, abs(depth))
		d += n * o.sdf_amplitude * fade
		// Rounded lobes merge gradually into the ground. This is a bounded
		// smooth union of two implicit fields rather than a height-only ridge.
		if o.overhangs && o.sdf_blend > 0 {
			lobes := terrain_sdf_fbm3(o, x, y, z, frequency * 0.72, o.seed + 42)
			secondary := depth * 0.65 + (lobes - 0.24) * o.sdf_amplitude
			merged := terrain_smooth_max(d, secondary, o.sdf_blend)
			d = terrain_lerp(d, merged, fade)
		}
	}
	if o.caves && depth > 2 * o.voxel_size && d > -o.voxel_size {
		frequency := o.feature_scale / max(o.sdf_scale * 0.24, 1)
		a := terrain_sdf_fbm3(o, x, y, z, frequency, o.seed + 51)
		b := terrain_sdf_fbm3(o, x, y, z, frequency, o.seed + 52)
		r := math.sqrt(a * a + b * b)
		radius := clamp(0.12 * o.cave_size, 0.03, 0.36)
		// Negative in the tunnel; smooth max in the negative-distance
		// convention corresponds to smooth min in our solid-positive field.
		cut := (r - radius) / max(frequency, 1e-6)
		fade := terrain_smoothstep(2 * o.voxel_size, 5 * o.voxel_size, depth)
		carved := terrain_smooth_min(d, cut, min(o.sdf_blend, 2 * o.voxel_size))
		d = terrain_lerp(d, carved, fade)
	}
	return d
}

// Sparse deterministic rounded rocks. Candidates are generated in global
// lattice space, so independently generated chunks agree at their borders.
Terrain_SDF_Rock :: struct {
	center_y, radius, horizontal_sq: f32,
}

terrain_sdf_rocks_at :: proc(o: ^Terrain_Chunk_Gen_Options, x, z: f32) -> [9]Terrain_SDF_Rock {
	rocks: [9]Terrain_SDF_Rock
	if o.sdf_rock_density <= 0 || !o.overhangs {return rocks}
	spacing := max(o.sdf_rock_size * 3.2, o.voxel_size * 6)
	gx, gz := int(math.floor(x / spacing)), int(math.floor(z / spacing))
	index := 0
	for ix in gx - 1 ..= gx + 1 {
		for iz in gz - 1 ..= gz + 1 {
			if terrain_hash(ix, 0, iz, o.seed + 61) >= o.sdf_rock_density {continue}
			cx := (f32(ix) + 0.5 + (terrain_hash(ix, 1, iz, o.seed + 62) - 0.5) * 0.5) * spacing
			cz := (f32(iz) + 0.5 + (terrain_hash(ix, 2, iz, o.seed + 63) - 0.5) * 0.5) * spacing
			radius := o.sdf_rock_size * (0.65 + 0.35 * terrain_hash(ix, 3, iz, o.seed + 64))
			dx, dz := x - cx, z - cz
			h2 := dx * dx + dz * dz
			reach := radius + min(o.sdf_blend, radius * 0.5) + o.voxel_size
			if h2 > reach * reach {continue}
			height := Terrain_SDF_Height(o, cx, cz)
			// Estimate the nearby implicit surface, then embed the rock in it.
			center := height
			for _ in 0 ..< 3 {
				d := Terrain_SDF_Density(o, cx, center, cz, height)
				center += clamp(d, -o.sdf_amplitude, o.sdf_amplitude) * 0.65
			}
			rocks[index] = {center - radius * 0.2, radius, h2}
			index += 1
		}
	}
	return rocks
}

terrain_sdf_merge_rocks :: proc(
	o: ^Terrain_Chunk_Gen_Options,
	d, y: f32,
	rocks: ^[9]Terrain_SDF_Rock,
) -> f32 {
	result := d
	for rock in rocks^ {
		if rock.radius <= 0 {break}
		dy := y - rock.center_y
		// Avoid a square root outside the region affected by the union.
		blend := min(o.sdf_blend, rock.radius * 0.5)
		if abs(dy) > rock.radius + blend + o.voxel_size {continue}
		field := rock.radius - math.sqrt(rock.horizontal_sq + dy * dy)
		// Keep the implicit field continuous even outside the sphere.
		result = terrain_smooth_max(result, field, blend)
	}
	return result
}
