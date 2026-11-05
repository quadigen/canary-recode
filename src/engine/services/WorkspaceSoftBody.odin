package services

import kineffi "../bindings"
import classes "../classes"
import materials "../material"
import "core:math/linalg"

workspace_append_softbody :: proc(
	body: ^classes.SoftBody,
	renderer: ^classes.Renderer_Object,
	items: ^[dynamic]kineffi.KineFilamentDrawItem,
	params: ^Workspace_Draw_Params,
) {
	if !body.enabled || body.transparency >= 1 {return}
	softbody_prepare_geometry(body)
	if len(body.indices) == 0 || !physics_valid_cframe(body.cframe) {return}
	mesh := workspace_softbody_mesh(body, renderer.Filament)
	if mesh == nil {return}
	shader, shader_revision := classes.MaterialVariant_Resolve(
		body.signal_registry,
		body.material_variant,
		renderer.Filament,
	)
	material, surface := materials.Lookup(body.material)
	opacity := 1 - body.transparency
	alpha_bits: u32
	if body.transparency > 0 {
		shader = kineffi.Kine_Filament_Shader_ResolveFade(shader)
		if shader != nil {
			surface.kind, surface.transmission = kineffi.KINE_MAT_FADE, opacity
		} else {
			switch surface.kind {
			case kineffi.KINE_MAT_GLASS:
				surface.transmission = body.transparency
			case kineffi.KINE_MAT_WATER, kineffi.KINE_MAT_FORCEFIELD:
				alpha_bits = transmute(u32)opacity
			case kineffi.KINE_MAT_NEON:
				surface.kind, surface.transmission = kineffi.KINE_MAT_NEON_FADE, opacity
			case:
				surface.kind, surface.transmission = kineffi.KINE_MAT_FADE, opacity
			}
		}
	}
	frame := classes.SoftBody_Current_CFrame(body)
	item := kineffi.KineFilamentDrawItem {
		mesh         = mesh,
		shader       = shader,
		tex          = material.texture,
		transform    = {
			frame.r00,
			frame.r01,
			frame.r02,
			frame.x,
			frame.r10,
			frame.r11,
			frame.r12,
			frame.y,
			frame.r20,
			frame.r21,
			frame.r22,
			frame.z,
			0,
			0,
			0,
			1,
		},
		r            = body.color.R,
		g            = body.color.G,
		b            = body.color.B,
		param1       = surface.param1,
		param2       = surface.param2,
		param3       = surface.param3,
		transmission = surface.transmission,
		materialKind = surface.kind,
		reserved     = alpha_bits,
		flags        = kineffi.KINE_FILAMENT_DRAW_CAST_SHADOWS | kineffi.KINE_FILAMENT_DRAW_RECEIVE_SHADOWS,
	}
	if params != nil {
		params.hash = workspace_hash_u64(params.hash, u64(uintptr(mesh)))
		params.hash = workspace_hash_u64(params.hash, body.revision)
		params.hash = workspace_hash_u64(params.hash, u64(uintptr(shader)))
		params.hash = workspace_hash_u64(params.hash, shader_revision)
		params.hash = workspace_hash_u64(params.hash, u64(uintptr(item.tex)))
		params.hash = workspace_hash_u64(params.hash, u64(item.materialKind))
		params.hash = workspace_hash_u64(params.hash, u64(item.reserved))
		params.hash = workspace_hash_f32(params.hash, item.param1)
		params.hash = workspace_hash_f32(params.hash, item.param2)
		params.hash = workspace_hash_f32(params.hash, item.param3)
		params.hash = workspace_hash_f32(params.hash, item.transmission)
		for component in item.transform {params.hash = workspace_hash_f32(params.hash, component)}
		params.hash = workspace_hash_f32(params.hash, item.r)
		params.hash = workspace_hash_f32(params.hash, item.g)
		params.hash = workspace_hash_f32(params.hash, item.b)
	}
	append(items, item)
}

workspace_softbody_mesh :: proc(
	body: ^classes.SoftBody,
	ctx: ^kineffi.KineFilamentContext,
) -> ^kineffi.KineFilamentMesh {
	if body.mesh_context != ctx {classes.SoftBody_Release_Render_Mesh(body)}
	if body.mesh != nil && body.mesh_revision == body.revision {return body.mesh}
	for &vertex, i in body.vertices {
		position := body.positions[body.vertex_particles[i]]
		vertex[0], vertex[1], vertex[2] = position.x, position.y, position.z
		vertex[3], vertex[4], vertex[5] = 0, 0, 0
	}
	for i := 0; i < len(body.indices); i += 3 {
		a, b, c := body.indices[i], body.indices[i + 1], body.indices[i + 2]
		va, vb, vc := body.vertices[a], body.vertices[b], body.vertices[c]
		ab := [3]f32{vb[0] - va[0], vb[1] - va[1], vb[2] - va[2]}
		ac := [3]f32{vc[0] - va[0], vc[1] - va[1], vc[2] - va[2]}
		normal := linalg.cross(ab, ac)
		for index in ([3]u32{a, b, c}) {
			for axis in 0 ..< 3 {body.vertices[index][3 + axis] += normal[axis]}
		}
	}
	for &vertex in body.vertices {
		normal := linalg.normalize([3]f32{vertex[3], vertex[4], vertex[5]})
		if !(linalg.dot(normal, normal) > 0) {normal = {0, 1, 0}}
		vertex[3], vertex[4], vertex[5] = normal.x, normal.y, normal.z
	}

	if body.mesh == nil {
		body.mesh = kineffi.Kine_Filament_CreateCustomMesh32(
			ctx,
			&body.vertices[0][0],
			i32(len(body.vertices)),
			&body.indices[0],
			i32(len(body.indices)),
		)
		if body.mesh == nil {return nil}
		if !body.closed_surface {kineffi.Kine_Filament_SetMeshDoubleSided(body.mesh)}
		body.mesh_context = ctx
	} else if !kineffi.Kine_Filament_UpdateCustomMesh(
		ctx,
		body.mesh,
		&body.vertices[0][0],
		i32(len(body.vertices)),
	) {
		return nil
	}
	body.mesh_revision = body.revision
	return body.mesh
}
