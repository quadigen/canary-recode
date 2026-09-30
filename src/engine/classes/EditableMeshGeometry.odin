package classes

import datatypes "../datatypes"
import enums "../enum"
import "core:fmt"
import "core:math"
import "core:strings"

EDITABLE_MESH_NONE :: i32(-1)

EDITABLE_MESH_MAX_VERTICES :: 65532
EDITABLE_MESH_MAX_FACES :: 65532

EDITABLE_MESH_MAX_FACE_VERTICES :: 64
EDITABLE_MESH_MAX_BONES :: 512
EDITABLE_MESH_MAX_BONE_INFLUENCE :: 4

EditableMesh_Color :: struct {
	color: datatypes.Color3,
	alpha: f32,
}

EditableMesh_Face :: struct {
	vertices: [dynamic]i32,
	normals:  [dynamic]i32,
	colors:   [dynamic]i32,
	uvs:      [dynamic]i32,
}

EditableMesh_Bone :: struct {
	name:         string,
	parent:       i32,
	cframe:       datatypes.CFrame,
	is_virtual:   bool,
	bind:         datatypes.CFrame,
	inverse_bind: datatypes.CFrame,
}

EditableMesh_Facs_Pose :: struct {
	action:     enums.FacsActionUnit,
	corrective: bool,
	bone_ids:   [dynamic]i32,
	cframes:    [dynamic]datatypes.CFrame,
}

EditableMesh :: struct {
	using object:    Object,
	fixed_size:      bool,
	version:         u64,
	vertices:        [dynamic]datatypes.Vector3,
	faces:           [dynamic]EditableMesh_Face,
	normals:         [dynamic]datatypes.Vector3,
	colors:          [dynamic]EditableMesh_Color,
	uvs:             [dynamic]datatypes.Vector2,
	vertex_faces:    [dynamic][dynamic]i32,
	vertex_normals:  [dynamic][dynamic]i32,
	vertex_colors:   [dynamic][dynamic]i32,
	vertex_uvs:      [dynamic][dynamic]i32,
	vertex_bones:    [dynamic][dynamic]i32,
	vertex_weights:  [dynamic][dynamic]f32,
	bones:           [dynamic]EditableMesh_Bone,
	facs_poses:      [dynamic]EditableMesh_Facs_Pose,
	adjacency_dirty: bool,
	handle:          u32,
}

editable_mesh_registry: struct {
	slots: [dynamic]^EditableMesh,
	free:  [dynamic]u32,
}

EditableMesh_Of_Handle :: proc(handle: u32) -> ^EditableMesh {
	if handle == 0 || int(handle) > len(editable_mesh_registry.slots) {
		return nil
	}
	return editable_mesh_registry.slots[handle - 1]
}

EditableMesh_Acquire_Handle :: proc(mesh: ^EditableMesh) -> u32 {
	if len(editable_mesh_registry.free) > 0 {
		handle := editable_mesh_registry.free[len(editable_mesh_registry.free) - 1]
		ordered_remove(&editable_mesh_registry.free, len(editable_mesh_registry.free) - 1)
		editable_mesh_registry.slots[handle - 1] = mesh
		return handle
	}

	append(&editable_mesh_registry.slots, mesh)
	return u32(len(editable_mesh_registry.slots))
}

EditableMesh_Release_Handle :: proc(mesh: ^EditableMesh) {
	if mesh == nil || mesh.handle == 0 {return}
	editable_mesh_registry.slots[mesh.handle - 1] = nil
	append(&editable_mesh_registry.free, mesh.handle)
	mesh.handle = 0
}

EditableMesh_Init :: proc() -> EditableMesh {
	mesh := EditableMesh {
		object = Object_Init(&EditableMesh_Class, "EditableMesh"),
	}
	mesh.adjacency_dirty = true
	return mesh
}

EditableMesh_Clear :: proc(mesh: ^EditableMesh) {
	if mesh == nil {return}

	for &face in &mesh.faces {
		delete(face.vertices)
		delete(face.normals)
		delete(face.colors)
		delete(face.uvs)
	}
	delete(mesh.faces)

	delete(mesh.vertices)
	delete(mesh.normals)
	delete(mesh.colors)
	delete(mesh.uvs)

	editable_mesh_clear_vertex_index(mesh)

	for &bone in &mesh.bones {
		delete(bone.name)
	}
	delete(mesh.bones)

	for &pose in &mesh.facs_poses {
		delete(pose.bone_ids)
		delete(pose.cframes)
	}
	delete(mesh.facs_poses)

	mesh.vertices = nil
	mesh.faces = nil
	mesh.normals = nil
	mesh.colors = nil
	mesh.uvs = nil
	mesh.bones = nil
	mesh.facs_poses = nil
	mesh.adjacency_dirty = true

	mesh.version += 1
}

EditableMesh_Free :: proc(mesh: ^EditableMesh) {
	if mesh == nil {return}

	for &face in &mesh.faces {
		delete(face.vertices)
		delete(face.normals)
		delete(face.colors)
		delete(face.uvs)
	}
	delete(mesh.faces)
	delete(mesh.vertices)
	delete(mesh.normals)
	delete(mesh.colors)
	delete(mesh.uvs)

	editable_mesh_clear_vertex_index(mesh)

	for &bone in &mesh.bones {
		delete(bone.name)
	}
	delete(mesh.bones)

	for &pose in &mesh.facs_poses {
		delete(pose.bone_ids)
		delete(pose.cframes)
	}
	delete(mesh.facs_poses)
}

editable_mesh_clear_vertex_index :: proc(mesh: ^EditableMesh) {
	for &entry in &mesh.vertex_faces {delete(entry)}
	mesh.vertex_faces = nil
	for &entry in &mesh.vertex_normals {delete(entry)}
	mesh.vertex_normals = nil
	for &entry in &mesh.vertex_colors {delete(entry)}
	mesh.vertex_colors = nil
	for &entry in &mesh.vertex_uvs {delete(entry)}
	mesh.vertex_uvs = nil

	for &entry in &mesh.vertex_bones {delete(entry)}
	mesh.vertex_bones = nil
	for &entry in &mesh.vertex_weights {delete(entry)}
	mesh.vertex_weights = nil
}

EditableMesh_Touch :: proc(mesh: ^EditableMesh) {
	if mesh == nil {return}
	mesh.version += 1
}

EditableMesh_Touch_Topology :: proc(mesh: ^EditableMesh) {
	if mesh == nil {return}
	mesh.version += 1
	mesh.adjacency_dirty = true
}

editable_mesh_reserve_vertices :: proc(mesh: ^EditableMesh, count: int) -> bool {
	if len(mesh.vertices) + count > EDITABLE_MESH_MAX_VERTICES {
		return false
	}
	return true
}

EditableMesh_Can_Grow :: proc(mesh: ^EditableMesh, count: int) -> bool {
	if count <= 0 {return true}
	if mesh.fixed_size {return false}
	return editable_mesh_reserve_vertices(mesh, count)
}

editable_mesh_valid_vertex :: proc(mesh: ^EditableMesh, id: i32) -> bool {
	return id >= 0 && int(id) < len(mesh.vertices)
}

editable_mesh_valid_face :: proc(mesh: ^EditableMesh, id: i32) -> bool {
	return id >= 0 && int(id) < len(mesh.faces)
}

editable_mesh_valid_normal :: proc(mesh: ^EditableMesh, id: i32) -> bool {
	return id >= 0 && int(id) < len(mesh.normals)
}

editable_mesh_valid_color :: proc(mesh: ^EditableMesh, id: i32) -> bool {
	return id >= 0 && int(id) < len(mesh.colors)
}

editable_mesh_valid_uv :: proc(mesh: ^EditableMesh, id: i32) -> bool {
	return id >= 0 && int(id) < len(mesh.uvs)
}

editable_mesh_valid_bone :: proc(mesh: ^EditableMesh, id: i32) -> bool {
	return id >= 0 && int(id) < len(mesh.bones)
}

editable_mesh_valid_position :: proc(value: datatypes.Vector3) -> bool {
	return(
		editable_mesh_finite(value.x) &&
		editable_mesh_finite(value.y) &&
		editable_mesh_finite(value.z) \
	)
}

editable_mesh_finite :: proc(value: f32) -> bool {
	return value == value && value > -1.0e18 && value < 1.0e18
}

// ---------------------------------------------------------------------------
// Attribute pools
// ---------------------------------------------------------------------------

EditableMesh_Add_Vertex :: proc(mesh: ^EditableMesh, position: datatypes.Vector3) -> i32 {
	if mesh == nil || !EditableMesh_Can_Grow(mesh, 1) {return EDITABLE_MESH_NONE}
	value := position
	if !editable_mesh_valid_position(value) {value = datatypes.Vector3{}}
	append(&mesh.vertices, value)
	append(&mesh.vertex_bones, nil)
	append(&mesh.vertex_weights, nil)
	EditableMesh_Touch_Topology(mesh)
	return i32(len(mesh.vertices) - 1)
}

EditableMesh_Set_Position :: proc(
	mesh: ^EditableMesh,
	vertex_id: i32,
	position: datatypes.Vector3,
) -> bool {
	if !editable_mesh_valid_vertex(mesh, vertex_id) {return false}
	if !editable_mesh_valid_position(position) {return false}
	mesh.vertices[vertex_id] = position
	EditableMesh_Touch(mesh)
	return true
}

EditableMesh_Add_Normal :: proc(mesh: ^EditableMesh, normal: datatypes.Vector3) -> i32 {
	if mesh == nil || mesh.fixed_size {return EDITABLE_MESH_NONE}
	value := normal
	if !editable_mesh_valid_position(value) {value = datatypes.Vector3{}}
	append(&mesh.normals, value)
	EditableMesh_Touch(mesh)
	return i32(len(mesh.normals) - 1)
}

EditableMesh_Set_Normal :: proc(
	mesh: ^EditableMesh,
	normal_id: i32,
	normal: datatypes.Vector3,
) -> bool {
	if !editable_mesh_valid_normal(mesh, normal_id) {return false}
	if !editable_mesh_valid_position(normal) {return false}
	mesh.normals[normal_id] = normal
	EditableMesh_Touch(mesh)
	return true
}

EditableMesh_Reset_Normal :: proc(mesh: ^EditableMesh, normal_id: i32) -> bool {
	if !editable_mesh_valid_normal(mesh, normal_id) {return false}
	mesh.normals[normal_id] = datatypes.Vector3{}
	EditableMesh_Touch(mesh)
	return true
}

EditableMesh_Add_Color :: proc(mesh: ^EditableMesh, color: datatypes.Color3, alpha: f32) -> i32 {
	if mesh == nil || mesh.fixed_size {return EDITABLE_MESH_NONE}
	entry := EditableMesh_Color {
		color = color,
		alpha = clamp(alpha, 0.0, 1.0),
	}
	append(&mesh.colors, entry)
	EditableMesh_Touch(mesh)
	return i32(len(mesh.colors) - 1)
}

EditableMesh_Set_Color :: proc(
	mesh: ^EditableMesh,
	color_id: i32,
	color: datatypes.Color3,
	alpha: f32,
) -> bool {
	if !editable_mesh_valid_color(mesh, color_id) {return false}
	mesh.colors[color_id] = EditableMesh_Color {
		color = color,
		alpha = clamp(alpha, 0.0, 1.0),
	}
	EditableMesh_Touch(mesh)
	return true
}

EditableMesh_Add_UV :: proc(mesh: ^EditableMesh, uv: datatypes.Vector2) -> i32 {
	if mesh == nil || mesh.fixed_size {return EDITABLE_MESH_NONE}
	value := uv
	if !editable_mesh_finite(value.X) || !editable_mesh_finite(value.Y) {
		value = datatypes.Vector2{}
	}
	append(&mesh.uvs, value)
	EditableMesh_Touch(mesh)
	return i32(len(mesh.uvs) - 1)
}

EditableMesh_Set_UV :: proc(mesh: ^EditableMesh, uv_id: i32, uv: datatypes.Vector2) -> bool {
	if !editable_mesh_valid_uv(mesh, uv_id) {return false}
	if !editable_mesh_finite(uv.X) || !editable_mesh_finite(uv.Y) {return false}
	mesh.uvs[uv_id] = uv
	EditableMesh_Touch(mesh)
	return true
}

// ---------------------------------------------------------------------------
// Faces
// ---------------------------------------------------------------------------

editable_mesh_face_has_vertex :: proc(
	mesh: ^EditableMesh,
	face: ^EditableMesh_Face,
	vertex_id: i32,
) -> bool {
	for id in face.vertices {
		if id == vertex_id {return true}
	}
	return false
}

EditableMesh_Face_Normal :: proc(mesh: ^EditableMesh, face_id: i32) -> datatypes.Vector3 {
	if !editable_mesh_valid_face(mesh, face_id) {return datatypes.Vector3{}}
	face := &mesh.faces[face_id]
	if len(face.vertices) < 3 {return datatypes.Vector3{}}

	first := face.vertices[0]
	if !editable_mesh_valid_vertex(mesh, first) {return datatypes.Vector3{}}
	a := mesh.vertices[first]

	for i in 1 ..< len(face.vertices) - 1 {
		if !editable_mesh_valid_vertex(mesh, face.vertices[i]) ||
		   !editable_mesh_valid_vertex(mesh, face.vertices[i + 1]) {
			return datatypes.Vector3{}
		}
		b := mesh.vertices[face.vertices[i]]
		c := mesh.vertices[face.vertices[i + 1]]
		normal := datatypes.Vec3_Cross(
			datatypes.Vec3_Subtract(b, a),
			datatypes.Vec3_Subtract(c, a),
		)
		if datatypes.Vec3_Magnitude_Squared(normal) > 1.0e-16 {
			return datatypes.Vec3_Unit(normal)
		}
	}

	return datatypes.Vector3{}
}

EditableMesh_Face_Color :: proc(mesh: ^EditableMesh, face_id: i32) -> datatypes.Color3 {
	if !editable_mesh_valid_face(mesh, face_id) {return datatypes.Color3{R = 1, G = 1, B = 1}}
	face := &mesh.faces[face_id]
	for id in face.colors {
		if editable_mesh_valid_color(mesh, id) {
			return mesh.colors[id].color
		}
	}
	return datatypes.Color3{R = 1, G = 1, B = 1}
}

editable_mesh_validate_face_vertices :: proc(mesh: ^EditableMesh, ids: []i32) -> bool {
	if len(ids) < 3 || len(ids) > EDITABLE_MESH_MAX_FACE_VERTICES {return false}
	for id in ids {
		if !editable_mesh_valid_vertex(mesh, id) {return false}
	}
	for i in 0 ..< len(ids) {
		for j in i + 1 ..< len(ids) {
			if ids[i] == ids[j] {return false}
		}
	}
	return true
}

editable_mesh_copy_ids :: proc(ids: []i32) -> [dynamic]i32 {
	result := make([dynamic]i32, len(ids))
	copy(result[:], ids)
	return result
}

editable_mesh_fill_none :: proc(ids: ^[dynamic]i32, count: int) {
	delete(ids^)
	for _ in 0 ..< count {
		append(ids, EDITABLE_MESH_NONE)
	}
}

EditableMesh_Add_Face :: proc(mesh: ^EditableMesh, ids: []i32) -> i32 {
	if mesh == nil {return EDITABLE_MESH_NONE}
	if len(mesh.faces) >= EDITABLE_MESH_MAX_FACES {return EDITABLE_MESH_NONE}
	if !editable_mesh_validate_face_vertices(mesh, ids) {return EDITABLE_MESH_NONE}

	face := EditableMesh_Face {
		vertices = editable_mesh_copy_ids(ids),
	}
	editable_mesh_fill_none(&face.normals, len(ids))
	editable_mesh_fill_none(&face.colors, len(ids))
	editable_mesh_fill_none(&face.uvs, len(ids))

	append(&mesh.faces, face)

	if len(ids) == 3 && !mesh.fixed_size {
		normal_id := EditableMesh_Add_Normal(
			mesh,
			EditableMesh_Face_Normal(mesh, i32(len(mesh.faces) - 1)),
		)
		if normal_id != EDITABLE_MESH_NONE {
			mesh.faces[len(mesh.faces) - 1].normals[0] = normal_id
			mesh.faces[len(mesh.faces) - 1].normals[1] = normal_id
			mesh.faces[len(mesh.faces) - 1].normals[2] = normal_id
		}
	}

	EditableMesh_Touch_Topology(mesh)
	return i32(len(mesh.faces) - 1)
}

EditableMesh_Remove_Face :: proc(mesh: ^EditableMesh, face_id: i32) -> bool {
	if !editable_mesh_valid_face(mesh, face_id) {return false}
	face := &mesh.faces[face_id]
	delete(face.vertices)
	delete(face.normals)
	delete(face.colors)
	delete(face.uvs)
	ordered_remove(&mesh.faces, face_id)
	EditableMesh_Touch_Topology(mesh)
	return true
}

EditableMesh_Set_Face_Vertices :: proc(mesh: ^EditableMesh, face_id: i32, ids: []i32) -> bool {
	if !editable_mesh_valid_face(mesh, face_id) {return false}
	if !editable_mesh_validate_face_vertices(mesh, ids) {return false}

	face := &mesh.faces[face_id]
	delete(face.vertices)
	face.vertices = editable_mesh_copy_ids(ids)
	editable_mesh_fill_none(&face.normals, len(ids))
	editable_mesh_fill_none(&face.colors, len(ids))
	editable_mesh_fill_none(&face.uvs, len(ids))

	EditableMesh_Touch_Topology(mesh)
	return true
}

editable_mesh_assign_ids :: proc(
	mesh: ^EditableMesh,
	ids: []i32,
	valid: proc(mesh: ^EditableMesh, id: i32) -> bool,
) -> bool {
	for id in ids {
		if !valid(mesh, id) {return false}
	}
	return true
}

EditableMesh_Set_Face_Normals :: proc(mesh: ^EditableMesh, face_id: i32, ids: []i32) -> bool {
	if !editable_mesh_valid_face(mesh, face_id) {return false}
	if !editable_mesh_assign_ids(mesh, ids, editable_mesh_valid_normal) {return false}

	face := &mesh.faces[face_id]
	delete(face.normals)
	face.normals = editable_mesh_copy_ids(ids)
	EditableMesh_Touch(mesh)
	return true
}

EditableMesh_Set_Face_Colors :: proc(mesh: ^EditableMesh, face_id: i32, ids: []i32) -> bool {
	if !editable_mesh_valid_face(mesh, face_id) {return false}
	if !editable_mesh_assign_ids(mesh, ids, editable_mesh_valid_color) {return false}

	face := &mesh.faces[face_id]
	delete(face.colors)
	face.colors = editable_mesh_copy_ids(ids)
	EditableMesh_Touch(mesh)
	return true
}

EditableMesh_Set_Face_UVs :: proc(mesh: ^EditableMesh, face_id: i32, ids: []i32) -> bool {
	if !editable_mesh_valid_face(mesh, face_id) {return false}
	if !editable_mesh_assign_ids(mesh, ids, editable_mesh_valid_uv) {return false}

	face := &mesh.faces[face_id]
	delete(face.uvs)
	face.uvs = editable_mesh_copy_ids(ids)
	EditableMesh_Touch(mesh)
	return true
}

editable_mesh_corner :: proc(face: ^EditableMesh_Face, vertex_id: i32) -> int {
	for vertex, corner in face.vertices {
		if vertex == vertex_id {return corner}
	}
	return -1
}

EditableMesh_Get_Vertex_Face_Normal :: proc(
	mesh: ^EditableMesh,
	vertex_id: i32,
	face_id: i32,
) -> i32 {
	if !editable_mesh_valid_vertex(mesh, vertex_id) || !editable_mesh_valid_face(mesh, face_id) {
		return EDITABLE_MESH_NONE
	}
	face := &mesh.faces[face_id]
	corner := editable_mesh_corner(face, vertex_id)
	if corner < 0 || corner >= len(face.normals) {return EDITABLE_MESH_NONE}
	return face.normals[corner]
}

EditableMesh_Get_Vertex_Face_Color :: proc(
	mesh: ^EditableMesh,
	vertex_id: i32,
	face_id: i32,
) -> i32 {
	if !editable_mesh_valid_vertex(mesh, vertex_id) || !editable_mesh_valid_face(mesh, face_id) {
		return EDITABLE_MESH_NONE
	}
	face := &mesh.faces[face_id]
	corner := editable_mesh_corner(face, vertex_id)
	if corner < 0 || corner >= len(face.colors) {return EDITABLE_MESH_NONE}
	return face.colors[corner]
}

EditableMesh_Get_Vertex_Face_UV :: proc(mesh: ^EditableMesh, vertex_id: i32, face_id: i32) -> i32 {
	if !editable_mesh_valid_vertex(mesh, vertex_id) || !editable_mesh_valid_face(mesh, face_id) {
		return EDITABLE_MESH_NONE
	}
	face := &mesh.faces[face_id]
	corner := editable_mesh_corner(face, vertex_id)
	if corner < 0 || corner >= len(face.uvs) {return EDITABLE_MESH_NONE}
	return face.uvs[corner]
}

EditableMesh_Set_Vertex_Face_Attribute :: proc(
	mesh: ^EditableMesh,
	vertex_id: i32,
	face_id: i32,
	attr_id: i32,
	attr: enums.MeshAttribute,
) -> bool {
	if !editable_mesh_valid_vertex(mesh, vertex_id) || !editable_mesh_valid_face(mesh, face_id) {
		return false
	}
	face := &mesh.faces[face_id]
	corner := editable_mesh_corner(face, vertex_id)
	if corner < 0 {return false}

	#partial switch attr {
	case .Normal:
		if !editable_mesh_valid_normal(mesh, attr_id) {return false}
		if corner >= len(face.normals) {return false}
		face.normals[corner] = attr_id
	case .Color:
		if !editable_mesh_valid_color(mesh, attr_id) {return false}
		if corner >= len(face.colors) {return false}
		face.colors[corner] = attr_id
	case .UV:
		if !editable_mesh_valid_uv(mesh, attr_id) {return false}
		if corner >= len(face.uvs) {return false}
		face.uvs[corner] = attr_id
	case:
		return false
	}

	EditableMesh_Touch_Topology(mesh)
	return true
}

// ---------------------------------------------------------------------------
// Vertex adjacency
// ---------------------------------------------------------------------------

editable_mesh_push_unique :: proc(list: ^[dynamic]i32, value: i32) {
	for id in list^ {
		if id == value {return}
	}
	append(list, value)
}

EditableMesh_Ensure_Vertex_Index :: proc(mesh: ^EditableMesh) {
	if mesh == nil || !mesh.adjacency_dirty {return}
	mesh.adjacency_dirty = false

	for &entry in &mesh.vertex_faces {delete(entry)}
	delete(mesh.vertex_faces)
	for &entry in &mesh.vertex_normals {delete(entry)}
	delete(mesh.vertex_normals)
	for &entry in &mesh.vertex_colors {delete(entry)}
	delete(mesh.vertex_colors)
	for &entry in &mesh.vertex_uvs {delete(entry)}
	delete(mesh.vertex_uvs)

	mesh.vertex_faces = make([dynamic][dynamic]i32, len(mesh.vertices))
	mesh.vertex_normals = make([dynamic][dynamic]i32, len(mesh.vertices))
	mesh.vertex_colors = make([dynamic][dynamic]i32, len(mesh.vertices))
	mesh.vertex_uvs = make([dynamic][dynamic]i32, len(mesh.vertices))

	if len(mesh.vertex_bones) != len(mesh.vertices) {
		for &entry in &mesh.vertex_bones {delete(entry)}
		for &entry in &mesh.vertex_weights {delete(entry)}
		delete(mesh.vertex_bones)
		delete(mesh.vertex_weights)
		mesh.vertex_bones = make([dynamic][dynamic]i32, len(mesh.vertices))
		mesh.vertex_weights = make([dynamic][dynamic]f32, len(mesh.vertices))
	}

	for &face, face_id in &mesh.faces {
		for vertex_id, corner in face.vertices {
			if !editable_mesh_valid_vertex(mesh, vertex_id) {continue}
			editable_mesh_push_unique(&mesh.vertex_faces[vertex_id], i32(face_id))
			if corner < len(face.normals) {
				editable_mesh_push_unique(&mesh.vertex_normals[vertex_id], face.normals[corner])
			}
			if corner < len(face.colors) {
				editable_mesh_push_unique(&mesh.vertex_colors[vertex_id], face.colors[corner])
			}
			if corner < len(face.uvs) {
				editable_mesh_push_unique(&mesh.vertex_uvs[vertex_id], face.uvs[corner])
			}
		}
	}
}

EditableMesh_Get_Vertex_Faces :: proc(mesh: ^EditableMesh, vertex_id: i32) -> [dynamic]i32 {
	result: [dynamic]i32
	if !editable_mesh_valid_vertex(mesh, vertex_id) {return result}
	EditableMesh_Ensure_Vertex_Index(mesh)
	if int(vertex_id) >= len(mesh.vertex_faces) {return result}
	result = make([dynamic]i32, len(mesh.vertex_faces[vertex_id]))
	copy(result[:], mesh.vertex_faces[vertex_id][:])
	return result
}

editable_mesh_collect_attribute_ids :: proc(
	mesh: ^EditableMesh,
	vertex_id: i32,
	list: [dynamic][dynamic]i32,
) -> [dynamic]i32 {
	result: [dynamic]i32
	if !editable_mesh_valid_vertex(mesh, vertex_id) || int(vertex_id) >= len(list) {return result}
	for &id in list[vertex_id] {
		if id != EDITABLE_MESH_NONE {
			editable_mesh_push_unique(&result, id)
		}
	}
	return result
}

EditableMesh_Get_Vertex_Normals :: proc(mesh: ^EditableMesh, vertex_id: i32) -> [dynamic]i32 {
	EditableMesh_Ensure_Vertex_Index(mesh)
	return editable_mesh_collect_attribute_ids(mesh, vertex_id, mesh.vertex_normals)
}

EditableMesh_Get_Vertex_Colors :: proc(mesh: ^EditableMesh, vertex_id: i32) -> [dynamic]i32 {
	EditableMesh_Ensure_Vertex_Index(mesh)
	return editable_mesh_collect_attribute_ids(mesh, vertex_id, mesh.vertex_colors)
}

EditableMesh_Get_Vertex_UVs :: proc(mesh: ^EditableMesh, vertex_id: i32) -> [dynamic]i32 {
	EditableMesh_Ensure_Vertex_Index(mesh)
	return editable_mesh_collect_attribute_ids(mesh, vertex_id, mesh.vertex_uvs)
}

EditableMesh_Get_Adjacent_Faces :: proc(mesh: ^EditableMesh, face_id: i32) -> [dynamic]i32 {
	result: [dynamic]i32
	if !editable_mesh_valid_face(mesh, face_id) {return result}

	source := &mesh.faces[face_id]
	for candidate in 0 ..< len(mesh.faces) {
		if candidate == int(face_id) {continue}
		other := &mesh.faces[candidate]
		shares := false
		for id in source.vertices {
			if editable_mesh_face_has_vertex(mesh, other, id) {
				shares = true
				break
			}
		}
		if shares {
			append(&result, i32(candidate))
		}
	}

	return result
}

EditableMesh_Get_Adjacent_Vertices :: proc(mesh: ^EditableMesh, vertex_id: i32) -> [dynamic]i32 {
	result: [dynamic]i32
	if !editable_mesh_valid_vertex(mesh, vertex_id) {return result}

	for &face in &mesh.faces {
		if !editable_mesh_face_has_vertex(mesh, &face, vertex_id) {continue}
		for other in face.vertices {
			if other == vertex_id {continue}
			editable_mesh_push_unique(&result, other)
		}
	}

	return result
}

// ---------------------------------------------------------------------------
// Bounds and spatial queries
// ---------------------------------------------------------------------------

EditableMesh_Get_Size :: proc(mesh: ^EditableMesh) -> datatypes.Vector3 {
	if mesh == nil || len(mesh.vertices) == 0 {return datatypes.Vector3{}}

	minimum := mesh.vertices[0]
	maximum := mesh.vertices[0]
	for index in 1 ..< len(mesh.vertices) {
		position := mesh.vertices[index]
		minimum = datatypes.Vec3_Min(minimum, position)
		maximum = datatypes.Vec3_Max(maximum, position)
	}

	return datatypes.Vec3_Subtract(maximum, minimum)
}

EditableMesh_Get_Center :: proc(mesh: ^EditableMesh) -> datatypes.Vector3 {
	if mesh == nil || len(mesh.vertices) == 0 {return datatypes.Vector3{}}

	minimum := mesh.vertices[0]
	maximum := mesh.vertices[0]
	for index in 1 ..< len(mesh.vertices) {
		position := mesh.vertices[index]
		minimum = datatypes.Vec3_Min(minimum, position)
		maximum = datatypes.Vec3_Max(maximum, position)
	}

	return datatypes.Vec3_Multiply(datatypes.Vec3_Add(minimum, maximum), 0.5)
}

EditableMesh_Find_Closest_Vertex :: proc(mesh: ^EditableMesh, point: datatypes.Vector3) -> i32 {
	if mesh == nil || len(mesh.vertices) == 0 {return EDITABLE_MESH_NONE}

	best := EDITABLE_MESH_NONE
	best_distance := f32(0)
	for &position, index in &mesh.vertices {
		delta := datatypes.Vec3_Subtract(position, point)
		distance := datatypes.Vec3_Magnitude_Squared(delta)
		if best == EDITABLE_MESH_NONE || distance < best_distance {
			best = i32(index)
			best_distance = distance
		}
	}

	return best
}

EditableMesh_Find_Vertices_Within_Sphere :: proc(
	mesh: ^EditableMesh,
	center: datatypes.Vector3,
	radius: f32,
) -> [dynamic]i32 {
	result: [dynamic]i32
	if mesh == nil || radius < 0 {return result}

	radius_squared := radius * radius
	for &position, index in &mesh.vertices {
		delta := datatypes.Vec3_Subtract(position, center)
		if datatypes.Vec3_Magnitude_Squared(delta) <= radius_squared {
			append(&result, i32(index))
		}
	}

	return result
}

editable_mesh_closest_point_on_triangle :: proc(
	point: datatypes.Vector3,
	a, b, c: datatypes.Vector3,
) -> (
	position: datatypes.Vector3,
	barycentric: datatypes.Vector3,
) {
	ab := datatypes.Vec3_Subtract(b, a)
	ac := datatypes.Vec3_Subtract(c, a)
	ap := datatypes.Vec3_Subtract(point, a)

	d1 := datatypes.Vec3_Dot(ab, ap)
	d2 := datatypes.Vec3_Dot(ac, ap)
	if d1 <= 0 && d2 <= 0 {
		return a, datatypes.Vector3{1, 0, 0}
	}

	bp := datatypes.Vec3_Subtract(point, b)
	d3 := datatypes.Vec3_Dot(ab, bp)
	d4 := datatypes.Vec3_Dot(ac, bp)
	if d3 >= 0 && d4 <= d3 {
		return b, datatypes.Vector3{0, 1, 0}
	}

	vc := d1 * d4 - d3 * d2
	if vc <= 0 && d1 >= 0 && d3 <= 0 {
		v := d1 / (d1 - d3)
		return datatypes.Vec3_Add(
			a,
			datatypes.Vec3_Multiply(ab, v),
		), datatypes.Vector3{1 - v, v, 0}
	}

	cp := datatypes.Vec3_Subtract(point, c)
	d5 := datatypes.Vec3_Dot(ab, cp)
	d6 := datatypes.Vec3_Dot(ac, cp)
	if d6 >= 0 && d5 <= d6 {
		return c, datatypes.Vector3{0, 0, 1}
	}

	vb := d5 * d2 - d1 * d6
	if vb <= 0 && d2 >= 0 && d6 <= 0 {
		w := d2 / (d2 - d6)
		return datatypes.Vec3_Add(
			a,
			datatypes.Vec3_Multiply(ac, w),
		), datatypes.Vector3{1 - w, 0, w}
	}

	va := d3 * d6 - d5 * d4
	if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0 {
		w := (d4 - d3) / ((d4 - d3) + (d5 - d6))
		return datatypes.Vec3_Add(
			b,
			datatypes.Vec3_Multiply(datatypes.Vec3_Subtract(c, b), w),
		), datatypes.Vector3{0, 1 - w, w}
	}

	denominator := va + vb + vc
	if math.abs(denominator) < 1.0e-12 {
		return a, datatypes.Vector3{1, 0, 0}
	}

	v := vb / denominator
	w := vc / denominator
	return datatypes.Vec3_Add(
		a,
		datatypes.Vec3_Add(datatypes.Vec3_Multiply(ab, v), datatypes.Vec3_Multiply(ac, w)),
	), datatypes.Vector3{1 - v - w, v, w}
}

// EditableMesh_Triangle_Iterator drives every polygon through a triangle fan.
// Faces carry an arbitrary number of vertices, and both the renderer and the
// collider need the same fan so a polygon and the triangles it degenerates to
// can never disagree.
EditableMesh_Triangle_Iterator :: struct {
	mesh: ^EditableMesh,
}

EditableMesh_Triangles :: proc(
	mesh: ^EditableMesh,
	step: proc(
		mesh: ^EditableMesh,
		face_id: i32,
		a_id: i32,
		b_id: i32,
		c_id: i32,
		a: datatypes.Vector3,
		b: datatypes.Vector3,
		c: datatypes.Vector3,
	) -> bool,
) -> bool {
	if mesh == nil {return false}

	for &face, face_id in &mesh.faces {
		if len(face.vertices) < 3 {continue}
		for corner in 1 ..< len(face.vertices) - 1 {
			a_id := face.vertices[0]
			b_id := face.vertices[corner]
			c_id := face.vertices[corner + 1]
			if !editable_mesh_valid_vertex(mesh, a_id) ||
			   !editable_mesh_valid_vertex(mesh, b_id) ||
			   !editable_mesh_valid_vertex(mesh, c_id) {
				continue
			}
			if !step(
				mesh,
				i32(face_id),
				a_id,
				b_id,
				c_id,
				mesh.vertices[a_id],
				mesh.vertices[b_id],
				mesh.vertices[c_id],
			) {
				return false
			}
		}
	}

	return true
}

EditableMesh_Closest_Point_On_Surface :: proc(
	mesh: ^EditableMesh,
	point: datatypes.Vector3,
) -> (
	position: datatypes.Vector3,
	face_id: i32,
	barycentric: datatypes.Vector3,
) {
	face_id = EDITABLE_MESH_NONE
	if mesh == nil {return point, face_id, datatypes.Vector3{1, 0, 0}}

	best_distance := f32(0)
	found := false

	for &face, current_face in &mesh.faces {
		if len(face.vertices) < 3 {continue}
		for corner in 1 ..< len(face.vertices) - 1 {
			a_id := face.vertices[0]
			b_id := face.vertices[corner]
			c_id := face.vertices[corner + 1]
			if !editable_mesh_valid_vertex(mesh, a_id) ||
			   !editable_mesh_valid_vertex(mesh, b_id) ||
			   !editable_mesh_valid_vertex(mesh, c_id) {
				continue
			}
			candidate, weights := editable_mesh_closest_point_on_triangle(
				point,
				mesh.vertices[a_id],
				mesh.vertices[b_id],
				mesh.vertices[c_id],
			)
			delta := datatypes.Vec3_Subtract(candidate, point)
			distance := datatypes.Vec3_Magnitude_Squared(delta)
			if !found || distance < best_distance {
				found = true
				best_distance = distance
				face_id = i32(current_face)
				position = candidate
				barycentric = weights
			}
		}
	}

	if !found {
		position = point
		barycentric = datatypes.Vector3{1, 0, 0}
	}

	return position, face_id, barycentric
}

EditableMesh_Raycast_Local :: proc(
	mesh: ^EditableMesh,
	origin: datatypes.Vector3,
	direction: datatypes.Vector3,
) -> (
	face_id: i32,
	point: datatypes.Vector3,
	barycentric: datatypes.Vector3,
	vertex_ids: datatypes.Vector3,
) {
	face_id = EDITABLE_MESH_NONE
	if mesh == nil {return face_id, datatypes.Vector3{}, datatypes.Vector3{}, datatypes.Vector3{}}

	direction_length := datatypes.Vec3_Magnitude(direction)
	if direction_length <=
	   1.0e-9 {return face_id, datatypes.Vector3{}, datatypes.Vector3{}, datatypes.Vector3{}}
	normalized := datatypes.Vec3_Multiply(direction, 1.0 / direction_length)

	best_distance := f32(0)
	found := false

	for &face, current_face in &mesh.faces {
		if len(face.vertices) < 3 {continue}
		for corner in 1 ..< len(face.vertices) - 1 {
			a_id := face.vertices[0]
			b_id := face.vertices[corner]
			c_id := face.vertices[corner + 1]
			if !editable_mesh_valid_vertex(mesh, a_id) ||
			   !editable_mesh_valid_vertex(mesh, b_id) ||
			   !editable_mesh_valid_vertex(mesh, c_id) {
				continue
			}
			a := mesh.vertices[a_id]
			b := mesh.vertices[b_id]
			c := mesh.vertices[c_id]

			edge1 := datatypes.Vec3_Subtract(b, a)
			edge2 := datatypes.Vec3_Subtract(c, a)
			pvec := datatypes.Vec3_Cross(normalized, edge2)
			determinant := datatypes.Vec3_Dot(edge1, pvec)
			if math.abs(determinant) < 1.0e-9 {continue}

			inv := 1.0 / determinant
			tvec := datatypes.Vec3_Subtract(origin, a)
			u := datatypes.Vec3_Dot(tvec, pvec) * inv
			if u < 0 || u > 1 {continue}

			qvec := datatypes.Vec3_Cross(tvec, edge1)
			v := datatypes.Vec3_Dot(normalized, qvec) * inv
			if v < 0 || u + v > 1 {continue}

			distance := datatypes.Vec3_Dot(edge2, qvec) * inv
			if distance < 1.0e-6 {continue}
			if found && distance >= best_distance {continue}

			found = true
			best_distance = distance
			face_id = i32(current_face)
			point = datatypes.Vec3_Add(origin, datatypes.Vec3_Multiply(normalized, distance))
			barycentric = datatypes.Vector3{1 - u - v, u, v}
			vertex_ids = datatypes.Vector3{f32(a_id), f32(b_id), f32(c_id)}
		}
	}

	if !found {
		return EDITABLE_MESH_NONE, datatypes.Vector3{}, datatypes.Vector3{}, datatypes.Vector3{}
	}

	return face_id, point, barycentric, vertex_ids
}

// ---------------------------------------------------------------------------
// Editing operations
// ---------------------------------------------------------------------------

EditableMesh_Triangulate :: proc(mesh: ^EditableMesh) -> bool {
	if mesh == nil || mesh.fixed_size {return false}

	changed := false
	next := make([dynamic]EditableMesh_Face, 0, len(mesh.faces))

	for &face in mesh.faces {
		if len(face.vertices) <= 3 {
			append(&next, face)
			face.vertices = nil
			face.normals = nil
			face.colors = nil
			face.uvs = nil
			continue
		}

		changed = true
		for corner in 1 ..< len(face.vertices) - 1 {
			ids := [3]i32{face.vertices[0], face.vertices[corner], face.vertices[corner + 1]}
			triangle := EditableMesh_Face {
				vertices = editable_mesh_copy_ids(ids[:]),
			}
			editable_mesh_fill_none(&triangle.normals, 3)
			editable_mesh_fill_none(&triangle.colors, 3)
			editable_mesh_fill_none(&triangle.uvs, 3)

			positions := [3]int{0, corner, corner + 1}
			for slot in 0 ..< 3 {
				source := positions[slot]
				if source < len(face.normals) {triangle.normals[slot] = face.normals[source]}
				if source < len(face.colors) {triangle.colors[slot] = face.colors[source]}
				if source < len(face.uvs) {triangle.uvs[slot] = face.uvs[source]}
			}

			append(&next, triangle)
		}

		delete(face.vertices)
		delete(face.normals)
		delete(face.colors)
		delete(face.uvs)
	}

	if !changed {
		for index in 0 ..< len(mesh.faces) {
			mesh.faces[index] = next[index]
		}
		delete(next)
		return false
	}

	delete(mesh.faces)
	mesh.faces = next

	EditableMesh_Touch_Topology(mesh)
	return true
}

editable_mesh_weld :: proc(
	mesh: ^EditableMesh,
	tolerance: f32,
	touch_topology: bool,
) -> [dynamic]i32 {
	remap := make([dynamic]i32, len(mesh.vertices))
	for index in 0 ..< len(mesh.vertices) {
		remap[index] = i32(index)
	}

	tolerance_squared := max(tolerance, 0) * max(tolerance, 0)

	bucket := EDITABLE_MESH_WELD_CELL
	if bucket <= 0 {bucket = 0.5}
	occupied := make(map[[3]i32]i32)

	for &position, index in &mesh.vertices {
		if tolerance <= 0 {
			key := [3]i32 {
				i32(math.floor(position.x * 1.0e6)),
				i32(math.floor(position.y * 1.0e6)),
				i32(math.floor(position.z * 1.0e6)),
			}
			if existing, found := occupied[key]; found {
				remap[index] = existing
				continue
			}
			occupied[key] = i32(index)
			continue
		}

		cell := [3]int {
			int(math.floor(position.x / bucket)),
			int(math.floor(position.y / bucket)),
			int(math.floor(position.z / bucket)),
		}

		merged := false
		for dx in -1 ..= 1 {
			if merged {break}
			for dy in -1 ..= 1 {
				if merged {break}
				for dz in -1 ..= 1 {
					key := [3]i32{i32(cell.x + dx), i32(cell.y + dy), i32(cell.z + dz)}
					candidate, found := occupied[key]
					if !found {continue}
					delta := datatypes.Vec3_Subtract(mesh.vertices[candidate], position)
					if datatypes.Vec3_Magnitude_Squared(delta) <= tolerance_squared {
						remap[index] = candidate
						merged = true
						break
					}
				}
			}
		}

		if !merged {
			occupied[[3]i32{i32(cell.x), i32(cell.y), i32(cell.z)}] = i32(index)
		}
	}

	delete(occupied)

	compacted := make([dynamic]datatypes.Vector3, 0, len(mesh.vertices))
	for index in 0 ..< len(mesh.vertices) {
		representative := remap[index]
		if representative != i32(index) {
			remap[index] = remap[representative]
			continue
		}
		remap[index] = i32(len(compacted))
		append(&compacted, mesh.vertices[index])
	}

	vertices := compacted
	mesh.vertices = make([dynamic]datatypes.Vector3, len(vertices))
	copy(mesh.vertices[:], vertices[:])
	delete(vertices)

	for &face in &mesh.faces {
		for &vertex_id in &face.vertices {
			if vertex_id >= 0 && int(vertex_id) < len(remap) {
				vertex_id = remap[vertex_id]
			}
		}
	}

	new_bones := make([dynamic][dynamic]i32, len(mesh.vertices))
	new_weights := make([dynamic][dynamic]f32, len(mesh.vertices))
	for index in 0 ..< len(mesh.vertex_bones) {
		target := remap[index]
		if target < 0 || int(target) >= len(new_bones) {continue}
		if len(mesh.vertex_bones[index]) == 0 {continue}
		if len(new_bones[target]) == 0 {
			new_bones[target] = make([dynamic]i32, len(mesh.vertex_bones[index]))
			copy(new_bones[target][:], mesh.vertex_bones[index][:])
			new_weights[target] = make([dynamic]f32, len(mesh.vertex_weights[index]))
			copy(new_weights[target][:], mesh.vertex_weights[index][:])
		}
	}
	for &entry in &mesh.vertex_bones {delete(entry)}
	for &entry in &mesh.vertex_weights {delete(entry)}
	delete(mesh.vertex_bones)
	delete(mesh.vertex_weights)
	mesh.vertex_bones = new_bones
	mesh.vertex_weights = new_weights

	if touch_topology {
		EditableMesh_Touch_Topology(mesh)
	} else {
		EditableMesh_Touch(mesh)
	}

	return remap
}

EDITABLE_MESH_WELD_CELL :: f32(0.5)

EditableMesh_Merge_Vertices :: proc(mesh: ^EditableMesh, tolerance: f32) -> [dynamic]i32 {
	if mesh == nil {return nil}
	return editable_mesh_weld(mesh, tolerance, true)
}

EditableMesh_Prune_Unused :: proc(
	mesh: ^EditableMesh,
) -> (
	vertex_remap: [dynamic]i32,
	normal_remap: [dynamic]i32,
	color_remap: [dynamic]i32,
	uv_remap: [dynamic]i32,
) {
	vertex_remap = make([dynamic]i32, len(mesh.vertices))
	for index in 0 ..< len(mesh.vertices) {
		vertex_remap[index] = i32(index)
	}
	normal_remap = make([dynamic]i32, len(mesh.normals))
	color_remap = make([dynamic]i32, len(mesh.colors))
	uv_remap = make([dynamic]i32, len(mesh.uvs))
	for index in 0 ..< len(mesh.normals) {
		normal_remap[index] = i32(index)
	}
	for index in 0 ..< len(mesh.colors) {
		color_remap[index] = i32(index)
	}
	for index in 0 ..< len(mesh.uvs) {
		uv_remap[index] = i32(index)
	}

	used_normals: map[i32]bool
	used_colors: map[i32]bool
	used_uvs: map[i32]bool
	used_vertices: map[i32]bool
	used_normals = make(map[i32]bool)
	used_colors = make(map[i32]bool)
	used_uvs = make(map[i32]bool)
	used_vertices = make(map[i32]bool)

	for &face in mesh.faces {
		for id in face.vertices {
			used_vertices[id] = true
		}
		for id in face.normals {
			if id != EDITABLE_MESH_NONE {used_normals[id] = true}
		}
		for id in face.colors {
			if id != EDITABLE_MESH_NONE {used_colors[id] = true}
		}
		for id in face.uvs {
			if id != EDITABLE_MESH_NONE {used_uvs[id] = true}
		}
	}

	vertices := make([dynamic]datatypes.Vector3, 0, len(mesh.vertices))
	next_vertex := i32(0)
	for index in 0 ..< len(mesh.vertices) {
		if used_vertices[i32(index)] {
			vertex_remap[index] = next_vertex
			append(&vertices, mesh.vertices[index])
			next_vertex += 1
		} else {
			vertex_remap[index] = -1
		}
	}

	normals := make([dynamic]datatypes.Vector3, 0, len(mesh.normals))
	next_normal := i32(0)
	for index in 0 ..< len(mesh.normals) {
		if used_normals[i32(index)] {
			normal_remap[index] = next_normal
			append(&normals, mesh.normals[index])
			next_normal += 1
		} else {
			normal_remap[index] = -1
		}
	}

	colors := make([dynamic]EditableMesh_Color, 0, len(mesh.colors))
	next_color := i32(0)
	for index in 0 ..< len(mesh.colors) {
		if used_colors[i32(index)] {
			color_remap[index] = next_color
			append(&colors, mesh.colors[index])
			next_color += 1
		} else {
			color_remap[index] = -1
		}
	}

	uvs := make([dynamic]datatypes.Vector2, 0, len(mesh.uvs))
	next_uv := i32(0)
	for index in 0 ..< len(mesh.uvs) {
		if used_uvs[i32(index)] {
			uv_remap[index] = next_uv
			append(&uvs, mesh.uvs[index])
			next_uv += 1
		} else {
			uv_remap[index] = -1
		}
	}

	for &face in &mesh.faces {
		for &vertex_id in &face.vertices {
			if vertex_id >= 0 && int(vertex_id) < len(vertex_remap) {
				vertex_id = max(vertex_remap[vertex_id], 0)
			}
		}
		for &normal_id in &face.normals {
			if normal_id >= 0 && int(normal_id) < len(normal_remap) {
				normal_id = max(normal_remap[normal_id], 0)
			} else {
				normal_id = EDITABLE_MESH_NONE
			}
		}
		for &color_id in &face.colors {
			if color_id >= 0 && int(color_id) < len(color_remap) {
				color_id = max(color_remap[color_id], 0)
			} else {
				color_id = EDITABLE_MESH_NONE
			}
		}
		for &uv_id in &face.uvs {
			if uv_id >= 0 && int(uv_id) < len(uv_remap) {
				uv_id = max(uv_remap[uv_id], 0)
			} else {
				uv_id = EDITABLE_MESH_NONE
			}
		}
	}

	bones := make([dynamic][dynamic]i32, len(vertices))
	weights := make([dynamic][dynamic]f32, len(vertices))
	for index in 0 ..< len(vertices) {
		old := -1
		for candidate in 0 ..< len(mesh.vertex_bones) {
			if vertex_remap[candidate] == i32(index) {
				old = candidate
				break
			}
		}
		if old >= 0 {
			bones[index] = make([dynamic]i32, len(mesh.vertex_bones[old]))
			copy(bones[index][:], mesh.vertex_bones[old][:])
			weights[index] = make([dynamic]f32, len(mesh.vertex_weights[old]))
			copy(weights[index][:], mesh.vertex_weights[old][:])
		}
	}

	delete(mesh.vertices)
	delete(mesh.normals)
	delete(mesh.colors)
	delete(mesh.uvs)
	for &entry in &mesh.vertex_bones {delete(entry)}
	for &entry in &mesh.vertex_weights {delete(entry)}
	delete(mesh.vertex_bones)
	delete(mesh.vertex_weights)

	mesh.vertices = vertices
	mesh.normals = normals
	mesh.colors = colors
	mesh.uvs = uvs
	mesh.vertex_bones = bones
	mesh.vertex_weights = weights

	delete(used_vertices)
	delete(used_normals)
	delete(used_colors)
	delete(used_uvs)

	EditableMesh_Touch_Topology(mesh)

	return
}

// ---------------------------------------------------------------------------
// Bones
// ---------------------------------------------------------------------------

EditableMesh_Add_Bone :: proc(
	mesh: ^EditableMesh,
	name: string,
	parent: i32,
	cframe: datatypes.CFrame,
	is_virtual: bool,
) -> i32 {
	if mesh == nil || mesh.fixed_size || len(mesh.bones) >= EDITABLE_MESH_MAX_BONES {
		return EDITABLE_MESH_NONE
	}

	if parent != EDITABLE_MESH_NONE && !editable_mesh_valid_bone(mesh, parent) {
		return EDITABLE_MESH_NONE
	}

	bone := EditableMesh_Bone {
		name         = strings.clone(name),
		parent       = parent,
		cframe       = cframe,
		is_virtual   = is_virtual,
		bind         = cframe,
		inverse_bind = datatypes.CFrame_Inverse(cframe),
	}
	append(&mesh.bones, bone)
	EditableMesh_Touch(mesh)
	return i32(len(mesh.bones) - 1)
}

EditableMesh_Remove_Bone :: proc(mesh: ^EditableMesh, bone_id: i32) -> bool {
	if !editable_mesh_valid_bone(mesh, bone_id) {return false}

	parent := mesh.bones[bone_id].parent
	for &bone in &mesh.bones {
		if bone.parent == bone_id {
			bone.parent = parent
		}
	}

	delete(mesh.bones[bone_id].name)
	ordered_remove(&mesh.bones, bone_id)

	for index in 0 ..< len(mesh.bones) {
		bone := &mesh.bones[index]
		if bone.parent > bone_id {
			bone.parent -= 1
		}
	}

	for &entry in &mesh.vertex_bones {
		for &id in &entry {
			if id == bone_id {
				id = EDITABLE_MESH_NONE
			} else if id > bone_id {
				id -= 1
			}
		}
	}

	for &pose in &mesh.facs_poses {
		for &id in &pose.bone_ids {
			if id == bone_id {
				id = EDITABLE_MESH_NONE
			} else if id > bone_id {
				id -= 1
			}
		}
	}

	EditableMesh_Touch_Topology(mesh)
	return true
}

EditableMesh_Get_Bone_By_Name :: proc(mesh: ^EditableMesh, name: string) -> i32 {
	for &bone, index in &mesh.bones {
		if bone.name == name {return i32(index)}
	}
	return EDITABLE_MESH_NONE
}

EditableMesh_Bone_Is_Ancestor_Of :: proc(
	mesh: ^EditableMesh,
	ancestor: i32,
	bone_id: i32,
) -> bool {
	current := bone_id
	for current != EDITABLE_MESH_NONE && editable_mesh_valid_bone(mesh, current) {
		if current == ancestor {return true}
		current = mesh.bones[current].parent
	}
	return false
}

EditableMesh_Set_Bone_Name :: proc(mesh: ^EditableMesh, bone_id: i32, name: string) -> bool {
	if !editable_mesh_valid_bone(mesh, bone_id) {return false}
	delete(mesh.bones[bone_id].name)
	mesh.bones[bone_id].name = strings.clone(name)
	EditableMesh_Touch(mesh)
	return true
}

EditableMesh_Set_Bone_Cframe :: proc(
	mesh: ^EditableMesh,
	bone_id: i32,
	cframe: datatypes.CFrame,
) -> bool {
	if !editable_mesh_valid_bone(mesh, bone_id) {return false}
	mesh.bones[bone_id].cframe = cframe
	mesh.bones[bone_id].inverse_bind = datatypes.CFrame_Inverse(mesh.bones[bone_id].bind)
	EditableMesh_Touch(mesh)
	return true
}

EditableMesh_Set_Bone_Parent :: proc(mesh: ^EditableMesh, bone_id: i32, parent: i32) -> bool {
	if !editable_mesh_valid_bone(mesh, bone_id) {return false}
	if parent != EDITABLE_MESH_NONE && !editable_mesh_valid_bone(mesh, parent) {return false}
	if parent == bone_id {return false}
	if parent != EDITABLE_MESH_NONE && EditableMesh_Bone_Is_Ancestor_Of(mesh, bone_id, parent) {
		return false
	}
	mesh.bones[bone_id].parent = parent
	EditableMesh_Touch(mesh)
	return true
}

EditableMesh_Set_Vertex_Bones :: proc(
	mesh: ^EditableMesh,
	vertex_id: i32,
	bone_ids: []i32,
) -> bool {
	if !editable_mesh_valid_vertex(mesh, vertex_id) {return false}
	if len(bone_ids) > EDITABLE_MESH_MAX_BONE_INFLUENCE {return false}
	for id in bone_ids {
		if !editable_mesh_valid_bone(mesh, id) {return false}
	}

	EditableMesh_Ensure_Vertex_Index(mesh)

	entries := make([dynamic]i32, len(bone_ids))
	copy(entries[:], bone_ids)

	weights := make([dynamic]f32, len(bone_ids))
	share := 1.0 / f32(max(len(bone_ids), 1))
	for index in 0 ..< len(weights) {
		weights[index] = share
	}

	delete(mesh.vertex_bones[vertex_id])
	delete(mesh.vertex_weights[vertex_id])
	mesh.vertex_bones[vertex_id] = entries
	mesh.vertex_weights[vertex_id] = weights

	EditableMesh_Touch(mesh)
	return true
}

EditableMesh_Set_Vertex_Bone_Weights :: proc(
	mesh: ^EditableMesh,
	vertex_id: i32,
	weights: []f32,
) -> bool {
	if !editable_mesh_valid_vertex(mesh, vertex_id) {return false}
	if len(weights) > EDITABLE_MESH_MAX_BONE_INFLUENCE {return false}
	if len(weights) != len(mesh.vertex_bones[vertex_id]) {return false}

	total := f32(0)
	for value in weights {
		if value < 0 || !editable_mesh_finite(value) {return false}
		total += value
	}
	if total <= 1.0e-6 {return false}

	normalized := make([dynamic]f32, len(weights))
	for value, index in weights {
		normalized[index] = value / total
	}

	delete(mesh.vertex_weights[vertex_id])
	mesh.vertex_weights[vertex_id] = normalized

	EditableMesh_Touch(mesh)
	return true
}

// ---------------------------------------------------------------------------
// Facial action poses
// ---------------------------------------------------------------------------

EditableMesh_Find_Facs_Pose :: proc(
	mesh: ^EditableMesh,
	action: enums.FacsActionUnit,
	corrective: bool,
	create: bool,
) -> int {
	for &pose, index in &mesh.facs_poses {
		if pose.action == action && pose.corrective == corrective {return int(index)}
	}
	if !create {return -1}

	pose := EditableMesh_Facs_Pose {
		action     = action,
		corrective = corrective,
	}
	append(&mesh.facs_poses, pose)
	return len(mesh.facs_poses) - 1
}

EditableMesh_Set_Facs_Pose :: proc(
	mesh: ^EditableMesh,
	action: enums.FacsActionUnit,
	corrective: bool,
	bone_ids: []i32,
	cframes: []datatypes.CFrame,
) -> bool {
	if mesh == nil || len(bone_ids) != len(cframes) {return false}
	for id in bone_ids {
		if !editable_mesh_valid_bone(mesh, id) {return false}
	}

	index := EditableMesh_Find_Facs_Pose(mesh, action, corrective, true)
	pose := &mesh.facs_poses[index]

	delete(pose.bone_ids)
	delete(pose.cframes)
	pose.bone_ids = make([dynamic]i32, len(bone_ids))
	copy(pose.bone_ids[:], bone_ids)
	pose.cframes = make([dynamic]datatypes.CFrame, len(cframes))
	copy(pose.cframes[:], cframes)

	EditableMesh_Touch(mesh)
	return true
}

EditableMesh_Prune_Empty_Facs_Poses :: proc(mesh: ^EditableMesh) {
	index := len(mesh.facs_poses) - 1
	for index >= 0 {
		pose := &mesh.facs_poses[index]
		if len(pose.bone_ids) == 0 {
			delete(pose.bone_ids)
			delete(pose.cframes)
			ordered_remove(&mesh.facs_poses, index)
		}
		index -= 1
	}
}

// ---------------------------------------------------------------------------
// Referencing queries
// ---------------------------------------------------------------------------

EditableMesh_Get_Vertices_With_Attribute :: proc(mesh: ^EditableMesh, id: i32) -> [dynamic]i32 {
	result: [dynamic]i32
	if mesh == nil {return result}

	editable_mesh_collect_ids_using(&result, mesh, .Normal, id)
	editable_mesh_collect_ids_using(&result, mesh, .Color, id)
	editable_mesh_collect_ids_using(&result, mesh, .UV, id)
	return result
}

EditableMesh_Get_Faces_With_Attribute :: proc(mesh: ^EditableMesh, id: i32) -> [dynamic]i32 {
	result: [dynamic]i32
	if mesh == nil {return result}

	editable_mesh_collect_faces_using(&result, mesh, .Normal, id)
	editable_mesh_collect_faces_using(&result, mesh, .Color, id)
	editable_mesh_collect_faces_using(&result, mesh, .UV, id)
	return result
}

EditableMesh_Get_Vertices_With_Normal :: proc(
	mesh: ^EditableMesh,
	normal_id: i32,
) -> [dynamic]i32 {
	result: [dynamic]i32
	editable_mesh_collect_ids_using(&result, mesh, .Normal, normal_id)
	return result
}

EditableMesh_Get_Vertices_With_Color :: proc(mesh: ^EditableMesh, color_id: i32) -> [dynamic]i32 {
	result: [dynamic]i32
	editable_mesh_collect_ids_using(&result, mesh, .Color, color_id)
	return result
}

EditableMesh_Get_Vertices_With_UV :: proc(mesh: ^EditableMesh, uv_id: i32) -> [dynamic]i32 {
	result: [dynamic]i32
	editable_mesh_collect_ids_using(&result, mesh, .UV, uv_id)
	return result
}

EditableMesh_Get_Faces_With_Normal :: proc(mesh: ^EditableMesh, normal_id: i32) -> [dynamic]i32 {
	result: [dynamic]i32
	editable_mesh_collect_faces_using(&result, mesh, .Normal, normal_id)
	return result
}

EditableMesh_Get_Faces_With_Color :: proc(mesh: ^EditableMesh, color_id: i32) -> [dynamic]i32 {
	result: [dynamic]i32
	editable_mesh_collect_faces_using(&result, mesh, .Color, color_id)
	return result
}

EditableMesh_Get_Faces_With_UV :: proc(mesh: ^EditableMesh, uv_id: i32) -> [dynamic]i32 {
	result: [dynamic]i32
	editable_mesh_collect_faces_using(&result, mesh, .UV, uv_id)
	return result
}

editable_mesh_face_attribute_ids :: proc(
	face: ^EditableMesh_Face,
	attr: enums.MeshAttribute,
) -> []i32 {
	#partial switch attr {
	case .Normal:
		return face.normals[:]
	case .Color:
		return face.colors[:]
	case .UV:
		return face.uvs[:]
	case:
		return nil
	}
}

editable_mesh_collect_ids_using :: proc(
	result: ^[dynamic]i32,
	mesh: ^EditableMesh,
	attr: enums.MeshAttribute,
	id: i32,
) {
	for &face, face_id in &mesh.faces {
		if !editable_mesh_face_uses_attribute(mesh, &face, i32(face_id), attr, id) {continue}
		for vertex_id in face.vertices {
			editable_mesh_push_unique(result, vertex_id)
		}
	}
}

editable_mesh_collect_faces_using :: proc(
	result: ^[dynamic]i32,
	mesh: ^EditableMesh,
	attr: enums.MeshAttribute,
	id: i32,
) {
	for &face, face_id in &mesh.faces {
		if editable_mesh_face_uses_attribute(mesh, &face, i32(face_id), attr, id) {
			append(result, i32(face_id))
		}
	}
}

editable_mesh_face_uses_attribute :: proc(
	mesh: ^EditableMesh,
	face: ^EditableMesh_Face,
	face_id: i32,
	attr: enums.MeshAttribute,
	id: i32,
) -> bool {
	for value in editable_mesh_face_attribute_ids(face, attr) {
		if value == id {return true}
	}
	_ = face_id
	return false
}

EditableMesh_Id_Debug_String :: proc(mesh: ^EditableMesh, id: i32) -> string {
	if mesh == nil {return "Unknown"}
	if editable_mesh_valid_vertex(mesh, id) {return strings.concatenate({"Vertex ", fmt_i32(id)})}
	if editable_mesh_valid_normal(mesh, id) {return strings.concatenate({"Normal ", fmt_i32(id)})}
	if editable_mesh_valid_color(mesh, id) {return strings.concatenate({"Color ", fmt_i32(id)})}
	if editable_mesh_valid_uv(mesh, id) {return strings.concatenate({"UV ", fmt_i32(id)})}
	if editable_mesh_valid_bone(mesh, id) {return strings.concatenate({"Bone ", fmt_i32(id)})}
	if editable_mesh_valid_face(mesh, id) {
		return strings.concatenate(
			{"Face ", fmt_i32(id), " (", fmt_i32(i32(len(mesh.faces[id].vertices))), " vertices)"},
		)
	}
	return strings.concatenate({"Unknown ", fmt_i32(id)})
}

fmt_i32 :: proc(value: i32) -> string {
	return fmt.tprintf("%d", value)
}

EditableMesh_Corner_Data :: struct {
	position: datatypes.Vector3,
	normal:   datatypes.Vector3,
	color:    datatypes.Color3,
	alpha:    f32,
	uv:       datatypes.Vector2,
}

EditableMesh_Collect_Corners :: proc(
	mesh: ^EditableMesh,
	out: ^[dynamic]EditableMesh_Corner_Data,
) -> bool {
	if mesh == nil {
		return false
	}

	for &face, face_index in &mesh.faces {
		if len(face.vertices) < 3 {
			continue
		}

		flat_normal := datatypes.Vec3_Unit(EditableMesh_Face_Normal(mesh, i32(face_index)))

		for corner in 0 ..< len(face.vertices) {
			vertex_id := face.vertices[corner]
			if !editable_mesh_valid_vertex(mesh, vertex_id) {
				continue
			}

			item := EditableMesh_Corner_Data {
				position = mesh.vertices[vertex_id],
				normal   = flat_normal,
				color    = datatypes.Color3{1, 1, 1},
				alpha    = 1,
			}

			if corner < len(face.normals) {
				normal_id := face.normals[corner]
				if editable_mesh_valid_normal(mesh, normal_id) {
					item.normal = mesh.normals[normal_id]
				}
			}

			if corner < len(face.colors) {
				color_id := face.colors[corner]
				if editable_mesh_valid_color(mesh, color_id) {
					item.color = mesh.colors[color_id].color
					item.alpha = mesh.colors[color_id].alpha
				}
			}

			if corner < len(face.uvs) {
				uv_id := face.uvs[corner]
				if editable_mesh_valid_uv(mesh, uv_id) {
					item.uv = mesh.uvs[uv_id]
				}
			}

			append(out, item)
		}
	}

	return true
}

EditableMesh_Collect_Triangles :: proc(
	mesh: ^EditableMesh,
	out: ^[dynamic]EditableMesh_Corner_Data,
) -> bool {
	if mesh == nil {
		return false
	}

	for &face, face_index in &mesh.faces {
		if len(face.vertices) < 3 {
			continue
		}

		flat_normal := datatypes.Vec3_Unit(EditableMesh_Face_Normal(mesh, i32(face_index)))

		for corner in 1 ..< len(face.vertices) - 1 {
			corner_ids := [3]i32{0, i32(corner), i32(corner + 1)}
			for c in 0 ..< 3 {
				vertex_id := face.vertices[corner_ids[c]]
				if !editable_mesh_valid_vertex(mesh, vertex_id) {
					continue
				}
				position := mesh.vertices[vertex_id]
				normal := flat_normal
				color := datatypes.Color3{1, 1, 1}
				alpha := f32(1)
				uv := datatypes.Vector2{}

				if int(corner_ids[c]) < len(face.normals) {
					normal_id := face.normals[corner_ids[c]]
					if editable_mesh_valid_normal(mesh, normal_id) {
						normal = mesh.normals[normal_id]
					}
				}

				if int(corner_ids[c]) < len(face.colors) {
					color_id := face.colors[corner_ids[c]]
					if editable_mesh_valid_color(mesh, color_id) {
						color = mesh.colors[color_id].color
						alpha = mesh.colors[color_id].alpha
					}
				}

				if int(corner_ids[c]) < len(face.uvs) {
					uv_id := face.uvs[corner_ids[c]]
					if editable_mesh_valid_uv(mesh, uv_id) {
						uv = mesh.uvs[uv_id]
					}
				}

				append(
					out,
					EditableMesh_Corner_Data {
						position = position,
						normal = normal,
						color = color,
						alpha = alpha,
						uv = uv,
					},
				)
			}
		}
	}

	return true
}
