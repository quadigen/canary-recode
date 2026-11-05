package services

import assetstore "../assetstore"
import kineffi "../bindings"
import classes "../classes"
import "core:math"
import "core:math/linalg"

SOFTBODY_MAX_MESH_VERTICES :: 32768
SOFTBODY_MAX_PARTICLES :: 8192
SOFTBODY_MAX_INDICES :: 3 * 32768

softbody_prepare_geometry :: proc(body: ^classes.SoftBody) {
	editable: ^classes.EditableMesh
	if body.mesh_content.object_kind == 1 {
		editable = classes.EditableMesh_Of_Handle(body.mesh_content.object_id)
	}
	version := editable != nil ? editable.version : 0
	if !body.mesh_dirty && body.editable_version == version {return}

	classes.SoftBody_Clear_Geometry(body)
	body.mesh_dirty = false
	body.editable_version = version
	body.last_error = ""

	if editable != nil {
		if !softbody_load_editable(body, editable) {
			body.last_error = "EditableMesh has no triangles or exceeds the mesh limit"
			return
		}
	} else {
		uri := body.mesh_content.uri != "" ? body.mesh_content.uri : body.mesh_id
		if uri == "" {
			if body.mesh_content.object_id != 0 {body.last_error = "EditableMesh is unavailable"}
			return
		}
		if !softbody_load_asset(body, uri) {
			body.last_error = "Could not load the mesh or it exceeds the mesh limit"
			return
		}
	}
	if !softbody_weld_geometry(body) {
		classes.SoftBody_Clear_Geometry(body)
		body.last_error = "Mesh has invalid geometry, no usable triangles, or too many particles"
		return
	}
	body.positions = make([]kineffi.JPH_Vec3, len(body.rest_positions))
	copy(body.positions, body.rest_positions[:])
	body.geometry_scale = body.scale
	body.revision += 1
}

softbody_load_asset :: proc(body: ^classes.SoftBody, uri: string) -> bool {
	path := assetstore.Resolve_C_Path(uri)
	if path == nil {
		assetstore.Report_Missing_Asset(uri, "SoftBody mesh")
		return false
	}
	defer delete(path)
	data := kineffi.Kine_Filament_LoadMeshDataFromPathIndexed(path, body.mesh_index)
	if data == nil {return false}
	defer kineffi.Kine_Filament_DestroyMeshData(data)
	vertex_count := kineffi.Kine_Filament_GetMeshDataVertexCount(data)
	index_count := kineffi.Kine_Filament_GetMeshDataIndexCount(data)
	if vertex_count < 3 ||
	   vertex_count > SOFTBODY_MAX_MESH_VERTICES ||
	   index_count < 3 ||
	   index_count > SOFTBODY_MAX_INDICES ||
	   index_count % 3 != 0 {
		return false
	}
	vertices := make([][8]f32, vertex_count)
	indices := make([]u32, index_count)
	if !kineffi.Kine_Filament_CopyMeshDataVertices(data, &vertices[0][0], vertex_count * 8) ||
	   kineffi.Kine_Filament_CopyMeshDataIndices(data, &indices[0], index_count) == 0 {
		delete(vertices)
		delete(indices)
		return false
	}
	body.vertices, body.indices = vertices, indices
	return true
}

softbody_load_editable :: proc(body: ^classes.SoftBody, mesh: ^classes.EditableMesh) -> bool {
	corners: [dynamic]classes.EditableMesh_Corner_Data
	defer delete(corners)
	_ = classes.EditableMesh_Collect_Triangles(mesh, &corners)
	if len(corners) < 3 || len(corners) > SOFTBODY_MAX_MESH_VERTICES {return false}
	body.vertices = make([][8]f32, len(corners))
	body.indices = make([]u32, len(corners))
	for corner, i in corners {
		p, n := corner.position, corner.normal
		body.vertices[i] = {p.x, p.y, p.z, n.x, n.y, n.z, corner.uv.X, corner.uv.Y}
		body.indices[i] = u32(i)
	}
	return true
}

softbody_weld_geometry :: proc(body: ^classes.SoftBody) -> bool {
	welded: map[[3]i64]u32
	defer delete(welded)
	body.vertex_particles = make([]u32, len(body.vertices))
	rest: [dynamic]kineffi.JPH_Vec3
	defer delete(rest)
	for &vertex, i in body.vertices {
		vertex[0] *= body.scale.x
		vertex[1] *= body.scale.y
		vertex[2] *= body.scale.z
		if !(abs(vertex[0]) <= 1e6 && abs(vertex[1]) <= 1e6 && abs(vertex[2]) <= 1e6) {
			return false
		}
		if !physics_finite_f32(vertex[6]) || !physics_finite_f32(vertex[7]) {
			vertex[6], vertex[7] = 0, 0
		}
		key := [3]i64 {
			i64(math.round(f64(vertex[0]) * 1e5)),
			i64(math.round(f64(vertex[1]) * 1e5)),
			i64(math.round(f64(vertex[2]) * 1e5)),
		}
		particle, exists := welded[key]
		if !exists {
			particle = u32(len(rest))
			welded[key] = particle
			append(&rest, kineffi.JPH_Vec3{vertex[0], vertex[1], vertex[2]})
		}
		body.vertex_particles[i] = particle
	}

	used: map[u32]u32
	defer delete(used)
	seen_faces: map[[3]u32]bool
	defer delete(seen_faces)
	render_index := 0
	for i := 0; i < len(body.indices); i += 3 {
		corners := [3]u32{body.indices[i], body.indices[i + 1], body.indices[i + 2]}
		if max(corners[0], corners[1], corners[2]) >= u32(len(body.vertices)) {return false}
		a, b, c :=
			body.vertex_particles[corners[0]],
			body.vertex_particles[corners[1]],
			body.vertex_particles[corners[2]]
		if a == b || b == c || c == a {continue}
		low, high := min(a, b, c), max(a, b, c)
		face_key := [3]u32{low, a + b + c - low - high, high}
		if seen_faces[face_key] {continue}
		pa, pb, pc := rest[a], rest[b], rest[c]
		ab := [3]f32{pb.x - pa.x, pb.y - pa.y, pb.z - pa.z}
		ac := [3]f32{pc.x - pa.x, pc.y - pa.y, pc.z - pa.z}
		area := linalg.cross(ab, ac)
		if !(linalg.dot(area, area) > 1e-20) {continue}
		seen_faces[face_key] = true
		for particle in ([3]u32{a, b, c}) {
			index, exists := used[particle]
			if !exists {
				index = u32(len(body.rest_positions))
				if index >= SOFTBODY_MAX_PARTICLES {return false}
				used[particle] = index
				append(&body.rest_positions, rest[particle])
			}
			append(&body.faces, index)
		}
		copy(body.indices[render_index:render_index + 3], corners[:])
		render_index += 3
	}
	if render_index == 0 {return false}
	// Only draw the faces that survived welding.
	if render_index != len(body.indices) {
		indices := make([]u32, render_index)
		copy(indices, body.indices[:render_index])
		delete(body.indices)
		body.indices = indices
	}
	for &particle in body.vertex_particles {particle = used[particle]}
	body.closed_surface = softbody_orient_closed_surface(body)
	return true
}

softbody_orient_closed_surface :: proc(body: ^classes.SoftBody) -> bool {
	edges: map[[2]u32][2]int
	defer delete(edges)
	origin := body.rest_positions[0]
	volume: f64
	for i := 0; i < len(body.faces); i += 3 {
		triangle := [3]u32{body.faces[i], body.faces[i + 1], body.faces[i + 2]}
		points: [3][3]f64
		for a, j in triangle {
			b := triangle[(j + 1) % 3]
			key := [2]u32{min(a, b), max(a, b)}
			edge := edges[key]
			edge[0] += 1
			edge[1] += a < b ? 1 : -1
			edges[key] = edge
			p := body.rest_positions[a]
			points[j] = {
				f64(p.x) - f64(origin.x),
				f64(p.y) - f64(origin.y),
				f64(p.z) - f64(origin.z),
			}
		}
		volume += linalg.dot(linalg.cross(points[0], points[1]), points[2])
	}
	for _, edge in edges {
		if edge != ([2]int{2, 0}) {return false}
	}
	if abs(volume) < 1e-12 {return false}
	if volume < 0 {
		for i := 0; i < len(body.faces); i += 3 {
			body.faces[i + 1], body.faces[i + 2] = body.faces[i + 2], body.faces[i + 1]
			body.indices[i + 1], body.indices[i + 2] = body.indices[i + 2], body.indices[i + 1]
		}
	}
	return true
}
