package services

import kineffi "../bindings"
import classes "../classes"

workspace_append_cloth :: proc(
	workspace: ^Workspace,
	cloth: ^classes.Cloth,
	renderer: ^classes.Renderer_Object,
	items: ^[dynamic]kineffi.KineFilamentDrawItem,
	params: ^Workspace_Draw_Params,
) {
	if !cloth.enabled {return}
	anchor, valid := classes.Cloth_Anchor(cloth, &workspace.object)
	if !valid {return}
	if !cloth.initialized {classes.Cloth_Initialize(cloth, anchor)}

	mesh := workspace_cloth_mesh(cloth, renderer.Filament)
	if mesh == nil {return}
	shader, shader_revision := classes.MaterialVariant_Resolve(
		cloth.signal_registry,
		cloth.material_variant,
		renderer.Filament,
	)
	item := kineffi.KineFilamentDrawItem {
		mesh      = mesh,
		shader    = shader,
		transform = classes.Cloth_Surface_Transform(cloth),
		r         = cloth.color.R,
		g         = cloth.color.G,
		b         = cloth.color.B,
		flags     = kineffi.KINE_FILAMENT_DRAW_CAST_SHADOWS | kineffi.KINE_FILAMENT_DRAW_RECEIVE_SHADOWS,
	}
	if params != nil {
		params.hash = workspace_hash_u64(params.hash, u64(uintptr(mesh)))
		params.hash = workspace_hash_u64(params.hash, cloth.revision)
		params.hash = workspace_hash_u64(params.hash, u64(uintptr(shader)))
		params.hash = workspace_hash_u64(params.hash, shader_revision)
		params.hash = workspace_hash_f32(params.hash, item.r)
		params.hash = workspace_hash_f32(params.hash, item.g)
		params.hash = workspace_hash_f32(params.hash, item.b)
	}
	append(items, item)
}

workspace_cloth_mesh :: proc(
	cloth: ^classes.Cloth,
	ctx: ^kineffi.KineFilamentContext,
) -> ^kineffi.KineFilamentMesh {
	if cloth.mesh_context != ctx && cloth.mesh != nil {
		kineffi.Kine_Filament_DestroyMesh(cloth.mesh_context, cloth.mesh)
		cloth.mesh = nil
	}
	if cloth.mesh != nil && cloth.mesh_revision == cloth.revision {return cloth.mesh}

	count :: classes.CLOTH_VERTEX_COUNT
	indices: classes.Cloth_Indices
	vertices: classes.Cloth_Vertices
	classes.Cloth_Build_Surface(cloth, &vertices, &indices)
	if cloth.mesh == nil {
		cloth.mesh = kineffi.Kine_Filament_CreateCustomMesh32(
			ctx,
			&vertices[0][0],
			count,
			&indices[0],
			len(indices),
		)
		if cloth.mesh == nil {return nil}
		kineffi.Kine_Filament_SetMeshDoubleSided(cloth.mesh)
		cloth.mesh_context = ctx
	} else if !kineffi.Kine_Filament_UpdateCustomMesh(ctx, cloth.mesh, &vertices[0][0], count) {
		return nil
	}
	cloth.mesh_revision = cloth.revision
	return cloth.mesh
}
