package classes

import "core:math/linalg"

cloth_free_render_grid :: proc(cloth: ^Cloth) {
	delete(cloth.surface_vertices)
	delete(cloth.decal_vertices)
	delete(cloth.surface_normals)
	delete(cloth.surface_indices)
	delete(cloth.surface_back_indices)
}

cloth_prepare_render_grid :: proc(cloth: ^Cloth) {
	nx := cloth.render_segments_x if cloth.render_segments_x > 0 else cloth.segments_x
	ny := cloth.render_segments_y if cloth.render_segments_y > 0 else cloth.segments_y
	if cloth.render_grid == ([2]int{nx, ny}) {return}
	cloth_free_render_grid(cloth)
	cloth.render_grid = {nx, ny}
	cloth.topology_revision += 1
	count := (nx + 1) * (ny + 1)
	cloth.surface_vertices = make([][8]f32, count)
	cloth.decal_vertices = make([][8]f32, count)
	cloth.surface_normals = make([][3]f32, count)
	cloth.surface_indices = make([]u32, nx * ny * 6)
	cloth.surface_back_indices = make([]u32, nx * ny * 6)

	stride := u32(nx + 1)
	for row in 0..<ny {
		for column in 0..<nx {
			top := u32(row) * stride + u32(column)
			i := (row * nx + column) * 6
			cloth.surface_indices[i + 0] = top
			cloth.surface_indices[i + 1] = top + stride
			cloth.surface_indices[i + 2] = top + 1
			cloth.surface_indices[i + 3] = top + 1
			cloth.surface_indices[i + 4] = top + stride
			cloth.surface_indices[i + 5] = top + stride + 1
		}
	}
	for i := 0; i < len(cloth.surface_indices); i += 3 {
		cloth.surface_back_indices[i + 0] = cloth.surface_indices[i + 0]
		cloth.surface_back_indices[i + 1] = cloth.surface_indices[i + 2]
		cloth.surface_back_indices[i + 2] = cloth.surface_indices[i + 1]
	}
}

cloth_sample_surface :: proc(cloth: ^Cloth, u, v: f32) -> [3]f32 {
	nx, ny := cloth.segments_x, cloth.segments_y
	sx, sy := u * f32(nx), v * f32(ny)
	x, y := min(int(sx), nx - 1), min(int(sy), ny - 1)
	fx, fy := sx - f32(x), sy - f32(y)
	stride := nx + 1
	i := y * stride + x
	b, c := cloth.particles[i + stride].position, cloth.particles[i + 1].position
	if fx + fy <= 1 {
		return cloth.particles[i].position * (1 - fx - fy) + b * fy + c * fx
	}
	return cloth.particles[i + stride + 1].position * (fx + fy - 1) + b * (1 - fx) + c * (1 - fy)
}

Cloth_Build_Surface :: proc(cloth: ^Cloth) {
	topology := cloth.topology_revision
	cloth_prepare_render_grid(cloth)
	if topology == cloth.topology_revision && cloth.surface_revision == cloth.revision {return}

	nx, ny := cloth.render_grid.x, cloth.render_grid.y
	stride := nx + 1
	pin := cloth.particles[cloth.segments_x / 2].position
	for &vertex, i in cloth.surface_vertices {
		u, v := f32(i % stride) / f32(nx), f32(i / stride) / f32(ny)
		position: [3]f32
		if cloth.render_grid == cloth.grid {position = cloth.particles[i].position - pin}
		else {position = cloth_sample_surface(cloth, u, v) - pin}
		vertex = {position.x, position.y, position.z, 0, 0, 0, u, v}
		cloth.surface_normals[i] = {}
	}
	indices := cloth.surface_indices
	vertices := cloth.surface_vertices
	for i := 0; i < len(indices); i += 3 {
		a, b, c := indices[i], indices[i + 1], indices[i + 2]
		origin := [3]f32{vertices[a][0], vertices[a][1], vertices[a][2]}
		ab := [3]f32{vertices[b][0], vertices[b][1], vertices[b][2]} - origin
		ac := [3]f32{vertices[c][0], vertices[c][1], vertices[c][2]} - origin
		normal := linalg.cross(ab, ac)
		cloth.surface_normals[a] += normal
		cloth.surface_normals[b] += normal
		cloth.surface_normals[c] += normal
	}
	for &vertex, i in vertices {
		normal := linalg.normalize(cloth.surface_normals[i])
		if !(linalg.dot(normal, normal) > 0) {normal = {0, 0, 1}}
		vertex[3], vertex[4], vertex[5] = normal.x, normal.y, normal.z
	}
	cloth.surface_revision = cloth.revision
}

Cloth_Surface_Transform :: proc(cloth: ^Cloth) -> [16]f32 {
	pin := cloth.particles[cloth.segments_x / 2].position
	return {1, 0, 0, pin.x, 0, 1, 0, pin.y, 0, 0, 1, pin.z, 0, 0, 0, 1}
}
