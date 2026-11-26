package services

import kineffi "../bindings"
import classes "../classes"
import enums "../enum"
import image "vendor:stb/image"

workspace_surface_slot :: proc(surface: enums.SurfaceType) -> int {
	#partial switch surface {
	case .Studs:
		return 0
	case .Inlet:
		return 1
	case .Glue:
		return 2
	case .Universal:
		return 3
	case:
		return -1
	}
}

workspace_surface_texture :: proc(workspace: ^Workspace, ctx: ^kineffi.KineFilamentContext, slot: int) -> ^kineffi.KineFilamentTex {
	if workspace.surface_textures[slot] != nil {return workspace.surface_textures[slot]}
	albedo, normal: string
	switch slot {
	case 0:
		albedo, normal = #load("../assets/surfaces/studs-albedo.png"), #load("../assets/surfaces/studs-normal.png")
	case 1:
		albedo, normal = #load("../assets/surfaces/inlet-albedo.png"), #load("../assets/surfaces/inlet-normal.png")
	case 2:
		albedo, normal = #load("../assets/surfaces/glue-albedo.png"), #load("../assets/surfaces/glue-normal.png")
	case 3:
		albedo, normal = #load("../assets/surfaces/universal-albedo.png"), #load("../assets/surfaces/universal-normal.png")
	}
	when ODIN_OS != .JS {
		w, h, channels, nw, nh, nc: i32
		a := image.load_from_memory(raw_data(albedo), i32(len(albedo)), &w, &h, &channels, 4)
		n := image.load_from_memory(raw_data(normal), i32(len(normal)), &nw, &nh, &nc, 4)
		defer image.image_free(a)
		defer image.image_free(n)
		if a == nil || n == nil {return nil}
		workspace.surface_textures[slot] = kineffi.Kine_Filament_CreatePbrTexFromPixels(
			ctx, w, h, w * 4, a, nw, nh, nw * 4, n, 0, 0, 0, nil, 0, 0, 0, nil, 0,
		)
	}
	return workspace.surface_textures[slot]
}

workspace_surface_mesh :: proc(workspace: ^Workspace, ctx: ^kineffi.KineFilamentContext) -> ^kineffi.KineFilamentMesh {
	if workspace.surface_mesh != nil {return workspace.surface_mesh}
	vertices := [4][8]f32 {
		{-0.5, 0, -0.5, 0, 1, 0, 0, 0},
		{0.5, 0, -0.5, 0, 1, 0, 1, 0},
		{0.5, 0, 0.5, 0, 1, 0, 1, 1},
		{-0.5, 0, 0.5, 0, 1, 0, 0, 1},
	}
	indices := [6]u16{0, 2, 1, 0, 3, 2}
	workspace.surface_mesh = kineffi.Kine_Filament_CreateCustomMesh(ctx, &vertices[0][0], 4, &indices[0], 6)
	return workspace.surface_mesh
}

workspace_append_part_surfaces :: proc(
	workspace: ^Workspace,
	ctx: ^kineffi.KineFilamentContext,
	part: ^classes.Part,
	base: kineffi.KineFilamentDrawItem,
	items: ^[dynamic]kineffi.KineFilamentDrawItem,
	params: ^Workspace_Draw_Params,
) {
	for surface, index in part.surfaces {
		slot := workspace_surface_slot(surface)
		if slot < 0 {continue}
		tex := workspace_surface_texture(workspace, ctx, slot)
		if tex == nil {continue}
		mesh := workspace_surface_mesh(workspace, ctx)
		if mesh == nil {continue}
		transform := classes.Part_Surface_Transform(part, enums.NormalId(index))
		item := base
		item.mesh = mesh
		item.tex = tex
		item.shader = nil
		item.param3 = -1
		item.flags &= ~u32(kineffi.KINE_FILAMENT_DRAW_CAST_SHADOWS)
		for value, i in transform {item.transform[i] = f32(value)}
		item.worldPosition = {transform[3], transform[7], transform[11]}
		if params != nil {
			params.hash = workspace_hash_u64(params.hash, u64(index))
			params.hash = workspace_hash_u64(params.hash, u64(uintptr(tex)))
			for value in transform {params.hash = workspace_hash_u64(params.hash, transmute(u64)value)}
		}
		append(items, item)
	}
}
