package classes

import assetstore "../assetstore"
import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:c"
import "core:strings"
import image "vendor:stb/image"

SpecialMesh_Class := Class_Info {
	name   = "SpecialMesh",
	parent = &Instance_Class,
}

SpecialMesh :: struct {
	using object:                      Object,
	mesh_type:                         enums.MeshType,
	mesh_id, texture_id:               string,
	scale, offset, vertex_color:       datatypes.Vector3,
	native_mesh:                       ^kineffi.KineFilamentMesh,
	native_texture:                    ^kineffi.KineFilamentTex,
	native_context:                    ^kineffi.KineFilamentContext,
	attempted_mesh, attempted_texture: bool,
}

SpecialMesh_construct :: proc(renderer: ^Renderer_Object, data_model: rawptr) -> ^Object {
	m := new(SpecialMesh)
	m.object = Object_Init(&SpecialMesh_Class, "SpecialMesh")
	m.mesh_type = .Head
	m.scale, m.vertex_color = {1, 1, 1}, {1, 1, 1}
	return &m.object
}
special_mesh_release :: proc(m: ^SpecialMesh) {
	if m.native_context != nil {
		if m.native_mesh !=
		   nil {_ = kineffi.Kine_Filament_DestroyMesh(m.native_context, m.native_mesh)}
		if m.native_texture !=
		   nil {_ = kineffi.Kine_Filament_DestroyTex(m.native_context, m.native_texture)}
	}
	m.native_mesh, m.native_texture, m.native_context = nil, nil, nil
	m.attempted_mesh, m.attempted_texture = false, false
}
SpecialMesh_destroy :: proc(object: ^Object, renderer: ^Renderer_Object) {
	m := cast(^SpecialMesh)object
	special_mesh_release(m)
	delete(m.mesh_id)
	delete(m.texture_id)
	Object_Destroy(object)
	free(m)
}
SpecialMesh_clone :: proc(source, destination: ^Object) {
	src, dst := cast(^SpecialMesh)source, cast(^SpecialMesh)destination
	dst.mesh_type = src.mesh_type
	dst.mesh_id, dst.texture_id = strings.clone(src.mesh_id), strings.clone(src.texture_id)
	dst.scale, dst.offset, dst.vertex_color = src.scale, src.offset, src.vertex_color
}
SpecialMesh_get :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
) -> bool {
	m := cast(^SpecialMesh)object
	switch key {
	case "MeshType":
		_ = enums.Push_Item_By_Value(L, e, "MeshType", i64(m.mesh_type))
	case "MeshId":
		vm.PushString(L, m.mesh_id)
	case "TextureId":
		vm.PushString(L, m.texture_id)
	case "Scale":
		datatypes.Push_Vector3(L, m.scale)
	case "Offset":
		datatypes.Push_Vector3(L, m.offset)
	case "VertexColor":
		datatypes.Push_Vector3(L, m.vertex_color)
	case:
		return false
	}
	return true
}
SpecialMesh_set :: proc(
	L: ^vm.State,
	object: ^Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
	index: int,
) -> bool {
	m := cast(^SpecialMesh)object
	switch key {
	case "MeshType":
		m.mesh_type = enums.MeshType(enums.Arg_Item(L, index, e, "MeshType").value)
	case "MeshId", "TextureId":
		slot := &m.mesh_id if key == "MeshId" else &m.texture_id
		value := vm.ArgString(L, index)
		if slot^ != value {
			new_value := strings.clone(value)
			delete(slot^)
			slot^ = new_value
			special_mesh_release(m)
		}
	case "Scale":
		m.scale = datatypes.Arg_Vector3(L, index)
	case "Offset":
		m.offset = datatypes.Arg_Vector3(L, index)
	case "VertexColor":
		m.vertex_color = datatypes.Arg_Vector3(L, index)
	case:
		return false
	}
	return true
}
SpecialMesh_Find :: proc(object: ^Object) -> ^SpecialMesh {
	for child in object.children {
		if child != nil &&
		   !child.destroyed &&
		   child.class == &SpecialMesh_Class {return cast(^SpecialMesh)child}
	}
	return nil
}

SpecialMesh_Geometry :: proc(
	m: ^SpecialMesh,
	ctx: ^kineffi.KineFilamentContext,
) -> (
	^kineffi.KineFilamentMesh,
	^kineffi.KineFilamentTex,
) {
	if ctx == nil {return nil, nil}
	if m.native_context != ctx {special_mesh_release(m); m.native_context = ctx}
	if m.mesh_type == .FileMesh && !m.attempted_mesh && m.mesh_id != "" {
		m.attempted_mesh = true
		if data, found := assetstore.Resolve_Bytes(m.mesh_id); found && len(data) > 0 {
			hint := assetstore.Format_Hint(m.mesh_id)
			defer delete(hint)
			c_hint := strings.clone_to_cstring("glb" if hint == "" else hint)
			defer delete(c_hint)
			m.native_mesh = kineffi.Kine_Filament_CreateMeshFromMemoryIndexed(
				ctx,
				raw_data(data),
				uintptr(len(data)),
				c_hint,
				0,
			)
		} else {
			path := assetstore.Resolve_C_Path(m.mesh_id)
			defer delete(path)
			if path !=
			   nil {m.native_mesh = kineffi.Kine_Filament_CreateMeshFromPathIndexed(ctx, path, 0)} else {assetstore.Report_Missing_Asset(m.mesh_id, "SpecialMesh mesh")}
		}
	}
	when ODIN_OS != .JS {
		if !m.attempted_texture && m.texture_id != "" {
			m.attempted_texture = true
			w, h, ch: c.int
			pixels: [^]u8
			if data, found := Texture_Resolve_Bytes(m.texture_id); found && len(data) > 0 {
				pixels = image.load_from_memory(raw_data(data), c.int(len(data)), &w, &h, &ch, 4)
			} else {
				path := assetstore.Resolve_C_Path(m.texture_id)
				defer delete(path)
				if path !=
				   nil {pixels = image.load(path, &w, &h, &ch, 4)} else {assetstore.Report_Missing_Asset(m.texture_id, "SpecialMesh texture")}
			}
			if pixels != nil {
				defer image.image_free(pixels)
				if w > 0 &&
				   h >
					   0 {m.native_texture = kineffi.Kine_Filament_CreateTexFromPixels(ctx, i32(w), i32(h), i32(w) * 4, pixels)}
			}
		}
	}
	return m.native_mesh, m.native_texture
}
Register_SpecialMesh :: proc(registry: ^Registry) {
	Register_Class(
		registry,
		&SpecialMesh_Class,
		SpecialMesh_construct,
		SpecialMesh_destroy,
		get = SpecialMesh_get,
		set = SpecialMesh_set,
		clone = SpecialMesh_clone,
		properties = []string{"MeshType", "MeshId", "TextureId", "Scale", "Offset", "VertexColor"},
	)
}
