package datatypes

import "core:math"


Water_Wave :: struct {
	direction:                 [2]f32,
	wavelength, weight, phase: f32,
}
WATER_WAVES := [?]Water_Wave {
	{{0.940, 0.342}, 24, 0.50, 0.4},
	{{-0.574, 0.819}, 14, 0.23, 2.1},
	{{0.259, -0.966}, 9, 0.13, 4.7},
	{{-0.848, -0.530}, 6, 0.075, 1.3},
	{{0.719, 0.695}, 3.7, 0.04, 5.5},
	{{-0.196, 0.981}, 2.5, 0.025, 3.2},
}

water_wave_hash :: proc(x, z: i32) -> f32 {
	h := u32(x) * 0x8da6b343 ~ u32(z) * 0xd8163841
	h = (h ~ (h >> 16)) * 0x7feb352d
	h = (h ~ (h >> 15)) * 0x846ca68b
	return f32(h >> 16) / 65535
}

water_wave_noise :: proc(p: [2]f32) -> (value: f32, gradient: [2]f32) {
	cell := [2]f32{math.floor(p.x), math.floor(p.y)}
	x, z := i32(cell.x), i32(cell.y)
	f := p - cell
	blend := f * f * f * (f * (6 * f - 15) + 10)
	slope := 30 * f * f * (f - 1) * (f - 1)
	a, b := water_wave_hash(x, z), water_wave_hash(x + 1, z)
	c, d := water_wave_hash(x, z + 1), water_wave_hash(x + 1, z + 1)
	low := a + (b - a) * blend.x
	high := c + (d - c) * blend.x
	value = low + (high - low) * blend.y
	gradient = {((b - a) + ((d - c) - (b - a)) * blend.y) * slope.x, (high - low) * slope.y}
	return
}

water_wave_warp :: proc(p: [2]f32, scale: f32) -> (warped, gradient_x, gradient_z: [2]f32) {
	x, dx := water_wave_noise(p * (0.034 / scale) + [2]f32{13.4, -8.7})
	z, dz := water_wave_noise(p * (0.029 / scale) + [2]f32{-19.1, 5.6})
	warped = p + ([2]f32{x, z} - 0.5) * (18 * scale)
	gradient_x = [2]f32{1, 0} + dx * 0.612
	gradient_z = [2]f32{0, 1} + dz * 0.522
	return
}

Water_Wave_Displacement :: proc(
	x, z, time, speed, strength, height, scale: f32,
	count: int,
) -> Vector3 {
	result: Vector3
	wave_scale := max(scale, 0.25)
	p, _, _ := water_wave_warp({x, z}, wave_scale)
	for i in 0 ..< clamp(count, 1, len(WATER_WAVES)) {
		wave := WATER_WAVES[i]
		length := math.sqrt(
			wave.direction[0] * wave.direction[0] + wave.direction[1] * wave.direction[1],
		)
		dx, dz := wave.direction[0] / length, wave.direction[1] / length
		k := 2 * f32(math.PI) / (wave.wavelength * wave_scale)
		amplitude := 0.65 * strength * height * wave.weight
		phase := k * (dx * p.x + dz * p.y) - math.sqrt(9.81 * k) * (time * speed) + wave.phase
		horizontal := min(amplitude * 0.35, 0.12 / k) * math.cos(phase)
		result.x += f64(dx * horizontal)
		result.z += f64(dz * horizontal)
		result.y += f64(amplitude * math.sin(phase))
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
	for _ in 0 ..< 8 {
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
		qx, qz = f32(f64(x) - displacement.x), f32(f64(z) - displacement.z)
	}
	wave_scale := max(scale, 0.25)
	p, warp_x, warp_z := water_wave_warp({qx, qz}, wave_scale)
	jxx, jxz, jzx, jzz := f32(1), f32(0), f32(0), f32(1)
	hx, hz, gradient_x, gradient_z, vertical := f32(0), f32(0), f32(0), f32(0), f32(0)
	for i in 0 ..< clamp(count, 1, len(WATER_WAVES)) {
		wave := WATER_WAVES[i]
		length := math.sqrt(
			wave.direction[0] * wave.direction[0] + wave.direction[1] * wave.direction[1],
		)
		dx, dz := wave.direction[0] / length, wave.direction[1] / length
		k := 2 * f32(math.PI) / (wave.wavelength * wave_scale)
		amplitude := 0.65 * strength * height * wave.weight
		horizontal := min(amplitude * 0.35, 0.12 / k)
		omega := math.sqrt(9.81 * k) * speed
		phase := k * (dx * p.x + dz * p.y) - math.sqrt(9.81 * k) * (time * speed) + wave.phase
		phase_gradient := (warp_x * dx + warp_z * dz) * k
		s, c := math.sin(phase), math.cos(phase)
		elevation += amplitude * s
		gradient_x += amplitude * phase_gradient.x * c
		gradient_z += amplitude * phase_gradient.y * c
		vertical -= amplitude * omega * c
		hx += horizontal * omega * dx * s; hz += horizontal * omega * dz * s
		jxx -= horizontal * dx * phase_gradient.x * s
		jxz -= horizontal * dx * phase_gradient.y * s
		jzx -= horizontal * dz * phase_gradient.x * s
		jzz -= horizontal * dz * phase_gradient.y * s
	}
	determinant := jxx * jzz - jxz * jzx
	qvx := (-jzz * hx + jxz * hz) / determinant
	qvz := (jzx * hx - jxx * hz) / determinant
	velocity = vertical + gradient_x * qvx + gradient_z * qvz
	return
}

Water_Wave_Height :: proc(x, z, time, speed, strength, height, scale: f32, count: int) -> f32 {
	elevation, _ := Water_Wave_Sample(x, z, time, speed, strength, height, scale, count)
	return elevation
}
