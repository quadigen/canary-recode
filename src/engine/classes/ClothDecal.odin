package classes

import kineffi "../bindings"
import "core:math"

decal_step_cloth :: proc(decal: ^Decal, renderer: ^Renderer_Object) {
	cloth := cast(^Cloth)decal.parent
	workspace: ^Object
	for ancestor := cloth.parent; ancestor != nil; ancestor = ancestor.parent {
		if Is_A_Class(ancestor, &ViewportFrame_Class) {break}
		if Is_A(ancestor, "Workspace") {
			workspace = ancestor
			break
		}
	}
	if workspace == nil ||
	   cloth.destroyed ||
	   !cloth.enabled ||
	   decal.transparency >= 1 ||
	   (decal.face != .Front && decal.face != .Back) ||
	   math.is_nan(decal.z_offset) ||
	   math.is_inf(decal.z_offset) {
		decal_destroy_renderable(decal, renderer)
		return
	}
	if !Cloth_Prepare_Surface(cloth, workspace) {
		decal_destroy_renderable(decal, renderer)
		return
	}

	Cloth_Build_Surface(cloth)
	if decal.cloth_parent != &cloth.object || decal.cloth_face != decal.face ||
	   decal.cloth_topology_revision != cloth.topology_revision {
		decal_destroy_renderable(decal, renderer)
	}
	if decal.cloth_mesh == nil ||
	   decal.cloth_revision != cloth.revision ||
	   decal.cloth_z_offset != decal.z_offset {
		if !decal_update_cloth_mesh(decal, cloth, renderer.Filament) {
			decal_destroy_renderable(decal, renderer)
			return
		}
	}

	base_transform := Cloth_Surface_Transform(cloth)
	transform: [16]f64
	for v, i in base_transform {transform[i] = f64(v)}
	pin := Cloth_World_Pin(cloth)
	transform[3], transform[7], transform[11] = pin.x, pin.y, pin.z
	decal_apply_style(decal, renderer, &transform, cloth.width, cloth.size.Y)
	_ = kineffi.Kine_Filament_EditMeshDecal(
		renderer.Filament,
		decal.native_decal,
		decal.cloth_mesh,
		decal.culling,
		decal.cast_shadows,
		decal.receive_shadows,
	)
}

decal_update_cloth_mesh :: proc(
	decal: ^Decal,
	cloth: ^Cloth,
	ctx: ^kineffi.KineFilamentContext,
) -> bool {
	vertices := cloth.decal_vertices
	copy(vertices, cloth.surface_vertices)
	indices := cloth.surface_indices
	front := decal.face == .Front
	if front {indices = cloth.surface_back_indices}
	for &vertex in vertices {
		if front {
			vertex[3], vertex[4], vertex[5] = -vertex[3], -vertex[4], -vertex[5]
			vertex[6] = 1 - vertex[6]
		}
		vertex[7] = 1 - vertex[7]
		for axis in 0 ..< 3 {
			vertex[axis] += vertex[axis + 3] * decal.z_offset
		}
	}

	if decal.cloth_mesh == nil {
		mesh := kineffi.Kine_Filament_CreateCustomMesh32(
			ctx,
			&vertices[0][0],
			i32(len(vertices)),
			&indices[0],
			i32(len(indices)),
		)
		if mesh == nil {return false}
		decal.native_decal = kineffi.Kine_Filament_CreateMeshDecal(ctx, mesh, decal.native_texture)
		if decal.native_decal < 0 {
			kineffi.Kine_Filament_DestroyMesh(ctx, mesh)
			return false
		}
		decal.cloth_mesh = mesh
		decal.cloth_parent = &cloth.object
		decal.cloth_face = decal.face
		decal.cloth_topology_revision = cloth.topology_revision
		decal.color_dirty = true
	} else if !kineffi.Kine_Filament_UpdateCustomMesh(
		ctx,
		decal.cloth_mesh,
		&vertices[0][0],
		i32(len(vertices)),
	) {
		return false
	}
	decal.cloth_revision = cloth.revision
	decal.cloth_z_offset = decal.z_offset
	return true
}
