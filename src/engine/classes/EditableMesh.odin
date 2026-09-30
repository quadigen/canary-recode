package classes

import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:strings"

EditableMesh_Class := Class_Info {
	name   = "EditableMesh",
	parent = &Object_Class,
}

editable_mesh_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	mesh := new(EditableMesh)
	mesh^ = EditableMesh_Init()
	mesh.handle = EditableMesh_Acquire_Handle(mesh)
	return &mesh.object
}

editable_mesh_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	mesh := cast(^EditableMesh)object
	EditableMesh_Release_Handle(mesh)
	EditableMesh_Free(mesh)
	Object_Destroy(object)
	free(mesh)
}

editable_mesh_clone :: proc(source: ^Object, destination: ^Object) {
	src := cast(^EditableMesh)source
	dst := cast(^EditableMesh)destination

	dst.fixed_size = src.fixed_size
	dst.version = src.version

	dst.vertices = make([dynamic]datatypes.Vector3, len(src.vertices))
	copy(dst.vertices[:], src.vertices[:])

	dst.normals = make([dynamic]datatypes.Vector3, len(src.normals))
	copy(dst.normals[:], src.normals[:])

	dst.colors = make([dynamic]EditableMesh_Color, len(src.colors))
	copy(dst.colors[:], src.colors[:])

	dst.uvs = make([dynamic]datatypes.Vector2, len(src.uvs))
	copy(dst.uvs[:], src.uvs[:])

	for &face in src.faces {
		new_face := EditableMesh_Face {
			vertices = editable_mesh_copy_ids(face.vertices[:]),
			normals  = editable_mesh_copy_ids(face.normals[:]),
			colors   = editable_mesh_copy_ids(face.colors[:]),
			uvs      = editable_mesh_copy_ids(face.uvs[:]),
		}
		append(&dst.faces, new_face)
	}

	dst.vertex_bones = make([dynamic][dynamic]i32, len(src.vertex_bones))
	for &entry, index in src.vertex_bones {
		dst.vertex_bones[index] = editable_mesh_copy_ids(entry[:])
	}

	dst.vertex_weights = make([dynamic][dynamic]f32, len(src.vertex_weights))
	for &entry, index in src.vertex_weights {
		dst.vertex_weights[index] = make([dynamic]f32, len(entry))
		copy(dst.vertex_weights[index][:], entry[:])
	}

	for &bone in src.bones {
		b := bone
		b.name = strings.clone(bone.name)
		append(&dst.bones, b)
	}

	for &pose in src.facs_poses {
		new_pose := EditableMesh_Facs_Pose {
			action     = pose.action,
			corrective = pose.corrective,
			bone_ids   = editable_mesh_copy_ids(pose.bone_ids[:]),
		}
		new_pose.cframes = make([dynamic]datatypes.CFrame, len(pose.cframes))
		copy(new_pose.cframes[:], pose.cframes[:])
		append(&dst.facs_poses, new_pose)
	}

	EditableMesh_Ensure_Vertex_Index(dst)
}

editable_mesh_get :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	mesh := cast(^EditableMesh)object

	switch key {
	case "FixedSize":
		vm.PushBoolean(L, mesh.fixed_size)
	case:
		return false
	}

	return true
}

editable_mesh_set :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	mesh := cast(^EditableMesh)object

	switch key {
	case "FixedSize":
		mesh.fixed_size = vm.ArgBoolean(L, value_index)
	case:
		return false
	}

	return true
}

editable_mesh_arg_id :: proc(L: ^vm.State, index: int) -> i32 {
	return i32(vm.ArgNumber(L, index))
}

editable_mesh_id_array :: proc(L: ^vm.State, index: int) -> [dynamic]i32 {
	result: [dynamic]i32
	if !vm.IsTable(L, index) {
		return result
	}
	count := vm.RawLen(L, index)
	for i in 0 ..< count {
		_ = vm.RawGetIndex(L, index, i + 1)
		value, _ := vm.ToNumber(L, -1)
		append(&result, i32(value))
		vm.Pop(L)
	}
	return result
}

editable_mesh_f32_array :: proc(L: ^vm.State, index: int) -> [dynamic]f32 {
	result: [dynamic]f32
	if !vm.IsTable(L, index) {
		return result
	}
	count := vm.RawLen(L, index)
	for i in 0 ..< count {
		_ = vm.RawGetIndex(L, index, i + 1)
		value, _ := vm.ToNumber(L, -1)
		append(&result, f32(value))
		vm.Pop(L)
	}
	return result
}

editable_mesh_vector3_array :: proc(L: ^vm.State, index: int) -> [dynamic]datatypes.Vector3 {
	result: [dynamic]datatypes.Vector3
	if !vm.IsTable(L, index) {
		return result
	}
	count := vm.RawLen(L, index)
	for i in 0 ..< count {
		_ = vm.RawGetIndex(L, index, i + 1)
		append(&result, datatypes.Arg_Vector3(L, -1))
		vm.Pop(L)
	}
	return result
}

editable_mesh_vector2_array :: proc(
	L: ^vm.State,
	index: int,
	datatype_registry: ^datatypes.Registry,
) -> [dynamic]datatypes.Vector2 {
	result: [dynamic]datatypes.Vector2
	if !vm.IsTable(L, index) {
		return result
	}
	count := vm.RawLen(L, index)
	for i in 0 ..< count {
		_ = vm.RawGetIndex(L, index, i + 1)
		append(&result, datatypes.Arg_Vector2(L, -1, datatype_registry))
		vm.Pop(L)
	}
	return result
}

editable_mesh_color_array :: proc(
	L: ^vm.State,
	index: int,
	datatype_registry: ^datatypes.Registry,
) -> [dynamic]datatypes.Color3 {
	result: [dynamic]datatypes.Color3
	if !vm.IsTable(L, index) {
		return result
	}
	count := vm.RawLen(L, index)
	for i in 0 ..< count {
		_ = vm.RawGetIndex(L, index, i + 1)
		append(&result, datatypes.Arg_Color3(L, -1, datatype_registry))
		vm.Pop(L)
	}
	return result
}

editable_mesh_push_ids :: proc(L: ^vm.State, ids: []i32) {
	vm.NewTable(L, len(ids))
	for id, i in ids {
		vm.PushNumber(L, f64(id))
		index := i + 1
		vm.SetArrayValue(L, -2, index)
	}
}

editable_mesh_push_numbers :: proc(L: ^vm.State, values: []f32) {
	vm.NewTable(L, len(values))
	for value, i in values {
		vm.PushNumber(L, f64(value))
		index := i + 1
		vm.SetArrayValue(L, -2, index)
	}
}

editable_mesh_push_vector3_values :: proc(L: ^vm.State, values: []datatypes.Vector3) {
	vm.NewTable(L, len(values))
	for value, i in values {
		datatypes.Push_Vector3(L, value)
		index := i + 1
		vm.SetArrayValue(L, -2, index)
	}
}

editable_mesh_push_vector2_values :: proc(
	L: ^vm.State,
	datatype_registry: ^datatypes.Registry,
	values: []datatypes.Vector2,
) {
	vm.NewTable(L, len(values))
	for value, i in values {
		datatypes.Push_Vector2(L, datatype_registry, value)
		index := i + 1
		vm.SetArrayValue(L, -2, index)
	}
}

editable_mesh_push_color3_values :: proc(
	L: ^vm.State,
	datatype_registry: ^datatypes.Registry,
	values: []datatypes.Color3,
) {
	vm.NewTable(L, len(values))
	for value, i in values {
		datatypes.Push_Color3(L, datatype_registry, value)
		index := i + 1
		vm.SetArrayValue(L, -2, index)
	}
}

editable_mesh_vertex_valid_attribute_at_corner :: proc(
	mesh: ^EditableMesh,
	vertex_id: i32,
	attr: enums.MeshAttribute,
) -> bool {
	if mesh == nil || !editable_mesh_valid_vertex(mesh, vertex_id) {
		return false
	}
	EditableMesh_Ensure_Vertex_Index(mesh)
	#partial switch attr {
	case .Normal:
		return len(mesh.vertex_normals) > int(vertex_id) && len(mesh.vertex_normals[vertex_id]) > 0
	case .Color:
		return len(mesh.vertex_colors) > int(vertex_id) && len(mesh.vertex_colors[vertex_id]) > 0
	case .UV:
		return len(mesh.vertex_uvs) > int(vertex_id) && len(mesh.vertex_uvs[vertex_id]) > 0
	}
	return false
}

editable_mesh_set_vertex_attribute_value :: proc(
	mesh: ^EditableMesh,
	vertex_id: i32,
	attr: enums.MeshAttribute,
	value: rawptr,
) -> bool {
	if mesh == nil || !editable_mesh_valid_vertex(mesh, vertex_id) {
		return false
	}
	EditableMesh_Ensure_Vertex_Index(mesh)

	attr_id: i32 = -1
	#partial switch attr {
	case .Vertex:
		position := (cast(^datatypes.Vector3)value)^
		_ = EditableMesh_Set_Position(mesh, vertex_id, position)
	case .Normal:
		normal := (cast(^datatypes.Vector3)value)^
		attr_id = EditableMesh_Add_Normal(mesh, normal)
		if len(mesh.vertex_faces) > int(vertex_id) && len(mesh.vertex_faces[vertex_id]) > 0 {
			face_id := mesh.vertex_faces[vertex_id][0]
			_ = EditableMesh_Set_Vertex_Face_Attribute(mesh, vertex_id, face_id, attr_id, .Normal)
		}
	case .Color:
		color := (cast(^datatypes.Color3)value)^
		attr_id = EditableMesh_Add_Color(mesh, color, 1)
		if len(mesh.vertex_faces) > int(vertex_id) && len(mesh.vertex_faces[vertex_id]) > 0 {
			face_id := mesh.vertex_faces[vertex_id][0]
			_ = EditableMesh_Set_Vertex_Face_Attribute(mesh, vertex_id, face_id, attr_id, .Color)
		}
	case .UV:
		uv := (cast(^datatypes.Vector2)value)^
		attr_id = EditableMesh_Add_UV(mesh, uv)
		if len(mesh.vertex_faces) > int(vertex_id) && len(mesh.vertex_faces[vertex_id]) > 0 {
			face_id := mesh.vertex_faces[vertex_id][0]
			_ = EditableMesh_Set_Vertex_Face_Attribute(mesh, vertex_id, face_id, attr_id, .UV)
		}
	}

	return attr_id >= 0
}

editable_mesh_namecall :: proc(
	L: ^vm.State,
	object: ^Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	mesh := cast(^EditableMesh)object

	switch method {
	case "AddBone":
		name := vm.ArgString(L, 2)
		parent_id := i32(-1)
		if !vm.IsNoneOrNil(L, 3) {
			parent_id = editable_mesh_arg_id(L, 3)
		}
		cframe := datatypes.CFrame_Identity
		if !vm.IsNoneOrNil(L, 4) {
			cframe = datatypes.Arg_CFrame(L, 4, datatype_registry)
		}
		is_virtual := vm.ArgOptionalBoolean(L, 5, false)
		vm.PushNumber(L, f64(EditableMesh_Add_Bone(mesh, name, parent_id, cframe, is_virtual)))
		return 1, true

	case "AddColor":
		color := datatypes.Arg_Color3(L, 2, datatype_registry)
		alpha := f32(vm.ArgOptionalNumber(L, 3, 0))
		vm.PushNumber(L, f64(EditableMesh_Add_Color(mesh, color, alpha)))
		return 1, true

	case "AddFace":
		ids := editable_mesh_id_array(L, 2)
		defer delete(ids)
		vm.PushNumber(L, f64(EditableMesh_Add_Face(mesh, ids[:])))
		return 1, true

	case "AddNormal":
		normal := datatypes.Arg_Vector3(L, 2)
		vm.PushNumber(L, f64(EditableMesh_Add_Normal(mesh, normal)))
		return 1, true

	case "AddTriangle":
		a := i32(editable_mesh_arg_id(L, 2))
		b := i32(editable_mesh_arg_id(L, 3))
		c := i32(editable_mesh_arg_id(L, 4))
		triangle := [3]i32{a, b, c}
		vm.PushNumber(L, f64(EditableMesh_Add_Face(mesh, triangle[:])))
		return 1, true

	case "AddUV":
		uv := datatypes.Arg_Vector2(L, 2, datatype_registry)
		vm.PushNumber(L, f64(EditableMesh_Add_UV(mesh, uv)))
		return 1, true

	case "AddVertex":
		position := datatypes.Arg_Vector3(L, 2)
		vm.PushNumber(L, f64(EditableMesh_Add_Vertex(mesh, position)))
		return 1, true

	case "BatchAdd":
		positions := editable_mesh_vector3_array(L, 3)
		defer delete(positions)
		for position, i in positions {
			if i < len(mesh.vertices) {
				_ = EditableMesh_Set_Position(mesh, i32(i), position)
			} else {
				_ = EditableMesh_Add_Vertex(mesh, position)
			}
		}
		normals := editable_mesh_vector3_array(L, 4)
		for normal in normals {
			_ = EditableMesh_Add_Normal(mesh, normal)
		}
		delete(normals)
		colors := editable_mesh_color_array(L, 5, datatype_registry)
		for color in colors {
			_ = EditableMesh_Add_Color(mesh, color, 1)
		}
		delete(colors)
		uvs := editable_mesh_vector2_array(L, 6, datatype_registry)
		for uv in uvs {
			_ = EditableMesh_Add_UV(mesh, uv)
		}
		delete(uvs)
		if vm.IsTable(L, 2) {
			face_count := vm.RawLen(L, 2)
			for i in 0 ..< face_count {
				_ = vm.RawGetIndex(L, 2, i + 1)
				face_ids := editable_mesh_id_array(L, -1)
				if len(face_ids) > 0 {
					_ = EditableMesh_Add_Face(mesh, face_ids[:])
				}
				delete(face_ids)
				vm.Pop(L)
			}
		}
		return 0, true

	case "BatchGet":
		ids := editable_mesh_id_array(L, 2)
		defer delete(ids)
		vm.NewTable(L, len(ids))
		for vertex_id, i in ids {
			vm.NewTable(L, 0, 5)
			if editable_mesh_valid_vertex(mesh, vertex_id) {
				datatypes.Push_Vector3(L, mesh.vertices[vertex_id])
			} else {
				datatypes.Push_Vector3(L, datatypes.Vector3{})
			}
			vm.SetField(L, -2, "Position")
			normal := datatypes.Vector3{}
			if editable_mesh_vertex_valid_attribute_at_corner(mesh, vertex_id, .Normal) {
				normal_ids := EditableMesh_Get_Vertex_Normals(mesh, vertex_id)
				if len(normal_ids) > 0 {
					normal = mesh.normals[normal_ids[0]]
				}
				delete(normal_ids)
			}
			datatypes.Push_Vector3(L, normal)
			vm.SetField(L, -2, "Normal")
			color := datatypes.Color3{1, 1, 1}
			alpha := f32(1)
			if editable_mesh_vertex_valid_attribute_at_corner(mesh, vertex_id, .Color) {
				color_ids := EditableMesh_Get_Vertex_Colors(mesh, vertex_id)
				if len(color_ids) > 0 {
					color = mesh.colors[color_ids[0]].color
					alpha = mesh.colors[color_ids[0]].alpha
				}
				delete(color_ids)
			}
			datatypes.Push_Color3(L, datatype_registry, color)
			vm.SetField(L, -2, "Color")
			vm.PushNumber(L, f64(alpha))
			vm.SetField(L, -2, "ColorAlpha")
			uv := datatypes.Vector2{}
			if editable_mesh_vertex_valid_attribute_at_corner(mesh, vertex_id, .UV) {
				uv_ids := EditableMesh_Get_Vertex_UVs(mesh, vertex_id)
				if len(uv_ids) > 0 {
					uv = mesh.uvs[uv_ids[0]]
				}
				delete(uv_ids)
			}
			datatypes.Push_Vector2(L, datatype_registry, uv)
			vm.SetField(L, -2, "UV")
			index := i + 1
			vm.SetArrayValue(L, -2, index)
		}
		return 1, true

	case "BatchGetNormals":
		ids := editable_mesh_id_array(L, 2)
		defer delete(ids)
		vm.NewTable(L, len(ids))
		for vertex_id, i in ids {
			value := datatypes.Vector3{}
			if editable_mesh_vertex_valid_attribute_at_corner(mesh, vertex_id, .Normal) {
				normal_ids := EditableMesh_Get_Vertex_Normals(mesh, vertex_id)
				if len(normal_ids) > 0 {
					value = mesh.normals[normal_ids[0]]
				}
				delete(normal_ids)
			}
			datatypes.Push_Vector3(L, value)
			index := i + 1
			vm.SetArrayValue(L, -2, index)
		}
		return 1, true

	case "BatchGetPositions":
		ids := editable_mesh_id_array(L, 2)
		defer delete(ids)
		vm.NewTable(L, len(ids))
		for vertex_id, i in ids {
			value := datatypes.Vector3{}
			if editable_mesh_valid_vertex(mesh, vertex_id) {
				value = mesh.vertices[vertex_id]
			}
			datatypes.Push_Vector3(L, value)
			index := i + 1
			vm.SetArrayValue(L, -2, index)
		}
		return 1, true

	case "BatchGetTriangles":
		return 0, true

	case "BatchSetNormals":
		ids := editable_mesh_id_array(L, 2)
		defer delete(ids)
		normals := editable_mesh_vector3_array(L, 3)
		defer delete(normals)
		for &normal, i in normals {
			if i >= len(ids) {
				break
			}
			_ = editable_mesh_set_vertex_attribute_value(mesh, ids[i], .Normal, &normal)
		}
		EditableMesh_Touch(mesh)
		return 0, true

	case "BatchSetUVs":
		ids := editable_mesh_id_array(L, 2)
		defer delete(ids)
		uvs := editable_mesh_vector2_array(L, 3, datatype_registry)
		defer delete(uvs)
		for &uv, i in uvs {
			if i >= len(ids) {
				break
			}
			_ = editable_mesh_set_vertex_attribute_value(mesh, ids[i], .UV, &uv)
		}
		EditableMesh_Touch(mesh)
		return 0, true

	case "Clear":
		EditableMesh_Clear(mesh)
		return 0, true

	case "FindClosestPointOnSurface":
		point := datatypes.Arg_Vector3(L, 2)
		position, _, _ := EditableMesh_Closest_Point_On_Surface(mesh, point)
		datatypes.Push_Vector3(L, position)
		return 1, true

	case "FindClosestVertex":
		point := datatypes.Arg_Vector3(L, 2)
		vm.PushNumber(L, f64(EditableMesh_Find_Closest_Vertex(mesh, point)))
		return 1, true

	case "FindVerticesWithinSphere":
		center := datatypes.Arg_Vector3(L, 2)
		radius := f32(vm.ArgNumber(L, 3))
		ids := EditableMesh_Find_Vertices_Within_Sphere(mesh, center, radius)
		defer delete(ids)
		editable_mesh_push_ids(L, ids[:])
		return 1, true

	case "GetAdjacentFaces":
		face_id := i32(editable_mesh_arg_id(L, 2))
		ids := EditableMesh_Get_Adjacent_Faces(mesh, face_id)
		defer delete(ids)
		editable_mesh_push_ids(L, ids[:])
		return 1, true

	case "GetAdjacentVertices":
		vertex_id := i32(editable_mesh_arg_id(L, 2))
		ids := EditableMesh_Get_Adjacent_Vertices(mesh, vertex_id)
		defer delete(ids)
		editable_mesh_push_ids(L, ids[:])
		return 1, true

	case "GetBoneByName":
		name := vm.ArgString(L, 2)
		vm.PushNumber(L, f64(EditableMesh_Get_Bone_By_Name(mesh, name)))
		return 1, true

	case "GetBones":
		vm.NewTable(L, len(mesh.bones))
		for _, i in mesh.bones {
			vm.PushNumber(L, f64(i))
			index := i + 1
			vm.SetArrayValue(L, -2, index)
		}
		return 1, true

	case "GetCenter":
		datatypes.Push_Vector3(L, EditableMesh_Get_Center(mesh))
		return 1, true

	case "GetColor", "GetColorWithAttribute":
		color_id := i32(editable_mesh_arg_id(L, 2))
		if editable_mesh_valid_color(mesh, color_id) {
			datatypes.Push_Color3(L, datatype_registry, mesh.colors[color_id].color)
		} else {
			datatypes.Push_Color3(L, datatype_registry, datatypes.Color3{1, 1, 1})
		}
		return 1, true

	case "GetColors":
		vm.NewTable(L, len(mesh.colors))
		for color, i in mesh.colors {
			vm.NewTable(L, 0, 2)
			datatypes.Push_Color3(L, datatype_registry, color.color)
			vm.SetField(L, -2, "Color")
			vm.PushNumber(L, f64(color.alpha))
			vm.SetField(L, -2, "Alpha")
			index := i + 1
			vm.SetArrayValue(L, -2, index)
		}
		return 1, true

	case "GetFaceColor":
		face_id := i32(editable_mesh_arg_id(L, 2))
		datatypes.Push_Color3(L, datatype_registry, EditableMesh_Face_Color(mesh, face_id))
		return 1, true

	case "GetFaceVertexIDs":
		face_id := i32(editable_mesh_arg_id(L, 2))
		if editable_mesh_valid_face(mesh, face_id) {
			ids := editable_mesh_copy_ids(mesh.faces[face_id].vertices[:])
			defer delete(ids)
			editable_mesh_push_ids(L, ids[:])
		} else {
			vm.NewTable(L, 0)
		}
		return 1, true

	case "GetFaceWithNormals":
		face_id := i32(editable_mesh_arg_id(L, 2))
		vm.NewTable(L, 0, 2)
		if editable_mesh_valid_face(mesh, face_id) {
			ids := editable_mesh_copy_ids(mesh.faces[face_id].vertices[:])
			defer delete(ids)
			editable_mesh_push_ids(L, ids[:])
			vm.SetField(L, -2, "FaceVertexIDs")
			normal_ids := editable_mesh_copy_ids(mesh.faces[face_id].normals[:])
			defer delete(normal_ids)
			editable_mesh_push_ids(L, normal_ids[:])
			vm.SetField(L, -2, "FaceNormals")
		}
		return 1, true

	case "GetFaceWithUV":
		face_id := i32(editable_mesh_arg_id(L, 2))
		vm.NewTable(L, 0, 2)
		if editable_mesh_valid_face(mesh, face_id) {
			ids := editable_mesh_copy_ids(mesh.faces[face_id].vertices[:])
			defer delete(ids)
			editable_mesh_push_ids(L, ids[:])
			vm.SetField(L, -2, "FaceVertexIDs")
			uv_ids := editable_mesh_copy_ids(mesh.faces[face_id].uvs[:])
			defer delete(uv_ids)
			editable_mesh_push_ids(L, uv_ids[:])
			vm.SetField(L, -2, "FaceUVs")
		}
		return 1, true

	case "GetFaces":
		vm.NewTable(L, len(mesh.faces))
		for &face, i in mesh.faces {
			ids := editable_mesh_copy_ids(face.vertices[:])
			editable_mesh_push_ids(L, ids[:])
			delete(ids)
			index := i + 1
			vm.SetArrayValue(L, -2, index)
		}
		return 1, true

	case "GetFacesWithAttribute":
		attribute_id := i32(editable_mesh_arg_id(L, 2))
		ids := EditableMesh_Get_Faces_With_Attribute(mesh, attribute_id)
		defer delete(ids)
		editable_mesh_push_ids(L, ids[:])
		return 1, true

	case "GetFacesWithColor":
		color_id := i32(editable_mesh_arg_id(L, 2))
		ids := EditableMesh_Get_Faces_With_Color(mesh, color_id)
		defer delete(ids)
		editable_mesh_push_ids(L, ids[:])
		return 1, true

	case "GetFacesWithNormal":
		normal_id := i32(editable_mesh_arg_id(L, 2))
		ids := EditableMesh_Get_Faces_With_Normal(mesh, normal_id)
		defer delete(ids)
		editable_mesh_push_ids(L, ids[:])
		return 1, true

	case "GetFacesWithUV":
		uv_id := i32(editable_mesh_arg_id(L, 2))
		ids := EditableMesh_Get_Faces_With_UV(mesh, uv_id)
		defer delete(ids)
		editable_mesh_push_ids(L, ids[:])
		return 1, true

	case "GetPosition", "GetVertexPosition":
		vertex_id := i32(editable_mesh_arg_id(L, 2))
		if editable_mesh_valid_vertex(mesh, vertex_id) {
			datatypes.Push_Vector3(L, mesh.vertices[vertex_id])
		} else {
			datatypes.Push_Vector3(L, datatypes.Vector3{})
		}
		return 1, true

	case "GetSize":
		datatypes.Push_Vector3(L, EditableMesh_Get_Size(mesh))
		return 1, true

	case "GetUV":
		uv_id := i32(editable_mesh_arg_id(L, 2))
		if editable_mesh_valid_uv(mesh, uv_id) {
			datatypes.Push_Vector2(L, datatype_registry, mesh.uvs[uv_id])
		} else {
			datatypes.Push_Vector2(L, datatype_registry, datatypes.Vector2{})
		}
		return 1, true

	case "GetUVs":
		editable_mesh_push_vector2_values(L, datatype_registry, mesh.uvs[:])
		return 1, true

	case "GetVertexColor":
		vertex_id := i32(editable_mesh_arg_id(L, 2))
		value := datatypes.Color3{1, 1, 1}
		if editable_mesh_vertex_valid_attribute_at_corner(mesh, vertex_id, .Color) {
			color_ids := EditableMesh_Get_Vertex_Colors(mesh, vertex_id)
			if len(color_ids) > 0 {
				value = mesh.colors[color_ids[0]].color
			}
			delete(color_ids)
		}
		datatypes.Push_Color3(L, datatype_registry, value)
		return 1, true

	case "GetVertexColors":
		vertex_id := i32(editable_mesh_arg_id(L, 2))
		ids := EditableMesh_Get_Vertex_Colors(mesh, vertex_id)
		defer delete(ids)
		values := make([dynamic]datatypes.Color3, len(ids))
		defer delete(values)
		for color_id, i in ids {
			values[i] = mesh.colors[color_id].color
		}
		editable_mesh_push_color3_values(L, datatype_registry, values[:])
		return 1, true

	case "GetVertexFaces":
		vertex_id := i32(editable_mesh_arg_id(L, 2))
		ids := EditableMesh_Get_Vertex_Faces(mesh, vertex_id)
		defer delete(ids)
		editable_mesh_push_ids(L, ids[:])
		return 1, true

	case "GetVertexFaceColor":
		vertex_id := i32(editable_mesh_arg_id(L, 2))
		face_id := i32(editable_mesh_arg_id(L, 3))
		vm.PushNumber(L, f64(EditableMesh_Get_Vertex_Face_Color(mesh, vertex_id, face_id)))
		return 1, true

	case "GetVertexFaceNormal":
		vertex_id := i32(editable_mesh_arg_id(L, 2))
		face_id := i32(editable_mesh_arg_id(L, 3))
		vm.PushNumber(L, f64(EditableMesh_Get_Vertex_Face_Normal(mesh, vertex_id, face_id)))
		return 1, true

	case "GetVertexFaceUV":
		vertex_id := i32(editable_mesh_arg_id(L, 2))
		face_id := i32(editable_mesh_arg_id(L, 3))
		vm.PushNumber(L, f64(EditableMesh_Get_Vertex_Face_UV(mesh, vertex_id, face_id)))
		return 1, true

	case "GetVertexNormals":
		vertex_id := i32(editable_mesh_arg_id(L, 2))
		ids := EditableMesh_Get_Vertex_Normals(mesh, vertex_id)
		defer delete(ids)
		values := make([dynamic]datatypes.Vector3, len(ids))
		defer delete(values)
		for normal_id, i in ids {
			values[i] = mesh.normals[normal_id]
		}
		editable_mesh_push_vector3_values(L, values[:])
		return 1, true

	case "GetVertexUVs":
		vertex_id := i32(editable_mesh_arg_id(L, 2))
		ids := EditableMesh_Get_Vertex_UVs(mesh, vertex_id)
		defer delete(ids)
		values := make([dynamic]datatypes.Vector2, len(ids))
		defer delete(values)
		for uv_id, i in ids {
			values[i] = mesh.uvs[uv_id]
		}
		editable_mesh_push_vector2_values(L, datatype_registry, values[:])
		return 1, true

	case "GetVerticesColors":
		values := make([dynamic]datatypes.Color3, len(mesh.colors))
		defer delete(values)
		for color, i in mesh.colors {
			values[i] = color.color
		}
		editable_mesh_push_color3_values(L, datatype_registry, values[:])
		return 1, true

	case "GetVerticesNormals":
		editable_mesh_push_vector3_values(L, mesh.normals[:])
		return 1, true

	case "GetVerticesUVs":
		editable_mesh_push_vector2_values(L, datatype_registry, mesh.uvs[:])
		return 1, true

	case "GetVerticesWithAttribute":
		attribute_id := i32(editable_mesh_arg_id(L, 2))
		ids := EditableMesh_Get_Vertices_With_Attribute(mesh, attribute_id)
		defer delete(ids)
		editable_mesh_push_ids(L, ids[:])
		return 1, true

	case "GetVerticesWithColor", "GetVertexWithColor":
		color_id := i32(editable_mesh_arg_id(L, 2))
		ids := EditableMesh_Get_Vertices_With_Color(mesh, color_id)
		defer delete(ids)
		editable_mesh_push_ids(L, ids[:])
		return 1, true

	case "GetVerticesWithNormal":
		normal_id := i32(editable_mesh_arg_id(L, 2))
		ids := EditableMesh_Get_Vertices_With_Normal(mesh, normal_id)
		defer delete(ids)
		editable_mesh_push_ids(L, ids[:])
		return 1, true

	case "GetVerticesWithUV", "GetVertexWithUV":
		uv_id := i32(editable_mesh_arg_id(L, 2))
		ids := EditableMesh_Get_Vertices_With_UV(mesh, uv_id)
		defer delete(ids)
		editable_mesh_push_ids(L, ids[:])
		return 1, true

	case "IdDebugString":
		id := i32(editable_mesh_arg_id(L, 2))
		display := EditableMesh_Id_Debug_String(mesh, id)
		defer delete(display)
		vm.PushString(L, display)
		return 1, true

	case "MergeVertices":
		tolerance := f32(vm.ArgNumber(L, 2))
		remap := EditableMesh_Merge_Vertices(mesh, tolerance)
		defer delete(remap)
		editable_mesh_push_ids(L, remap[:])
		return 1, true

	case "RaycastLocal":
		origin := datatypes.Arg_Vector3(L, 2)
		direction := datatypes.Arg_Vector3(L, 3)
		face_id, point, barycentric, vertex_ids := EditableMesh_Raycast_Local(
			mesh,
			origin,
			direction,
		)
		vm.PushNumber(L, f64(face_id))
		datatypes.Push_Vector3(L, point)
		datatypes.Push_Vector3(L, barycentric)
		datatypes.Push_Vector3(L, vertex_ids)
		return 4, true

	case "RemoveBone":
		bone_id := i32(editable_mesh_arg_id(L, 2))
		_ = EditableMesh_Remove_Bone(mesh, bone_id)
		return 0, true

	case "RemoveColor":
		color_id := i32(editable_mesh_arg_id(L, 2))
		delete_color(mesh, color_id)
		return 0, true

	case "RemoveFace":
		face_id := i32(editable_mesh_arg_id(L, 2))
		_ = EditableMesh_Remove_Face(mesh, face_id)
		return 0, true

	case "RemoveNormal":
		normal_id := i32(editable_mesh_arg_id(L, 2))
		delete_normal(mesh, normal_id)
		return 0, true

	case "RemoveUV":
		uv_id := i32(editable_mesh_arg_id(L, 2))
		delete_uv(mesh, uv_id)
		return 0, true

	case "RemoveVertex":
		vertex_id := i32(editable_mesh_arg_id(L, 2))
		delete_vertex(mesh, vertex_id)
		return 0, true

	case "ResetNormal":
		normal_id := i32(editable_mesh_arg_id(L, 2))
		_ = EditableMesh_Reset_Normal(mesh, normal_id)
		return 0, true

	case "SetBoneCframe":
		bone_id := i32(editable_mesh_arg_id(L, 2))
		cframe := datatypes.Arg_CFrame(L, 3, datatype_registry)
		_ = EditableMesh_Set_Bone_Cframe(mesh, bone_id, cframe)
		return 0, true

	case "SetBoneName":
		bone_id := i32(editable_mesh_arg_id(L, 2))
		name := vm.ArgString(L, 3)
		_ = EditableMesh_Set_Bone_Name(mesh, bone_id, name)
		return 0, true

	case "SetBoneParent":
		bone_id := i32(editable_mesh_arg_id(L, 2))
		parent_id := i32(editable_mesh_arg_id(L, 3))
		_ = EditableMesh_Set_Bone_Parent(mesh, bone_id, parent_id)
		return 0, true

	case "SetColorForVertices":
		ids := editable_mesh_id_array(L, 2)
		defer delete(ids)
		color := datatypes.Arg_Color3(L, 3, datatype_registry)
		for vertex_id in ids {
			_ = editable_mesh_set_vertex_attribute_value(mesh, vertex_id, .Color, &color)
		}
		EditableMesh_Touch(mesh)
		return 0, true

	case "SetFaceColors":
		face_id := i32(editable_mesh_arg_id(L, 2))
		ids := editable_mesh_id_array(L, 3)
		defer delete(ids)
		_ = EditableMesh_Set_Face_Colors(mesh, face_id, ids[:])
		return 0, true

	case "SetFaceNormals":
		face_id := i32(editable_mesh_arg_id(L, 2))
		ids := editable_mesh_id_array(L, 3)
		defer delete(ids)
		_ = EditableMesh_Set_Face_Normals(mesh, face_id, ids[:])
		return 0, true

	case "SetFaceUVs":
		face_id := i32(editable_mesh_arg_id(L, 2))
		ids := editable_mesh_id_array(L, 3)
		defer delete(ids)
		_ = EditableMesh_Set_Face_UVs(mesh, face_id, ids[:])
		return 0, true

	case "SetFaceVertices":
		face_id := i32(editable_mesh_arg_id(L, 2))
		ids := editable_mesh_id_array(L, 3)
		defer delete(ids)
		_ = EditableMesh_Set_Face_Vertices(mesh, face_id, ids[:])
		return 0, true

	case "SetNormalForVertices":
		ids := editable_mesh_id_array(L, 2)
		defer delete(ids)
		normal := datatypes.Arg_Vector3(L, 3)
		for vertex_id in ids {
			_ = editable_mesh_set_vertex_attribute_value(mesh, vertex_id, .Normal, &normal)
		}
		EditableMesh_Touch(mesh)
		return 0, true

	case "SetPosition":
		vertex_id := i32(editable_mesh_arg_id(L, 2))
		position := datatypes.Arg_Vector3(L, 3)
		_ = EditableMesh_Set_Position(mesh, vertex_id, position)
		return 0, true

	case "SetUVForVertices":
		ids := editable_mesh_id_array(L, 2)
		defer delete(ids)
		uv := datatypes.Arg_Vector2(L, 3, datatype_registry)
		for vertex_id in ids {
			_ = editable_mesh_set_vertex_attribute_value(mesh, vertex_id, .UV, &uv)
		}
		EditableMesh_Touch(mesh)
		return 0, true

	case "SetVertexBones":
		vertex_id := i32(editable_mesh_arg_id(L, 2))
		bone_ids := editable_mesh_id_array(L, 3)
		defer delete(bone_ids)
		_ = EditableMesh_Set_Vertex_Bones(mesh, vertex_id, bone_ids[:])
		return 0, true

	case "SetVertexBoneWeights":
		vertex_id := i32(editable_mesh_arg_id(L, 2))
		weights := editable_mesh_f32_array(L, 3)
		defer delete(weights)
		_ = EditableMesh_Set_Vertex_Bone_Weights(mesh, vertex_id, weights[:])
		return 0, true

	case "SetVertexColor":
		vertex_id := i32(editable_mesh_arg_id(L, 2))
		color := datatypes.Arg_Color3(L, 3, datatype_registry)
		_ = editable_mesh_set_vertex_attribute_value(mesh, vertex_id, .Color, &color)
		EditableMesh_Touch(mesh)
		return 0, true

	case "SetVertexFaceColor":
		vertex_id := i32(editable_mesh_arg_id(L, 2))
		face_id := i32(editable_mesh_arg_id(L, 3))
		color_id := i32(editable_mesh_arg_id(L, 4))
		_ = EditableMesh_Set_Vertex_Face_Attribute(mesh, vertex_id, face_id, color_id, .Color)
		return 0, true

	case "SetVertexFaceNormal":
		vertex_id := i32(editable_mesh_arg_id(L, 2))
		face_id := i32(editable_mesh_arg_id(L, 3))
		normal_id := i32(editable_mesh_arg_id(L, 4))
		_ = EditableMesh_Set_Vertex_Face_Attribute(mesh, vertex_id, face_id, normal_id, .Normal)
		return 0, true

	case "SetVertexFaceUV":
		vertex_id := i32(editable_mesh_arg_id(L, 2))
		face_id := i32(editable_mesh_arg_id(L, 3))
		uv_id := i32(editable_mesh_arg_id(L, 4))
		_ = EditableMesh_Set_Vertex_Face_Attribute(mesh, vertex_id, face_id, uv_id, .UV)
		return 0, true

	case "SetVertexNormal":
		vertex_id := i32(editable_mesh_arg_id(L, 2))
		normal := datatypes.Arg_Vector3(L, 3)
		_ = editable_mesh_set_vertex_attribute_value(mesh, vertex_id, .Normal, &normal)
		EditableMesh_Touch(mesh)
		return 0, true

	case "SetVertexUV":
		vertex_id := i32(editable_mesh_arg_id(L, 2))
		uv := datatypes.Arg_Vector2(L, 3, datatype_registry)
		_ = editable_mesh_set_vertex_attribute_value(mesh, vertex_id, .UV, &uv)
		EditableMesh_Touch(mesh)
		return 0, true

	case "Triangulate":
		_ = EditableMesh_Triangulate(mesh)
		return 0, true
	}

	return 0, false
}

delete_normal :: proc(mesh: ^EditableMesh, normal_id: i32) {
	if !editable_mesh_valid_normal(mesh, normal_id) {
		return
	}
	for &face in &mesh.faces {
		for &id in &face.normals {
			if id == normal_id {
				id = EDITABLE_MESH_NONE
			} else if id > normal_id {
				id -= 1
			}
		}
	}
	ordered_remove(&mesh.normals, normal_id)
	EditableMesh_Touch_Topology(mesh)
}

delete_color :: proc(mesh: ^EditableMesh, color_id: i32) {
	if !editable_mesh_valid_color(mesh, color_id) {
		return
	}
	for &face in &mesh.faces {
		for &id in &face.colors {
			if id == color_id {
				id = EDITABLE_MESH_NONE
			} else if id > color_id {
				id -= 1
			}
		}
	}
	ordered_remove(&mesh.colors, color_id)
	EditableMesh_Touch_Topology(mesh)
}

delete_uv :: proc(mesh: ^EditableMesh, uv_id: i32) {
	if !editable_mesh_valid_uv(mesh, uv_id) {
		return
	}
	for &face in &mesh.faces {
		for &id in &face.uvs {
			if id == uv_id {
				id = EDITABLE_MESH_NONE
			} else if id > uv_id {
				id -= 1
			}
		}
	}
	ordered_remove(&mesh.uvs, uv_id)
	EditableMesh_Touch_Topology(mesh)
}

delete_vertex :: proc(mesh: ^EditableMesh, vertex_id: i32) {
	if !editable_mesh_valid_vertex(mesh, vertex_id) {
		return
	}
	for &face in &mesh.faces {
		for &id in &face.vertices {
			if id == vertex_id {
				id = EDITABLE_MESH_NONE
			} else if id > vertex_id {
				id -= 1
			}
		}
	}
	for &face in &mesh.faces {
		new_ids: [dynamic]i32
		for id in face.vertices {
			if id != EDITABLE_MESH_NONE {
				append(&new_ids, id)
			}
		}
		delete(face.vertices)
		face.vertices = new_ids
	}
	ordered_remove(&mesh.vertices, vertex_id)
	EditableMesh_Touch_Topology(mesh)
}

editable_mesh_resolve_content :: proc(object: rawptr) -> (u32, u8) {
	instance := cast(^Object)object
	if instance == nil || !Is_A(instance, "EditableMesh") {
		return 0, 0
	}
	mesh := cast(^EditableMesh)instance
	return mesh.handle, 1
}

editable_mesh_content_of_id :: proc(id: u32, kind: u8) -> rawptr {
	if kind != 1 {
		return nil
	}
	mesh := EditableMesh_Of_Handle(id)
	if mesh == nil {
		return nil
	}
	return &mesh.object
}

editable_mesh_push_content_object :: proc(L: ^vm.State, object: rawptr) -> bool {
	instance := cast(^Object)object
	if instance == nil || instance.lua_ref <= 0 {
		return false
	}
	Push_Object(L, instance)
	return true
}

Register_EditableMesh :: proc(registry: ^Registry) {
	datatypes.Set_Content_Object_Resolver(
		editable_mesh_resolve_content,
		editable_mesh_content_of_id,
		editable_mesh_push_content_object,
	)
	Register_Class(
		registry,
		&EditableMesh_Class,
		editable_mesh_construct,
		editable_mesh_destroy,
		clone = editable_mesh_clone,
		get = editable_mesh_get,
		set = editable_mesh_set,
		namecall = editable_mesh_namecall,
		properties = []string{"FixedSize"},
		methods = []string {
			"AddBone",
			"AddColor",
			"AddFace",
			"AddNormal",
			"AddTriangle",
			"AddUV",
			"AddVertex",
			"BatchAdd",
			"BatchGet",
			"BatchGetNormals",
			"BatchGetPositions",
			"BatchGetTriangles",
			"BatchSetNormals",
			"BatchSetUVs",
			"Clear",
			"FindClosestPointOnSurface",
			"FindClosestVertex",
			"FindVerticesWithinSphere",
			"GetAdjacentFaces",
			"GetAdjacentVertices",
			"GetBoneByName",
			"GetBones",
			"GetCenter",
			"GetColor",
			"GetColorWithAttribute",
			"GetColors",
			"GetFaceColor",
			"GetFaceVertexIDs",
			"GetFaceWithNormals",
			"GetFaceWithUV",
			"GetFaces",
			"GetFacesWithAttribute",
			"GetFacesWithColor",
			"GetFacesWithNormal",
			"GetFacesWithUV",
			"GetPosition",
			"GetSize",
			"GetUV",
			"GetUVs",
			"GetVertexColor",
			"GetVertexColors",
			"GetVertexFaces",
			"GetVertexFaceColor",
			"GetVertexFaceNormal",
			"GetVertexFaceUV",
			"GetVertexNormals",
			"GetVertexPosition",
			"GetVertexUVs",
			"GetVertexWithColor",
			"GetVertexWithUV",
			"GetVerticesColors",
			"GetVerticesNormals",
			"GetVerticesUVs",
			"GetVerticesWithAttribute",
			"GetVerticesWithColor",
			"GetVerticesWithNormal",
			"GetVerticesWithUV",
			"IdDebugString",
			"MergeVertices",
			"RaycastLocal",
			"RemoveBone",
			"RemoveColor",
			"RemoveFace",
			"RemoveNormal",
			"RemoveUV",
			"RemoveVertex",
			"ResetNormal",
			"SetBoneCframe",
			"SetBoneName",
			"SetBoneParent",
			"SetColorForVertices",
			"SetFaceColors",
			"SetFaceNormals",
			"SetFaceUVs",
			"SetFaceVertices",
			"SetNormalForVertices",
			"SetPosition",
			"SetUVForVertices",
			"SetVertexBones",
			"SetVertexBoneWeights",
			"SetVertexColor",
			"SetVertexFaceColor",
			"SetVertexFaceNormal",
			"SetVertexFaceUV",
			"SetVertexNormal",
			"SetVertexUV",
			"Triangulate",
		},
	)
}
