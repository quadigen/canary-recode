package services
// wire:service global="workspace"

import "base:runtime"


import assetstore "../assetstore"
import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import materials "../material"
import platform "../platform"
import profiling "../profiling"
import signals "../signals"
import tracy "../util/odin-tracy"
import vm "../vm"
import "core:math"
import "core:strings"

window_width: i32
window_height: i32

Workspace_Class := classes.Class_Info {
	name   = "Workspace",
	parent = &Service_Class,
}

Workspace :: struct {
	using service:               Service,
	water_time:                  f64,
	cube_mesh:                   ^kineffi.KineFilamentMesh,
	water_grid_mesh:             ^kineffi.KineFilamentMesh,
	sphere_mesh:                 ^kineffi.KineFilamentMesh,
	cylinder_mesh:               ^kineffi.KineFilamentMesh,
	cone_mesh:                   ^kineffi.KineFilamentMesh,
	torus_mesh:                  ^kineffi.KineFilamentMesh,
	pyramid_mesh:                ^kineffi.KineFilamentMesh,
	truss_mesh:                  ^kineffi.KineFilamentMesh,
	wedge_mesh:                  ^kineffi.KineFilamentMesh,
	triangle_wedge_mesh:         ^kineffi.KineFilamentMesh,
	corner_wedge_mesh:           ^kineffi.KineFilamentMesh,
	capsule_mesh:                ^kineffi.KineFilamentMesh,
	fallen_parts_destroy_height: f32,
	fall_height_enabled:         bool,
	distributed_game_time:       f64,
	simulate_physics:            bool,
	current_camera:              ^classes.Camera,
	finished_replicating:        ^signals.Signal,
	draw_items:                  [dynamic]kineffi.KineFilamentDrawItem,
	draw_version:                u64,
	draw_hash:                   u64,
	draw_hash_valid:             bool,
	cull_parts:                  bool,
	max_draw_distance:           f32,
	lod_distance:                f32,
}

load_mesh :: proc(
	ctx: ^kineffi.KineFilamentContext,
	data: string,
	format_hint: cstring = "glb",
) -> ^kineffi.KineFilamentMesh {
	mesh := kineffi.Kine_Filament_CreateMeshFromMemory(
		ctx,
		raw_data(data),
		uintptr(len(data)),
		format_hint,
	)
	kineffi.Kine_Filament_SetUseImportedMaterials(ctx, mesh, false)
	return mesh
}

workspace_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	workspace := new(Workspace)
	workspace.service = Service_Init(&Workspace_Class, "Workspace", data_model)
	workspace.fallen_parts_destroy_height = -500
	workspace.fall_height_enabled = true
	workspace.simulate_physics = true
	workspace.cull_parts = true
	workspace.max_draw_distance = 0
	workspace.lod_distance = 0
	return &workspace.object
}

workspace_ensure_meshes :: proc(
	workspace: ^Workspace,
	renderer: ^classes.Renderer_Object,
) -> bool {
	if workspace == nil || renderer == nil || renderer.Filament == nil {
		return false
	}

	if workspace.cube_mesh == nil {
		workspace.cube_mesh = load_mesh(renderer.Filament, #load("../assets/shapes/Block.glb"))
	}

	if workspace.water_grid_mesh == nil {
		workspace.water_grid_mesh = kineffi.Kine_Filament_CreateMesh(
			renderer.Filament,
			kineffi.KINE_MESH_WATER_GRID,
		)
	}

	if workspace.sphere_mesh == nil {
		workspace.sphere_mesh = load_mesh(renderer.Filament, #load("../assets/shapes/Ball.glb"))
	}

	if workspace.cylinder_mesh == nil {
		workspace.cylinder_mesh = load_mesh(
			renderer.Filament,
			#load("../assets/shapes/Cylinder.glb"),
		)
	}

	if workspace.cone_mesh == nil {
		workspace.cone_mesh = load_mesh(renderer.Filament, #load("../assets/shapes/Cone.glb"))
	}

	if workspace.torus_mesh == nil {
		workspace.torus_mesh = load_mesh(renderer.Filament, #load("../assets/shapes/Torus.glb"))
	}

	if workspace.pyramid_mesh == nil {
		workspace.pyramid_mesh = load_mesh(
			renderer.Filament,
			#load("../assets/shapes/Pyramid.glb"),
		)
	}

	if workspace.truss_mesh == nil {
		workspace.truss_mesh = load_mesh(renderer.Filament, #load("../assets/shapes/Truss.glb"))
	}

	if workspace.wedge_mesh == nil {
		workspace.wedge_mesh = load_mesh(renderer.Filament, #load("../assets/shapes/Wedge.glb"))
	}

	if workspace.triangle_wedge_mesh == nil {
		workspace.triangle_wedge_mesh = load_mesh(
			renderer.Filament,
			#load("../assets/shapes/Triangle Wedge.glb"),
		)
	}

	if workspace.corner_wedge_mesh == nil {
		workspace.corner_wedge_mesh = load_mesh(
			renderer.Filament,
			#load("../assets/shapes/Corner Wedge.glb"),
		)
	}

	if workspace.capsule_mesh == nil {
		workspace.capsule_mesh = load_mesh(
			renderer.Filament,
			#load("../assets/shapes/Capsule.glb"),
		)
	}

	return(
		workspace.cube_mesh != nil &&
		workspace.sphere_mesh != nil &&
		workspace.cylinder_mesh != nil &&
		workspace.cone_mesh != nil &&
		workspace.torus_mesh != nil &&
		workspace.pyramid_mesh != nil &&
		workspace.truss_mesh != nil &&
		workspace.wedge_mesh != nil &&
		workspace.triangle_wedge_mesh != nil &&
		workspace.corner_wedge_mesh != nil &&
		workspace.capsule_mesh != nil \
	)
}

workspace_part_mesh :: proc(
	workspace: ^Workspace,
	shape: enums.PartType,
) -> ^kineffi.KineFilamentMesh {
	switch shape {
	case .Ball:
		return workspace.sphere_mesh

	case .Block:
		return workspace.cube_mesh

	case .Cylinder:
		return workspace.cylinder_mesh

	case .Wedge:
		return workspace.wedge_mesh

	case .CornerWedge:
		return workspace.corner_wedge_mesh

	case .Cone:
		return workspace.cone_mesh

	case .Pyramid:
		return workspace.pyramid_mesh

	case .Truss:
		return workspace.truss_mesh

	case .Torus:
		return workspace.torus_mesh

	case .TriangleWedge:
		return workspace.triangle_wedge_mesh

	case .Capsule:
		return workspace.capsule_mesh
	}

	return workspace.cube_mesh
}

workspace_water_mesh :: proc(workspace: ^Workspace) -> ^kineffi.KineFilamentMesh {
	if workspace.water_grid_mesh != nil {
		return workspace.water_grid_mesh
	}
	return workspace.cube_mesh
}

workspace_meshpart_mesh :: proc(
	part: ^classes.MeshPart,
	ctx: ^kineffi.KineFilamentContext,
) -> ^kineffi.KineFilamentMesh {
	if part == nil || ctx == nil {
		return nil
	}
	if part.editable_mesh_id != 0 {
		return workspace_editable_meshpart_mesh(part, ctx)
	}
	if part.mesh_id == "" {
		if part.native_mesh != nil && part.native_context != nil {
			_ = kineffi.Kine_Filament_DestroyMesh(part.native_context, part.native_mesh)
			part.native_mesh = nil
			part.native_context = nil
		}
		return nil
	}
	if part.native_mesh != nil &&
	   part.native_context == ctx &&
	   !part.native_is_editable &&
	   part.native_mesh_id == part.mesh_id &&
	   part.native_mesh_index == part.mesh_index {
		return part.native_mesh
	}
	if part.native_mesh != nil && part.native_context != nil {
		_ = kineffi.Kine_Filament_DestroyMesh(part.native_context, part.native_mesh)
		part.native_mesh = nil
		part.native_context = nil
	}
	delete(part.native_mesh_id)
	part.native_mesh_id = strings.clone(part.mesh_id)
	part.native_mesh_index = part.mesh_index
	if data, found := assetstore.Resolve_Bytes(part.mesh_id); found && len(data) > 0 {
		hint := assetstore.Format_Hint(part.mesh_id)
		defer delete(hint)
		c_hint := hint == "" ? "glb" : strings.clone_to_cstring(hint)
		defer delete(c_hint)
		part.native_mesh = kineffi.Kine_Filament_CreateMeshFromMemoryIndexed(
			ctx,
			raw_data(data),
			uintptr(len(data)),
			c_hint,
			part.mesh_index,
		)
		if part.native_mesh != nil {
			part.native_context = ctx
			part.native_is_editable = false
		}
		return part.native_mesh
	}

	if assetstore.Is_Uri(part.mesh_id) {
		assetstore.Report_Missing_Asset(part.mesh_id, "Part mesh")
	}
	resolved := assetstore.Resolve_Path(part.mesh_id)
	defer delete(resolved)
	c_path := strings.clone_to_cstring(resolved)
	defer delete(c_path)
	part.native_mesh = kineffi.Kine_Filament_CreateMeshFromPathIndexed(ctx, c_path, part.mesh_index)
	if part.native_mesh != nil {
		part.native_context = ctx
		part.native_is_editable = false
	}
	return part.native_mesh
}

editable_mesh_render_scale :: proc(bounds: datatypes.Vector3) -> datatypes.Vector3 {
	scale := datatypes.Vector3{1, 1, 1}
	if bounds.x > 0 {
		scale.x = 2.0 / bounds.x
	}
	if bounds.y > 0 {
		scale.y = 2.0 / bounds.y
	}
	if bounds.z > 0 {
		scale.z = 2.0 / bounds.z
	}
	return scale
}

workspace_editable_meshpart_mesh :: proc(
	part: ^classes.MeshPart,
	ctx: ^kineffi.KineFilamentContext,
) -> ^kineffi.KineFilamentMesh {
	mesh := classes.EditableMesh_Of_Handle(part.editable_mesh_id)
	if mesh == nil {
		return nil
	}
	if part.native_mesh != nil &&
	   part.native_context == ctx &&
	   part.native_is_editable &&
	   part.editable_mesh_version == mesh.version {
		return part.native_mesh
	}
	if part.native_mesh != nil && part.native_context != nil {
		_ = kineffi.Kine_Filament_DestroyMesh(part.native_context, part.native_mesh)
		part.native_mesh = nil
		part.native_context = nil
	}

	corners: [dynamic]classes.EditableMesh_Corner_Data
	_ = classes.EditableMesh_Collect_Triangles(mesh, &corners)
	defer delete(corners)

	vertex_count := len(corners)
	if vertex_count == 0 {
		part.editable_mesh_version = mesh.version
		return nil
	}

	center := classes.EditableMesh_Get_Center(mesh)
	bounds := classes.EditableMesh_Get_Size(mesh)
	scale := editable_mesh_render_scale(bounds)

	vertex_data := make([dynamic]f32, 0, vertex_count * 8)
	defer delete(vertex_data)
	color_data := make([dynamic]f32, 0, vertex_count * 4)
	defer delete(color_data)
	indices := make([dynamic]u32, 0, vertex_count)
	defer delete(indices)

	for corner_index in 0 ..< vertex_count {
		corner := corners[corner_index]
		position := datatypes.Vector3 {
			(corner.position.x - center.x) * scale.x,
			(corner.position.y - center.y) * scale.y,
			(corner.position.z - center.z) * scale.z,
		}
		append(&indices, u32(corner_index))
		append(&vertex_data, position.x, position.y, position.z)
		append(&vertex_data, corner.normal.x, corner.normal.y, corner.normal.z)
		append(&vertex_data, corner.uv.X, corner.uv.Y)
		append(&color_data, corner.color.R, corner.color.G, corner.color.B, corner.alpha)
	}

	part.native_mesh = kineffi.Kine_Filament_CreateCustomMeshEx32(
		ctx,
		cast(^f32)raw_data(vertex_data),
		cast(^f32)raw_data(color_data),
		i32(vertex_count),
		cast(^u32)raw_data(indices),
		i32(len(indices)),
	)
	if part.native_mesh != nil {
		part.native_context = ctx
		part.native_is_editable = true
		part.editable_mesh_version = mesh.version
	}
	return part.native_mesh
}

workspace_has_parts :: proc(object: ^classes.Object) -> bool {
	if object == nil {return false}
	for child in object.children {
		if child == nil ||
		   child.destroyed ||
		   classes.Is_A_Class(child, &classes.ViewportFrame_Class) {continue}
		if classes.Is_A_Class(child, &classes.Part_Class) || workspace_has_parts(child) {
			return true
		}
	}
	return false
}

workspace_prepare_3d :: proc(workspace: ^Workspace, renderer: ^classes.Renderer_Object) {
	tracy.ZoneNC("Workspace Prepare 3D", 0xB48EAD)
	z := profiling.Begin("Workspace Prepare 3D", 0xB48EAD)
	if workspace == nil || !workspace_has_parts(&workspace.object) {return}
	if !workspace_ensure_meshes(workspace, renderer) {return}

	materials.init(renderer)

}

Workspace_Apply_View :: proc(
	renderer: ^classes.Renderer_Object,
	cframe: datatypes.CFrame,
) -> datatypes.CFrame {
	if renderer == nil || !renderer.HasWorldToView {return cframe}
	view := renderer.WorldToView
	return datatypes.CFrame_Mul_CFrame(
		datatypes.CFrame {
			x = view[0],
			y = view[1],
			z = view[2],
			r00 = view[3],
			r01 = view[4],
			r02 = view[5],
			r10 = view[6],
			r11 = view[7],
			r12 = view[8],
			r20 = view[9],
			r21 = view[10],
			r22 = view[11],
		},
		cframe,
	)
}

workspace_part_flags :: proc(part: ^classes.Part) -> u32 {
	flags := u32(kineffi.KINE_FILAMENT_DRAW_CULLING)


	if part.castshadow {
		flags |= u32(kineffi.KINE_FILAMENT_DRAW_CAST_SHADOWS)
	}


	flags |= u32(kineffi.KINE_FILAMENT_DRAW_RECEIVE_SHADOWS)

	return flags
}


WORKSPACE_FRUSTUM_NEAR :: f32(0.1)
WORKSPACE_FRUSTUM_FAR :: f32(1000.0)
WORKSPACE_CULL_MARGIN :: f32(2.0)


WORKSPACE_STREAM_ID :: u64(0x574F524B53504345)

Workspace_Frustum_Plane :: struct {
	normal: datatypes.Vector3,
	offset: f32,
}

Workspace_Frustum :: struct {
	planes: [6]Workspace_Frustum_Plane,
}

Workspace_Frustum_Build :: proc(
	camera: ^classes.Camera,
	far: f32,
) -> (
	frustum: Workspace_Frustum,
	ok: bool,
) {
	if camera == nil {return {}, false}

	width, height := classes.Camera_Effective_Viewport(camera)
	if width <= 0 || height <= 0 {return {}, false}

	tan_half_v := f32(math.tan(math.to_radians(f64(camera.field_of_view)) * 0.5))
	tan_half_x := tan_half_v * (width / height)

	cframe := camera.CFrame
	eye := datatypes.Vector3{cframe.x, cframe.y, cframe.z}
	forward := datatypes.CFrame_LookVector(cframe)
	right := datatypes.CFrame_RightVector(cframe)
	up := datatypes.CFrame_UpVector(cframe)


	normals := [6]datatypes.Vector3 {
		forward,
		datatypes.Vec3_Negate(forward),
		datatypes.Vec3_Subtract(datatypes.Vec3_Multiply(forward, tan_half_v), up),
		datatypes.Vec3_Add(datatypes.Vec3_Multiply(forward, tan_half_v), up),
		datatypes.Vec3_Subtract(datatypes.Vec3_Multiply(forward, tan_half_x), right),
		datatypes.Vec3_Add(datatypes.Vec3_Multiply(forward, tan_half_x), right),
	}

	offsets := [6]f32 {
		-datatypes.Vec3_Dot(normals[0], eye) - WORKSPACE_FRUSTUM_NEAR,
		-datatypes.Vec3_Dot(normals[1], eye) + far,
		-datatypes.Vec3_Dot(normals[2], eye),
		-datatypes.Vec3_Dot(normals[3], eye),
		-datatypes.Vec3_Dot(normals[4], eye),
		-datatypes.Vec3_Dot(normals[5], eye),
	}

	for i in 0 ..< 6 {
		length := datatypes.Vec3_Magnitude(normals[i])
		if length <= 0 {return {}, false}
		inverse := 1.0 / length
		frustum.planes[i] = Workspace_Frustum_Plane {
			normal = datatypes.Vec3_Multiply(normals[i], inverse),
			offset = offsets[i] * inverse,
		}
	}

	return frustum, true
}


Workspace_Frustum_Contains_Sphere :: proc(
	frustum: ^Workspace_Frustum,
	center: datatypes.Vector3,
	radius: f32,
) -> bool {
	if frustum == nil {return true}
	for plane in frustum.planes {
		if datatypes.Vec3_Dot(plane.normal, center) + plane.offset < -radius {
			return false
		}
	}
	return true
}


Workspace_Draw_Params :: struct {
	reflection_center: datatypes.Vector3,
	reflection_radius: f32,
	frustum:           ^Workspace_Frustum,
	eye:               datatypes.Vector3,
	max_distance_sq:   f32,
	lod_distance_sq:   f32,
	lod_mesh:          ^kineffi.KineFilamentMesh,
	hash:              u64,
}

workspace_hash_f32 :: proc(hash: u64, value: f32) -> u64 {
	return (hash ~ u64(transmute(u32)value)) * 1099511628211
}

workspace_hash_u64 :: proc(hash: u64, value: u64) -> u64 {
	return (hash ~ value) * 1099511628211
}

workspace_distance_squared :: proc(a, b: datatypes.Vector3) -> f32 {
	dx := a.x - b.x
	dy := a.y - b.y
	dz := a.z - b.z
	return dx * dx + dy * dy + dz * dz
}

workspace_append_draw_items :: proc(
	workspace: ^Workspace,
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
	items: ^[dynamic]kineffi.KineFilamentDrawItem,
	params: ^Workspace_Draw_Params,
) {
	for child in object.children {
		if child == nil ||
		   child.destroyed ||
		   classes.Is_A_Class(child, &classes.ViewportFrame_Class) {continue}

		if classes.Is_A_Class(child, &classes.Part_Class) {
			part := cast(^classes.Part)child
			mesh := workspace_part_mesh(workspace, part.shape)
			is_meshpart := classes.Is_A_Class(child, &classes.MeshPart_Class)
			if part.transparency >= 1.0 {
				workspace_append_draw_items(workspace, child, renderer, items, params)
				continue
			}

			if is_meshpart {
				mesh = workspace_meshpart_mesh(cast(^classes.MeshPart)child, renderer.Filament)
				if mesh == nil {
					mesh = workspace_part_mesh(workspace, part.shape)
				}
			}
			cframe := part.cframe
			size := part.size
			render_size := datatypes.Vector3{size.x * 0.5, size.y * 0.5, size.z * 0.5}

			render_material, material_params := materials.Lookup(part.material)
			material_kind := material_params.kind
			param1 := material_params.param1
			param2 := material_params.param2
			param3 := material_params.param3
			transmission := material_params.transmission

			if material_kind == kineffi.KINE_MAT_GLASS {
				transmission = f32(part.transparency)
			}

			if material_kind == kineffi.KINE_MAT_WATER {
				mesh = workspace_water_mesh(workspace)
				render_size.x = size.x
				render_size.y = size.y
				render_size.z = size.z
			}

			center := datatypes.Vector3{cframe.x, cframe.y, cframe.z}
			radius := 0.5 * datatypes.Vec3_Magnitude(size) + WORKSPACE_CULL_MARGIN
			if is_meshpart && mesh != nil {


				local_center, half_extent: [3]f32
				if kineffi.Kine_Filament_GetMeshBounds(mesh, &local_center[0], &half_extent[0]) {
					center = datatypes.CFrame_PointToWorldSpace(
						cframe,
						{
							local_center[0] * render_size.x,
							local_center[1] * render_size.y,
							local_center[2] * render_size.z,
						},
					)
					radius =
						datatypes.Vec3_Magnitude(
							datatypes.Vector3 {
								half_extent[0] * render_size.x,
								half_extent[1] * render_size.y,
								half_extent[2] * render_size.z,
							},
						) +
						WORKSPACE_CULL_MARGIN
				}
			}
			if variant := classes.MaterialVariant_Find(
				child.signal_registry,
				part.material_variant,
			); variant != nil {
				radius += abs(variant.height_scale) + variant.displacement_bounds
			}

			visible := true
			distance_sq: f32
			if params != nil {
				distance_sq = workspace_distance_squared(center, params.eye)
				if params.max_distance_sq > 0 &&
				   distance_sq > math.pow(math.sqrt(params.max_distance_sq) + radius, 2) {
					visible = false
				}
				if visible &&
				   params.frustum != nil &&
				   !Workspace_Frustum_Contains_Sphere(params.frustum, center, radius) {
					visible = false
				}


				if !visible && params.reflection_radius > 0 {
					capture_radius := params.reflection_radius + radius
					visible =
						workspace_distance_squared(center, params.reflection_center) <=
						capture_radius * capture_radius
				}
			}

			if visible {


				if params != nil &&
				   params.lod_mesh != nil &&
				   params.lod_distance_sq > 0 &&
				   !is_meshpart &&
				   material_kind != kineffi.KINE_MAT_WATER &&
				   distance_sq > params.lod_distance_sq {
					mesh = params.lod_mesh
				}

				draw_texture := render_material.texture
				mesh_texture: ^kineffi.KineFilamentTex = nil
				if mesh != nil && material_kind == kineffi.KINE_MAT_DEFAULT {
					mesh_texture = kineffi.Kine_Filament_GetMeshTexture(mesh)
					if mesh_texture != nil {
						draw_texture = mesh_texture


						param3 = 1.0
					}
				}

				if material_kind == kineffi.KINE_MAT_DEFAULT &&
				   render_material.texture != nil &&
				   mesh_texture == nil {
					STUDS_PER_TILE :: f32(4.0)

					largest_dimension := size.x
					if size.y > largest_dimension {
						largest_dimension = size.y
					}
					if size.z > largest_dimension {
						largest_dimension = size.z
					}

					param3 = largest_dimension / STUDS_PER_TILE

					if param3 < 1.0 {
						param3 = 1.0
					}
				}

				shader, shader_revision := classes.MaterialVariant_Resolve(
					child.signal_registry,
					part.material_variant,
					renderer.Filament,
				)
				item := kineffi.KineFilamentDrawItem {
					shader       = shader,
					mesh         = mesh,
					tex          = draw_texture,
					transform    = {
						cframe.r00 * render_size.x,
						cframe.r01 * render_size.y,
						cframe.r02 * render_size.z,
						cframe.x,
						cframe.r10 * render_size.x,
						cframe.r11 * render_size.y,
						cframe.r12 * render_size.z,
						cframe.y,
						cframe.r20 * render_size.x,
						cframe.r21 * render_size.y,
						cframe.r22 * render_size.z,
						cframe.z,
						0,
						0,
						0,
						1,
					},
					r            = part.color.R,
					g            = part.color.G,
					b            = part.color.B,
					param1       = param1,
					param2       = param2,
					param3       = param3,
					transmission = transmission,
					materialKind = material_kind,
					flags        = workspace_part_flags(part),
				}


				if params != nil {
					params.hash = workspace_hash_u64(params.hash, u64(uintptr(shader)))
					params.hash = workspace_hash_u64(params.hash, shader_revision)
					params.hash = workspace_hash_u64(params.hash, u64(uintptr(mesh)))
					params.hash = workspace_hash_u64(params.hash, u64(uintptr(draw_texture)))
					for i in 0 ..< 16 {
						params.hash = workspace_hash_f32(params.hash, item.transform[i])
					}
					params.hash = workspace_hash_f32(params.hash, item.r)
					params.hash = workspace_hash_f32(params.hash, item.g)
					params.hash = workspace_hash_f32(params.hash, item.b)
					params.hash = workspace_hash_f32(params.hash, item.param1)
					params.hash = workspace_hash_f32(params.hash, item.param2)
					params.hash = workspace_hash_f32(params.hash, item.param3)
					params.hash = workspace_hash_f32(params.hash, item.transmission)
					params.hash = workspace_hash_u64(params.hash, u64(item.materialKind))
					params.hash = workspace_hash_u64(params.hash, u64(item.flags))
				}

				append(items, item)
			}
		}

		workspace_append_draw_items(workspace, child, renderer, items, params)
	}
}

workspace_render_3d :: proc(object: ^classes.Object, ctx: ^classes.Class_Step_Context) {
	tracy.ZoneNC("Workspace Render 3D", 0xB48EAD)
	z := profiling.Begin("Workspace Render 3D", 0xB48EAD)
	workspace := cast(^Workspace)object
	if !workspace_has_parts(object) {return}
	if ctx == nil || ctx.renderer == nil || ctx.renderer.Filament == nil {return}

	{
		tracy.ZoneNC("WS Mesh Setup", 0x9CDCFE)
		setup := profiling.Begin("WS Mesh Setup", 0x9CDCFE)
		if !workspace_ensure_meshes(workspace, ctx.renderer) {return}
		materials.init(ctx.renderer)
	}

	{
		tc := tracy.ZoneNC("WS Collect Draw Items", 0xB48EAD)
		collect := profiling.Begin("WS Collect Draw Items", 0xB48EAD)


		platform.GetWindowSize(ctx.renderer.Window, &window_width, &window_height)

		items := &workspace.draw_items
		clear(items)

		params := Workspace_Draw_Params {
			hash = 1469598103934665603,
		}
		probe_center: [3]f32
		if kineffi.Kine_Filament_GetReflectionProbeRegion(
			ctx.renderer.Filament,
			&probe_center[0],
			&params.reflection_radius,
		) {
			params.reflection_center = {probe_center[0], probe_center[1], probe_center[2]}
		}
		frustum: Workspace_Frustum

		if camera := cast(^classes.Camera)ctx.renderer.ActiveCamera; camera != nil {
			params.eye = datatypes.Vector3{camera.CFrame.x, camera.CFrame.y, camera.CFrame.z}

			if workspace.lod_distance > 0 {
				params.lod_distance_sq = workspace.lod_distance * workspace.lod_distance
				params.lod_mesh = workspace.cube_mesh
			}

			if workspace.max_draw_distance > 0 {
				params.max_distance_sq = workspace.max_draw_distance * workspace.max_draw_distance
			}

			if workspace.cull_parts {
				far := WORKSPACE_FRUSTUM_FAR
				if workspace.max_draw_distance > 0 && workspace.max_draw_distance < far {
					far = workspace.max_draw_distance
				}
				if built, ok := Workspace_Frustum_Build(camera, far); ok {
					frustum = built
					params.frustum = &frustum
				}
			}
		}

		workspace_append_draw_items(workspace, object, ctx.renderer, items, &params)
		tracy.ZoneValue(tc, u64(len(items^)))

		if len(items^) > 0 {
			ts := tracy.ZoneNC("WS Filament Submit", 0xC678DD)
			submit := profiling.Begin("WS Filament Submit", 0xC678DD)
			tracy.ZoneValue(ts, u64(len(items^)))


			hash := workspace_hash_u64(params.hash, u64(len(items^)))
			if !workspace.draw_hash_valid || hash != workspace.draw_hash {
				workspace.draw_version += 1
				workspace.draw_hash = hash
				workspace.draw_hash_valid = true
			}

			_ = kineffi.Kine_Filament_DrawMeshListVersioned(
				ctx.renderer.Filament,
				raw_data(items^),
				u32(len(items^)),
				WORKSPACE_STREAM_ID,
				workspace.draw_version,
			)
		} else {
			workspace.draw_hash_valid = false
		}
	}
}

workspace_physics :: proc(workspace: ^Workspace) -> ^Physics {
	object := Service_Get_Service(&workspace.service, "Physics")
	if object == nil {return nil}
	return cast(^Physics)object
}


Workspace_Finished_Replicating_Signal :: proc(workspace: ^Workspace) -> ^signals.Signal {
	if workspace == nil {return nil}
	if workspace.finished_replicating != nil {return workspace.finished_replicating}
	registry := workspace.signal_registry
	if registry == nil {return nil}
	L := registry.vm_state
	if L == nil || registry.signal_registry == nil {return nil}
	signal := signals.Create(registry.signal_registry)
	workspace.finished_replicating = signal
	return signal
}


Workspace_Fire_Finished_Replicating :: proc(L: ^vm.State, workspace: ^Workspace) {
	if workspace == nil || L == nil {return}
	signal := workspace.finished_replicating
	if signal == nil || signal.destroyed {return}
	if len(signal.listeners) == 0 && len(signal.waiters) == 0 {return}
	signals.Fire(L, signal, 0)
}

workspace_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	workspace := cast(^Workspace)object
	physics := workspace_physics(workspace)
	switch key {
	case "CurrentCamera":
		classes.Push_Object(L, cast(^classes.Object)workspace.current_camera)
	case "SimulatePhysics":
		vm.PushBoolean(L, workspace.simulate_physics)
	case "Gravity":
		vm.PushNumber(L, physics == nil ? 196.2 : f64(physics.gravity))
	case "FallenPartsDestroyHeight":
		vm.PushNumber(L, f64(workspace.fallen_parts_destroy_height))
	case "FallHeightEnabled":
		vm.PushBoolean(L, workspace.fall_height_enabled)
	case "DistributedGameTime":
		vm.PushNumber(L, workspace.distributed_game_time)
	case "RenderCulling":
		vm.PushBoolean(L, workspace.cull_parts)
	case "MaxDrawDistance":
		vm.PushNumber(L, f64(workspace.max_draw_distance))
	case "LODDistance":
		vm.PushNumber(L, f64(workspace.lod_distance))
	case "FinishedReplicating":
		signal := Workspace_Finished_Replicating_Signal(workspace)
		if signal == nil {return false}
		signals.Push(L, signal)
	case "Raycast",
	     "GetNumAwakeParts",
	     "GetPhysicsThrottling",
	     "GetRealPhysicsFPS",
	     "PGSIsEnabled":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

workspace_set :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
	value_index: int,
) -> bool {
	workspace := cast(^Workspace)object
	switch key {
	case "CurrentCamera":
		camera := classes.object_from_argument(L, value_index)
		if camera == nil || !classes.Is_A(camera, "Camera") {return false}
		workspace.current_camera = cast(^classes.Camera)camera
		registry := cast(^DataModel)workspace.data_model
		if registry != nil && registry.registry.classes.renderer != nil {
			registry.registry.classes.renderer.ActiveCamera = camera
		}
	case "SimulatePhysics":
		workspace.simulate_physics = vm.ArgBoolean(L, value_index)
	case "Gravity":
		physics := workspace_physics(workspace)
		if physics == nil {return false}
		Physics_Set_Gravity(physics, f32(vm.ArgNumber(L, value_index)))
	case "FallenPartsDestroyHeight":
		workspace.fallen_parts_destroy_height = clamp(
			f32(vm.ArgNumber(L, value_index)),
			-50_000,
			50_000,
		)
	case "FallHeightEnabled":
		workspace.fall_height_enabled = vm.ArgBoolean(L, value_index)
	case "RenderCulling":
		workspace.cull_parts = vm.ArgBoolean(L, value_index)
	case "MaxDrawDistance":
		workspace.max_draw_distance = max(0, f32(vm.ArgNumber(L, value_index)))
	case "LODDistance":
		workspace.lod_distance = max(0, f32(vm.ArgNumber(L, value_index)))
	case:
		return false
	}
	return true
}

workspace_kne_raycast :: proc "contextless" (ctx: ^classes.Class_Export_Context) -> i32 {
	context = runtime.default_context()
	count, _ := workspace_namecall(ctx.L, ctx.object, ctx.datatypes, ctx.enums, "Raycast")
	return count
}

workspace_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	workspace := cast(^Workspace)object
	physics := workspace_physics(workspace)
	switch method {
	case "Raycast":
		if datatype_registry ==
		   nil {return vm.RaiseError(L, "datatype registry is unavailable"), true}
		x, y, z := vm.ArgVector3(L, 2)
		dx, dy, dz := vm.ArgVector3(L, 3)
		params: ^datatypes.RaycastParams
		if !vm.IsNoneOrNil(L, 4) {params = datatypes.Arg_RaycastParams(L, 4, datatype_registry)}
		if physics == nil {
			vm.PushNil(L)
			return 1, true
		}
		result, hit := Physics_Raycast(
			physics,
			object,
			datatypes.Vector3{x, y, z},
			datatypes.Vector3{dx, dy, dz},
			params,
		)
		if !hit {vm.PushNil(L)} else {datatypes.Push_RaycastResult(L, datatype_registry, result)}
		return 1, true
	case "GetNumAwakeParts":
		vm.PushNumber(L, f64(Physics_Get_Num_Awake_Parts(physics)))
		return 1, true
	case "GetPhysicsThrottling":
		vm.PushNumber(L, 0)
		return 1, true
	case "GetRealPhysicsFPS":
		vm.PushNumber(L, 60)
		return 1, true
	case "PGSIsEnabled":
		vm.PushBoolean(L, true)
		return 1, true
	case "GetWindowDimensions":
		vec2 := datatypes.Vector2{f32(window_width), f32(window_height)}
		datatypes.Push_Vector2(L, datatype_registry, vec2)
		return 1, true
	}
	return 0, false
}

workspace_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	workspace := cast(^Workspace)object

	materials.shutdown(renderer)

	if renderer != nil && renderer.Filament != nil {
		if workspace.cube_mesh !=
		   nil {_ = kineffi.Kine_Filament_DestroyMesh(renderer.Filament, workspace.cube_mesh)}
		if workspace.sphere_mesh !=
		   nil {_ = kineffi.Kine_Filament_DestroyMesh(renderer.Filament, workspace.sphere_mesh)}
		if workspace.cylinder_mesh !=
		   nil {_ = kineffi.Kine_Filament_DestroyMesh(renderer.Filament, workspace.cylinder_mesh)}
	}
	delete(workspace.draw_items)
	classes.Object_Destroy(object)
	free(workspace)
}

Register_Workspace_Class :: proc(registry: ^classes.Registry) {
	classes.ViewportFrame_MeshPart_Provider = workspace_meshpart_mesh
	classes.Register_Class(
		registry,
		&Workspace_Class,
		workspace_construct,
		workspace_destroy,
		creatable = false,
		get = workspace_get,
		set = workspace_set,
		namecall = workspace_namecall,
		properties = []string {
			"CurrentCamera",
			"SimulatePhysics",
			"Gravity",
			"FallenPartsDestroyHeight",
			"FallHeightEnabled",
			"DistributedGameTime",
			"RenderCulling",
			"MaxDrawDistance",
			"LODDistance",
			"FinishedReplicating",
		},
		methods = []string {
			"Raycast",
			"GetNumAwakeParts",
			"GetPhysicsThrottling",
			"GetRealPhysicsFPS",
			"PGSIsEnabled",
		},
		events = []string{"FinishedReplicating"},
		exports = []classes.Class_Export{{name = "Raycast", handler = workspace_kne_raycast}},
	)
}
