package classes

import "core:math/linalg"

Cloth_Vertices :: [CLOTH_VERTEX_COUNT][8]f32
Cloth_Indices :: [CLOTH_SEGMENTS * CLOTH_SEGMENTS * 6]u32

Cloth_Build_Surface :: proc(cloth: ^Cloth, vertices: ^Cloth_Vertices, indices: ^Cloth_Indices) {
	n :: CLOTH_SEGMENTS
	stride :: CLOTH_STRIDE
	normals: [CLOTH_VERTEX_COUNT][3]f32
	for row in 0 ..< n {
		for column in 0 ..< n {
			top := u32(row * stride + column)
			index := (row * n + column) * 6
			indices[index + 0] = top
			indices[index + 1] = top + stride
			indices[index + 2] = top + 1
			indices[index + 3] = top + 1
			indices[index + 4] = top + stride
			indices[index + 5] = top + stride + 1
		}
	}
	for i := 0; i < len(indices^); i += 3 {
		a, b, c := indices[i], indices[i + 1], indices[i + 2]
		origin := cloth.particles[a].position
		normal := linalg.cross(
			cloth.particles[b].position - origin,
			cloth.particles[c].position - origin,
		)
		normals[a] += normal
		normals[b] += normal
		normals[c] += normal
	}

	pin := cloth.particles[CLOTH_PIN].position
	for &vertex, i in vertices^ {
		position := cloth.particles[i].position - pin
		normal := linalg.normalize(normals[i])
		if !(linalg.dot(normal, normal) > 0) {normal = {0, 0, 1}}
		vertex = {
			position.x,
			position.y,
			position.z,
			normal.x,
			normal.y,
			normal.z,
			f32(i % stride) / n,
			f32(i / stride) / n,
		}
	}
}

Cloth_Surface_Transform :: proc(cloth: ^Cloth) -> [16]f32 {
	pin := cloth.particles[CLOTH_PIN].position
	return {1, 0, 0, pin.x, 0, 1, 0, pin.y, 0, 0, 1, pin.z, 0, 0, 0, 1}
}
