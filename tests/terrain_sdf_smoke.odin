package main

import services "../src/engine/services"
import "core:fmt"
import "core:math"

main :: proc() {
	o := services.Terrain_Chunk_Gen_Options {
		seed             = 12345,
		voxel_size       = 2,
		feature_scale    = 1,
		sea_level        = -32,
		base_height      = 150,
		mountain_height  = 95,
		hill_height      = 22,
		sdf_style        = true,
		sdf_scale        = 100,
		sdf_octaves      = 7,
		sdf_gain         = 0.41,
		sdf_lacunarity   = 2,
		sdf_amplitude    = 22,
		sdf_blend        = 6,
		sdf_rock_size    = 9,
		sdf_rock_density = 0.45,
		overhangs        = true,
	}

	h := services.Terrain_SDF_Height(&o, 32, -16)
	assert(h == services.Terrain_SDF_Height(&o, 32, -16))
	assert(abs(h - services.Terrain_SDF_Height(&o, 32.001, -16)) < 0.1)
	assert(services.Terrain_SDF_Density(&o, 32, h - 100, -16, h) > 0)
	assert(services.Terrain_SDF_Density(&o, 32, h + 100, -16, h) < 0)

	// Sample both sides of a chunk boundary at negative world coordinates.
	for x in -40 ..= 40 {
		fx := f32(x)
		height := services.Terrain_SDF_Height(&o, fx, -32)
		d := services.Terrain_SDF_Density(&o, fx, height, -32, height)
		assert(!math.is_nan(d) && abs(d) < 40)
		assert(d == services.Terrain_SDF_Density(&o, fx, height, -32, height))
	}

	// Removing 3D perturbations must reduce to the base plane.
	o.sdf_amplitude = 0
	o.sdf_blend = 0
	o.caves = false
	assert(services.Terrain_SDF_Density(&o, 0, 17, 0, 20) == 3)
	assert(services.Terrain_SDF_Density(&o, 0, 23, 0, 20) == -3)
	fmt.println("TERRAIN_SDF_SMOKE_PASSED")
}
