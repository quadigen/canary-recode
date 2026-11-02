package datatypes

import "core:math"


Water_Wave :: struct {
	direction:                 [2]f32,
	wavelength, weight, phase: f32,
}
WATER_WAVES := [?]Water_Wave {
	{{0.940, 0.342}, 32, 0.50, 0.4},
	{{-0.574, 0.819}, 19, 0.23, 2.1},
	{{0.259, -0.966}, 11, 0.13, 4.7},
	{{-0.848, -0.530}, 7, 0.075, 1.3},
	{{0.719, 0.695}, 4, 0.04, 5.5},
	{{-0.196, 0.981}, 2.5, 0.025, 3.2},
}

Water_Wave_Displacement :: proc(
	x, z, time, speed, strength, height, scale: f32,
	count: int,
) -> Vector3 {
	result: Vector3
	for i in 0 ..< clamp(count, 1, len(WATER_WAVES)) {
		wave := WATER_WAVES[i]
		length := math.sqrt(
			wave.direction[0] * wave.direction[0] + wave.direction[1] * wave.direction[1],
		)
		dx, dz := wave.direction[0] / length, wave.direction[1] / length
		k := 2 * f32(math.PI) / (wave.wavelength * max(scale, 0.25))
		amplitude := 0.65 * strength * height * wave.weight
		phase := k * (dx * x + dz * z) - math.sqrt(9.81 * k) * time * speed + wave.phase
		horizontal := min(amplitude * 0.35, 0.12 / k) * math.cos(phase)
		result.x += dx * horizontal
		result.z += dz * horizontal
		result.y += amplitude * math.sin(phase)
	}
	return result
}

Water_Wave_Sample :: proc(
	x, z, time, speed, strength, height, scale: f32,
	count: int,
) -> (
	elevation, velocity: f32,
) {


	qx, qz := x, z
	for _ in 0 ..< 6 {
		displacement := Water_Wave_Displacement(
			qx,
			qz,
			time,
			speed,
			strength,
			height,
			scale,
			count,
		)
		qx, qz = x - displacement.x, z - displacement.z
	}
	jxx, jxz, jzz := f32(1), f32(0), f32(1)
	hx, hz, gradient_x, gradient_z, vertical := f32(0), f32(0), f32(0), f32(0), f32(0)
	for i in 0 ..< clamp(count, 1, len(WATER_WAVES)) {
		wave := WATER_WAVES[i]
		length := math.sqrt(
			wave.direction[0] * wave.direction[0] + wave.direction[1] * wave.direction[1],
		)
		dx, dz := wave.direction[0] / length, wave.direction[1] / length
		k := 2 * f32(math.PI) / (wave.wavelength * max(scale, 0.25))
		amplitude := 0.65 * strength * height * wave.weight
		horizontal := min(amplitude * 0.35, 0.12 / k)
		omega := math.sqrt(9.81 * k) * speed
		phase := k * (dx * qx + dz * qz) - omega * time + wave.phase
		s, c := math.sin(phase), math.cos(phase)
		elevation += amplitude * s
		gradient_x += amplitude * k * dx * c; gradient_z += amplitude * k * dz * c
		vertical -= amplitude * omega * c
		hx += horizontal * omega * dx * s; hz += horizontal * omega * dz * s
		jxx -=
			horizontal *
			k *
			dx *
			dx *
			s; jxz -= horizontal * k * dx * dz * s; jzz -= horizontal * k * dz * dz * s
	}
	determinant := jxx * jzz - jxz * jxz
	qvx, qvz := (-jzz * hx + jxz * hz) / determinant, (jxz * hx - jxx * hz) / determinant
	velocity = vertical + gradient_x * qvx + gradient_z * qvz
	return
}

Water_Wave_Height :: proc(x, z, time, speed, strength, height, scale: f32, count: int) -> f32 {
	elevation, _ := Water_Wave_Sample(x, z, time, speed, strength, height, scale, count)
	return elevation
}
