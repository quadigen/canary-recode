package services

import "core:fmt"


import assetstore "../assetstore"
import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import materials "../material"
import platform "../platform"
import profiling "../profiling"
import renderer "../renderer"
import serializer "../serializer"
import signals "../signals"
import tracy "../util/odin-tracy"
import vm "../vm"
import "core:math"
import "core:os"
import "core:strings"
import "core:time"


Workspace_Class := classes.Class_Info {
	name   = "Workspace",
	parent = &Service_Class,
}

Workspace_Streamed_Region :: struct {
	name:    string,
	payload: []u8,
}

Workspace :: struct {
	using service:               Service,
	streamed_regions:            [dynamic]Workspace_Streamed_Region,
	cell_streaming:              World_Cell_Streaming,
	rewind:                      Replication_Rewind_History,
	input_replays:               Replication_Replay_Registry,
	water_time:                  f64,
	cube_mesh:                   ^kineffi.KineFilamentMesh,
	surface_mesh:                ^kineffi.KineFilamentMesh,
	surface_textures:            [4]^kineffi.KineFilamentTex,
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
	dimension:                   enums.Dimension,
	global_wind:                 datatypes.Vector3,
	current_camera:              ^classes.Camera,
	finished_replicating:        ^signals.Signal,
	draw_items:                  [dynamic]kineffi.KineFilamentDrawItem,
	draw_version:                u64,
	draw_hash:                   u64,
	draw_hash_valid:             bool,
	enable_3d:                   bool,
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
	workspace.enable_3d = true
	workspace.cull_parts = true
	workspace.dimension = enums.Dimension.D3
	workspace.max_draw_distance = 0
	workspace.lod_distance = 0
	return &workspace.object
}

workspace_part_mesh :: proc(
	workspace: ^Workspace,
	filament: ^kineffi.KineFilamentContext,
	shape: enums.PartType,
) -> ^kineffi.KineFilamentMesh {
	slot := &workspace.cube_mesh
	data := #load("../assets/shapes/Block.glb")
	primitive: i32
	switch shape {
	case .Block:
	case .Ball:
		slot, data = &workspace.sphere_mesh, #load("../assets/shapes/Ball.glb")
	case .Cylinder:
		slot, primitive = &workspace.cylinder_mesh, kineffi.KINE_MESH_CYLINDER
	case .Wedge:
		slot, data = &workspace.wedge_mesh, #load("../assets/shapes/Wedge.glb")
	case .CornerWedge:
		slot, data = &workspace.corner_wedge_mesh, #load("../assets/shapes/Corner Wedge.glb")
	case .Cone:
		slot, data = &workspace.cone_mesh, #load("../assets/shapes/Cone.glb")
	case .Pyramid:
		slot, data = &workspace.pyramid_mesh, #load("../assets/shapes/Pyramid.glb")
	case .Truss:
		slot, data = &workspace.truss_mesh, #load("../assets/shapes/Truss.glb")
	case .Torus:
		slot, data = &workspace.torus_mesh, #load("../assets/shapes/Torus.glb")
	case .TriangleWedge:
		slot, data = &workspace.triangle_wedge_mesh, #load("../assets/shapes/Triangle Wedge.glb")
	case .Capsule:
		slot, data = &workspace.capsule_mesh, #load("../assets/shapes/Capsule.glb")
	}
	if slot^ == nil {
		tracy.ZoneNC("Workspace Primitive Mesh Load", 0xB48EAD)
		if primitive != 0 {
			slot^ = kineffi.Kine_Filament_CreateMesh(filament, primitive)
		} else {
			slot^ = load_mesh(filament, string(data))
		}
	}
	return slot^
}

workspace_water_mesh :: proc(
	workspace: ^Workspace,
	filament: ^kineffi.KineFilamentContext,
	size: datatypes.Vector3,
) -> ^kineffi.KineFilamentMesh {
	mesh: ^kineffi.KineFilamentMesh
	when ODIN_OS == .JS {
		if workspace.water_grid_mesh == nil {
			workspace.water_grid_mesh = kineffi.Kine_Filament_CreateMesh(
				filament,
				kineffi.KINE_MESH_WATER_GRID,
			)
		}
		mesh = workspace.water_grid_mesh
	} else {
		mesh = kineffi.Kine_Filament_GetWaterGrid(filament, f32(size.x), f32(size.z))
	}
	if mesh == nil {return workspace_part_mesh(workspace, filament, .Block)}
	return mesh
}

workspace_meshpart_mesh :: proc(
	part: ^classes.MeshPart,
	ctx: ^kineffi.KineFilamentContext,
) -> ^kineffi.KineFilamentMesh {
	if part == nil || ctx == nil {return nil}
	if part.editable_mesh_id != 0 {
		return workspace_editable_meshpart_mesh(part, ctx)
	}

	mesh_path := classes.MeshPart_Source_Path(part)
	if mesh_path == "" {
		classes.MeshPart_Release_Native_Mesh(part)
		return nil
	}

	if part.native_mesh != nil &&
	   part.native_context == ctx &&
	   !part.native_is_editable &&
	   part.native_mesh_id == mesh_path &&
	   part.native_mesh_index == part.mesh_index {
		return part.native_mesh
	}

	classes.MeshPart_Release_Native_Mesh(part)
	tracy.ZoneNC("Workspace Load MeshPart", 0xB48EAD)
	delete(part.native_mesh_id)
	part.native_mesh_id = strings.clone(mesh_path)
	part.native_mesh_index = part.mesh_index

	if data, found := assetstore.Resolve_Bytes(mesh_path); found && len(data) > 0 {


		if shared := classes.Shared_Mesh_Acquire(ctx, mesh_path, part.mesh_index, 0, true);
		   shared != nil {
			part.native_mesh = shared
			part.native_context = ctx
			return shared
		}

		hint := assetstore.Format_Hint(mesh_path)
		defer delete(hint)
		c_hint := hint == "" ? "glb" : strings.clone_to_cstring(hint)
		defer delete(c_hint)
		loaded := kineffi.Kine_Filament_CreateMeshFromMemoryIndexed(
			ctx,
			raw_data(data),
			uintptr(len(data)),
			c_hint,
			part.mesh_index,
		)
		if loaded != nil {
			if classes.Shared_Mesh_Can_Share(loaded) {
				loaded = classes.Shared_Mesh_Register(
					ctx,
					mesh_path,
					part.mesh_index,
					0,
					true,
					loaded,
				)
			}
			part.native_mesh = loaded
			part.native_context = ctx
		}
		return part.native_mesh
	}

	if assetstore.Is_Uri(mesh_path) {
		assetstore.Report_Missing_Asset(mesh_path, "Part mesh")
		return nil
	}

	resolved := assetstore.Resolve_Path(mesh_path)
	defer delete(resolved)
	if resolved == "" {return nil}


	revision: u64
	file, stat_err := os.stat(resolved, context.allocator)
	if stat_err == nil {
		defer os.file_info_delete(file, context.allocator)
		revision = u64(time.to_unix_nanoseconds(file.modification_time))
		revision ~= u64(file.size) * 0x9e3779b97f4a7c15
		revision ~= u64(file.inode) * 0xbf58476d1ce4e5b9
	}

	if shared := classes.Shared_Mesh_Acquire(ctx, resolved, part.mesh_index, revision, false);
	   shared != nil {
		part.native_mesh = shared
		part.native_context = ctx
		return shared
	}

	c_path := strings.clone_to_cstring(resolved)
	defer delete(c_path)
	loaded := kineffi.Kine_Filament_CreateMeshFromPathIndexed(ctx, c_path, part.mesh_index)
	if loaded != nil {
		if classes.Shared_Mesh_Can_Share(loaded) {
			loaded = classes.Shared_Mesh_Register(
				ctx,
				resolved,
				part.mesh_index,
				revision,
				false,
				loaded,
			)
		}
		part.native_mesh = loaded
		part.native_context = ctx
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
	classes.MeshPart_Release_Native_Mesh(part)

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
		append(&vertex_data, f32(position.x), f32(position.y), f32(position.z))
		append(&vertex_data, f32(corner.normal.x), f32(corner.normal.y), f32(corner.normal.z))
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
		if classes.Is_A_Class(child, &classes.Part_Class) ||
		   classes.Is_A_Class(child, &classes.Cloth_Class) ||
		   classes.Is_A_Class(child, &classes.SoftBody_Class) ||
		   classes.Is_A_Class(child, &classes.RopeConstraint_Class) ||
		   workspace_has_parts(child) {
			return true
		}
	}
	return false
}

workspace_prepare_3d :: proc(workspace: ^Workspace, renderer: ^classes.Renderer_Object) {
	tracy.ZoneNC("Workspace Prepare 3D", 0xB48EAD)
	z := profiling.Begin("Workspace Prepare 3D", 0xB48EAD)
	if workspace == nil || !workspace_has_parts(&workspace.object) {return}
	if renderer == nil || renderer.Filament == nil {return}

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
			x = f64(view[0]),
			y = f64(view[1]),
			z = f64(view[2]),
			r00 = f64(view[3]),
			r01 = f64(view[4]),
			r02 = f64(view[5]),
			r10 = f64(view[6]),
			r11 = f64(view[7]),
			r12 = f64(view[8]),
			r20 = f64(view[9]),
			r21 = f64(view[10]),
			r22 = f64(view[11]),
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
	offset: f64,
}

Workspace_Frustum :: struct {
	eye:    datatypes.Vector3,
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
		datatypes.Vec3_Subtract(datatypes.Vec3_Multiply(forward, f64(tan_half_v)), up),
		datatypes.Vec3_Add(datatypes.Vec3_Multiply(forward, f64(tan_half_v)), up),
		datatypes.Vec3_Subtract(datatypes.Vec3_Multiply(forward, f64(tan_half_x)), right),
		datatypes.Vec3_Add(datatypes.Vec3_Multiply(forward, f64(tan_half_x)), right),
	}

	frustum.eye = eye
	offsets := [6]f64{-f64(WORKSPACE_FRUSTUM_NEAR), f64(far), 0, 0, 0, 0}

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
	relative := datatypes.Vec3_Subtract(center, frustum.eye)
	for plane in frustum.planes {
		if datatypes.Vec3_Dot(plane.normal, relative) + f64(plane.offset) < f64(-radius) {
			return false
		}
	}
	return true
}


Workspace_Draw_Params :: struct {
	hidden_character:  ^classes.Object,
	replicator:        ^ReplicatorService,
	reflection_center: datatypes.Vector3,
	reflection_radius: f32,
	sun_caster_center: datatypes.Vector3,
	sun_caster_radius: f32,
	frustum:           ^Workspace_Frustum,
	eye:               datatypes.Vector3,
	max_distance:      f32,
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
	return f32(dx * dx + dy * dy + dz * dz)
}

workspace_set_3d_state :: proc(state: bool, workspace: ^Workspace) {
	registry := cast(^DataModel)workspace.data_model
	if registry != nil && registry.registry.classes.renderer != nil {
		r := registry.registry.classes.renderer
		r.RenderFilament = state
	}
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

		if params != nil && child == params.hidden_character {continue}

		if classes.Is_A_Class(child, &classes.Cloth_Class) {
			workspace_append_cloth(workspace, cast(^classes.Cloth)child, renderer, items, params)
		} else if classes.Is_A_Class(child, &classes.SoftBody_Class) {
			workspace_append_softbody(cast(^classes.SoftBody)child, renderer, items, params)
		} else if classes.Is_A_Class(child, &classes.RopeConstraint_Class) {
			rope := cast(^classes.RopeConstraint)child
			if item, ok := classes.RopeConstraint_Draw_Item(
				rope,
				&workspace.object,
				renderer.Filament,
			); ok {
				fabric, _ := materials.Lookup(.Fabric)
				item.tex = fabric.texture
				if params != nil {
					params.hash = workspace_hash_u64(params.hash, u64(uintptr(item.mesh)))
					params.hash = workspace_hash_u64(params.hash, u64(uintptr(item.tex)))
					params.hash = workspace_hash_u64(params.hash, rope.mesh_revision)
				}
				append(items, item)
			}
		} else if classes.Is_A_Class(child, &classes.Part_Class) {
			part := cast(^classes.Part)child
			mesh: ^kineffi.KineFilamentMesh
			is_meshpart := classes.Is_A_Class(child, &classes.MeshPart_Class)
			if part.transparency >= 1.0 ||
			   replication_part_awaiting_transform(params.replicator, part) {
				workspace_append_draw_items(workspace, child, renderer, items, params)
				continue
			}

			if is_meshpart {
				mesh = workspace_meshpart_mesh(cast(^classes.MeshPart)child, renderer.Filament)
			}
			cframe := part.cframe
			size := part.size
			render_size := datatypes.Vector3{size.x * 0.5, size.y * 0.5, size.z * 0.5}
			special := classes.SpecialMesh_Find(child)
			special_tex: ^kineffi.KineFilamentTex
			shape := part.shape
			if special != nil && !is_meshpart {
				mesh, special_tex = classes.SpecialMesh_Geometry(special, renderer.Filament)
				cframe = datatypes.CFrame_Add_Vector3(
					cframe,
					datatypes.CFrame_VectorToWorldSpace(cframe, special.offset),
				)
				switch special.mesh_type {
				case .FileMesh:
					render_size = special.scale
				case .Sphere:
					shape = .Ball
				case .Cylinder:
					shape = .Cylinder
				case .Wedge, .RightAngleRamp:
					shape = .Wedge
				case .CornerWedge:
					shape = .CornerWedge
				case .Pyramid:
					shape = .Pyramid
				case .Head:
					shape = .Ball
				case .Brick, .Torso, .Prism, .ParallelRamp:
					shape = .Block
				}
				if special.mesh_type != .FileMesh {
					size = {
						size.x * special.scale.x,
						size.y * special.scale.y,
						size.z * special.scale.z,
					}
					render_size = datatypes.Vec3_Multiply(size, 0.5)
				}
			}


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
				mesh = workspace_water_mesh(workspace, renderer.Filament, size)
				render_size.x = size.x
				render_size.y = size.y
				render_size.z = size.z
			}

			center := datatypes.Vector3{cframe.x, cframe.y, cframe.z}
			radius := 0.5 * datatypes.Vec3_Magnitude(size) + f64(WORKSPACE_CULL_MARGIN)
			if (is_meshpart || special != nil) && mesh != nil {


				local_center, half_extent: [3]f32
				if kineffi.Kine_Filament_GetMeshBounds(mesh, &local_center[0], &half_extent[0]) {
					center = datatypes.CFrame_PointToWorldSpace(
						cframe,
						{
							f64(local_center[0]) * render_size.x,
							f64(local_center[1]) * render_size.y,
							f64(local_center[2]) * render_size.z,
						},
					)
					radius =
						datatypes.Vec3_Magnitude(
							datatypes.Vector3 {
								f64(half_extent[0]) * render_size.x,
								f64(half_extent[1]) * render_size.y,
								f64(half_extent[2]) * render_size.z,
							},
						) +
						f64(WORKSPACE_CULL_MARGIN)
				}
			}
			variant := classes.MaterialVariant_Find(child.signal_registry, part.material_variant)
			if variant != nil {
				radius += f64(abs(variant.height_scale) + variant.displacement_bounds)
			}

			visible := true
			distance_sq: f32
			if params != nil {
				distance_sq = workspace_distance_squared(center, params.eye)
				draw_distance := f64(params.max_distance) + radius
				within_draw_distance :=
					params.max_distance <= 0 || f64(distance_sq) <= draw_distance * draw_distance
				visible = within_draw_distance
				if visible &&
				   params.frustum != nil &&
				   !Workspace_Frustum_Contains_Sphere(params.frustum, center, f32(radius)) {
					visible = false
				}


				if !visible && params.reflection_radius > 0 {
					capture_radius := f64(params.reflection_radius) + radius
					visible =
						f64(workspace_distance_squared(center, params.reflection_center)) <=
						capture_radius * capture_radius
				}
				if !visible &&
				   within_draw_distance &&
				   part.castshadow &&
				   params.sun_caster_radius > 0 {
					caster_radius := f64(params.sun_caster_radius) + radius
					visible =
						f64(workspace_distance_squared(center, params.sun_caster_center)) <=
						caster_radius * caster_radius
				}
			}

			if visible {
				if mesh == nil && material_kind != kineffi.KINE_MAT_WATER {
					mesh = workspace_part_mesh(workspace, renderer.Filament, shape)

					if shape == .Cylinder && mesh != nil {render_size = size}
				}

				if params != nil &&
				   params.lod_mesh != nil &&
				   params.lod_distance_sq > 0 &&
				   !is_meshpart &&
				   special == nil &&
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

				if special_tex !=
				   nil {mesh_texture = special_tex; draw_texture = special_tex; param3 = 1}


				when ODIN_OS != .JS {
					if material_kind == kineffi.KINE_MAT_DEFAULT &&
					   render_material.texture != nil &&
					   mesh_texture == nil &&
					   !is_meshpart {
						param3 = -0.25
					}
				} else {
					if material_kind == kineffi.KINE_MAT_DEFAULT &&
					   render_material.texture != nil &&
					   mesh_texture == nil {
						param3 = f32(max(1.0, max(size.x, max(size.y, size.z)) / 4.0))
					}
				}

				shader: ^kineffi.KineFilamentShader
				shader_revision: u64
				if variant != nil && renderer.Filament != nil {
					classes.MaterialVariant_Prepare(variant, renderer.Filament)
					shader, shader_revision = variant.filament_shader, variant.revision
				}
				item := kineffi.KineFilamentDrawItem {
					shader        = shader,
					mesh          = mesh,
					tex           = draw_texture,
					transform     = {
						f32(cframe.r00 * render_size.x),
						f32(cframe.r01 * render_size.y),
						f32(cframe.r02 * render_size.z),
						f32(cframe.x),
						f32(cframe.r10 * render_size.x),
						f32(cframe.r11 * render_size.y),
						f32(cframe.r12 * render_size.z),
						f32(cframe.y),
						f32(cframe.r20 * render_size.x),
						f32(cframe.r21 * render_size.y),
						f32(cframe.r22 * render_size.z),
						f32(cframe.z),
						0,
						0,
						0,
						1,
					},
					r             = part.color.R,
					g             = part.color.G,
					b             = part.color.B,
					param1        = param1,
					param2        = param2,
					param3        = param3,
					transmission  = transmission,
					materialKind  = material_kind,
					flags         = workspace_part_flags(
						part,
					) | kineffi.KINE_FILAMENT_DRAW_WORLD_POSITION,
					worldPosition = {cframe.x, cframe.y, cframe.z},
				}


				if special != nil {
					item.r *= f32(special.vertex_color.x)
					item.g *= f32(special.vertex_color.y)
					item.b *= f32(special.vertex_color.z)
				}
				if params != nil {
					params.hash = workspace_hash_u64(params.hash, u64(uintptr(shader)))
					params.hash = workspace_hash_u64(params.hash, shader_revision)
					params.hash = workspace_hash_u64(params.hash, u64(uintptr(mesh)))
					params.hash = workspace_hash_u64(params.hash, u64(uintptr(draw_texture)))
					for i in 0 ..< 16 {
						params.hash = workspace_hash_f32(params.hash, item.transform[i])
					}
					for v in item.worldPosition {params.hash = workspace_hash_u64(params.hash, transmute(u64)v)}
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
				if !is_meshpart && special == nil && shape == .Block &&
				   material_kind == kineffi.KINE_MAT_DEFAULT && part.transparency == 0 {
					workspace_append_part_surfaces(workspace, renderer.Filament, part, item, items, params)
				}
			}
		}

		workspace_append_draw_items(workspace, child, renderer, items, params)
	}
}

workspace_clear_draw_items :: proc(workspace: ^Workspace, renderer: ^classes.Renderer_Object) {
	if !workspace.draw_hash_valid && len(workspace.draw_items) == 0 {return}
	clear(&workspace.draw_items)
	workspace.draw_version += 1
	workspace.draw_hash_valid = false
	if renderer != nil && renderer.Filament != nil {
		_ = kineffi.Kine_Filament_DrawMeshListVersioned(
			renderer.Filament,
			nil,
			0,
			WORKSPACE_STREAM_ID,
			workspace.draw_version,
		)
	}
}

workspace_render :: proc(object: ^classes.Object, ctx: ^classes.Class_Step_Context) {
	workspace := cast(^Workspace)object
	if ctx == nil || ctx.renderer == nil {return}
	ctx.renderer.RenderFilament = workspace.dimension == .D3 && workspace.enable_3d
	if !ctx.renderer.RenderFilament {return}

	tracy.ZoneNC("Workspace Render 3D", 0xB48EAD)
	z := profiling.Begin("Workspace Render 3D", 0xB48EAD)
	if ctx.renderer.Filament == nil {return}
	if !workspace_has_parts(object) {
		workspace_clear_draw_items(workspace, ctx.renderer)
		return
	}

	{
		tracy.ZoneNC("WS Mesh Setup", 0x9CDCFE)
		setup := profiling.Begin("WS Mesh Setup", 0x9CDCFE)
		materials.init(ctx.renderer)
	}

	{
		tc := tracy.ZoneNC("WS Collect Draw Items", 0xB48EAD)
		collect := profiling.Begin("WS Collect Draw Items", 0xB48EAD)

		items := &workspace.draw_items
		clear(items)

		params := Workspace_Draw_Params {
			hash       = 1469598103934665603,
			replicator = cast(^ReplicatorService)Service_Get_Service(
				&workspace.service,
				"ReplicatorService",
			),
		}
		probe_center: [3]f32
		if kineffi.Kine_Filament_GetReflectionProbeRegion(
			ctx.renderer.Filament,
			&probe_center[0],
			&params.reflection_radius,
		) {
			params.reflection_center = {
				f64(probe_center[0]),
				f64(probe_center[1]),
				f64(probe_center[2]),
			}
		}
		frustum: Workspace_Frustum

		if camera := cast(^classes.Camera)ctx.renderer.ActiveCamera; camera != nil {
			params.eye = datatypes.Vector3{camera.CFrame.x, camera.CFrame.y, camera.CFrame.z}
			lighting := cast(^Lighting)Service_Get_Service(&workspace.service, "Lighting")
			if lighting != nil && lighting.sun_rays_distance > 0 {

				half := f64(lighting.sun_rays_distance) * 1.05
				direction := lighting_effective_sun_direction(lighting)
				params.sun_caster_center = datatypes.Vec3_Add(
					params.eye,
					datatypes.Vec3_Multiply(direction, 24),
				)
				params.sun_caster_radius = f32(
					math.sqrt(2 * half * half + (half + 25) * (half + 25)),
				)
			}
			if camera.CameraType == .FirstPerson {
				players := cast(^Players)Service_Get_Service(&workspace.service, "Players")
				if players != nil && players.local_player != nil {
					character := players.local_player.character
					if character != nil &&
					   !character.destroyed &&
					   camera.CameraSubject == &character.object {
						params.hidden_character = &character.object
					}
				}
			}

			if workspace.lod_distance > 0 {
				params.lod_distance_sq = workspace.lod_distance * workspace.lod_distance
				params.lod_mesh = workspace_part_mesh(workspace, ctx.renderer.Filament, .Block)
			}

			params.max_distance = workspace.max_draw_distance


			xr_active := VR_Service_Enabled(&workspace.service)
			if workspace.cull_parts && !xr_active {
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

		workspace_set_3d_state(workspace.enable_3d, workspace)
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
			workspace_clear_draw_items(workspace, ctx.renderer)
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


workspace_stream_error :: proc(L: ^vm.State, err: ^serializer.Error) -> i32 {
	message := serializer.Error_String(err^)
	owned := strings.clone(message, context.temp_allocator)
	delete(message)
	serializer.Error_Delete(err)
	return vm.RaiseError(L, owned)
}

workspace_stream_unload :: proc(L: ^vm.State, workspace: ^Workspace) -> i32 {
	if workspace.object.signal_registry == nil ||
	   workspace.object.signal_registry.mode == .Client {
		return vm.RaiseError(L, "only the server may unload world regions")
	}
	if vm.ThreadIsParallel(
		L,
	) {return vm.RaiseError(L, "region streaming is not allowed in parallel Luau")}
	region := classes.Object_From_Argument(L, 2)
	if region == nil ||
	   region.destroyed ||
	   !classes.Is_A(region, "Model") ||
	   region.parent != &workspace.object {
		return vm.RaiseError(L, "UnloadRegion expects a direct child Model of Workspace")
	}
	if region.name == "" {return vm.RaiseError(L, "region Model must have a name")}
	for existing in workspace.streamed_regions {
		if existing.name == region.name {return vm.RaiseError(L, "region already unloaded")}
	}
	data, err := serializer.Serialize(workspace.signal_registry, L, region)
	if !serializer.Error_Is_None(err) {
		delete(data)
		return workspace_stream_error(L, &err)
	}
	if len(data) == 0 || len(data) > 128 * 1024 * 1024 {
		delete(data)
		return vm.RaiseError(L, "region snapshot must be between 1 byte and 128 MiB")
	}
	append(
		&workspace.streamed_regions,
		Workspace_Streamed_Region{name = strings.clone(region.name), payload = data},
	)
	classes.Destroy_Hierarchy(region)
	vm.PushBoolean(L, true)
	return 1
}

workspace_stream_load :: proc(L: ^vm.State, workspace: ^Workspace) -> i32 {
	if workspace.object.signal_registry == nil ||
	   workspace.object.signal_registry.mode == .Client {
		return vm.RaiseError(L, "only the server may load world regions")
	}
	if vm.ThreadIsParallel(
		L,
	) {return vm.RaiseError(L, "region streaming is not allowed in parallel Luau")}
	name := vm.ArgString(L, 2)
	index := -1
	for region, i in workspace.streamed_regions {
		if region.name == name {index = i; break}
	}
	if index < 0 {return vm.RaiseError(L, "no unloaded region with that name")}
	for child in workspace.object.children {
		if child != nil && !child.destroyed && child.name == name {
			return vm.RaiseError(L, "Workspace already has a child with that region name")
		}
	}
	region := &workspace.streamed_regions[index]

	model, err := serializer.Deserialize(
		workspace.signal_registry,
		L,
		nil,
		region.payload,
		fresh_unique_ids = true,
	)
	if !serializer.Error_Is_None(err) {return workspace_stream_error(L, &err)}
	if model == nil || !classes.Is_A(model, "Model") {
		if model != nil {classes.Destroy_Hierarchy(model)}
		return vm.RaiseError(L, "region snapshot is not a Model")
	}
	classes.Set_Parent(model, &workspace.object)
	classes.Push_Object(L, model)
	delete(region.name)
	delete(region.payload)
	ordered_remove(&workspace.streamed_regions, index)
	return 1
}

workspace_stream_list :: proc(L: ^vm.State, workspace: ^Workspace) -> i32 {
	vm.NewTable(L, len(workspace.streamed_regions))
	for region, i in workspace.streamed_regions {
		vm.PushString(L, region.name)
		vm.SetArrayValue(L, -2, i + 1)
	}
	return 1
}

workspace_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	workspace := cast(^Workspace)object
	switch key {
	case "CurrentCamera":
		classes.Push_Object(L, cast(^classes.Object)workspace.current_camera)
	case "Terrain":
		classes.Push_Object(L, Service_Get_Service(&workspace.service, "Terrain"))
	case "Gravity":
		physics := cast(^Physics)Service_Get_Service(&workspace.service, "Physics")
		vm.PushNumber(L, f64(physics.gravity) if physics != nil else 196.2)
	case "FluidForces":
		aerodynamics := cast(^Aerodynamics)Service_Get_Service(&workspace.service, "Aerodynamics")
		vm.PushBoolean(L, aerodynamics != nil && aerodynamics.enabled)
	case "SimulatePhysics", "AutoSimulate":
		vm.PushBoolean(L, workspace.simulate_physics)
	case "Dimension":
		if enum_registry == nil {return false}
		_ = enums.Push_Item_By_Value(L, enum_registry, "Dimension", i64(workspace.dimension))
	case "Enable3dRendering":
		vm.PushBoolean(L, workspace.enable_3d)
	case "GlobalWind":
		datatypes.Push_Vector3(L, workspace.global_wind)
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
	     "GetPartBoundsInBox",
	     "GetPartBoundsInRadius",
	     "GetPartsInPart",
	     "GetNumAwakeParts",
	     "GetPhysicsThrottling",
	     "GetRealPhysicsFPS",
	     "Disable3D",
	     "Enable3D",
	     "PGSIsEnabled",
	     "UnloadRegion",
	     "LoadRegion",
	     "GetUnloadedRegions",
	     "ConfigureCellStreaming",
	     "RegisterWorldCell",
	     "SetCellStreamingFocus",
	     "GetCellStreamingStats",
	     "GetWorldCells",
	     "RetryWorldCell",
	     "UnregisterWorldCell",
	     "ConfigureRewind",
	     "GetHistoricalTransform",
	     "RaycastRewind",
	     "GetRewindStats",
	     "GetRewindTime",
	     "CreateInputReplay",
	     "PushReplayInput",
	     "ReconcileInputReplay",
	     "GetInputReplayState",
	     "DestroyInputReplay":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

workspace_render_state :: proc(object: ^classes.Object, key: string) -> ([3]f64, bool) {
	switch key {
	case "Gravity":
		return {}, true
	case:
		return {}, false
	}
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
	case "Gravity":
		physics := cast(^Physics)Service_Get_Service(&workspace.service, "Physics")
		if physics != nil {
			Physics_Set_Gravity(physics, f32(vm.ArgNumber(L, value_index)))
		}
	case "FluidForces":
		aerodynamics := cast(^Aerodynamics)Service_Get_Service(&workspace.service, "Aerodynamics")
		if aerodynamics != nil {
			aerodynamics.enabled = vm.ArgBoolean(L, value_index)
		}
	case "SimulatePhysics", "AutoSimulate":
		simulate := vm.ArgBoolean(L, value_index)
		if workspace.simulate_physics && !simulate {
			if descriptor := classes.Find_Class(workspace.signal_registry, "Cloth");
			   descriptor != nil {
				for object in descriptor.instances {
					cloth := cast(^classes.Cloth)object
					if cloth.pose_source == .Simulation {cloth.pose_source = .Preview}
				}
			}
		}
		workspace.simulate_physics = simulate
	case "Enable3dRendering":
		workspace.enable_3d = vm.ArgBoolean(L, value_index)
	case "Dimension":
		if enum_registry == nil {return false}
		item := enums.Arg_Item(L, value_index, enum_registry, "Dimension")
		workspace.dimension = enums.Dimension(item.value)
	case "GlobalWind":
		wind := datatypes.Arg_Vector3(L, value_index)
		if !physics_finite_f32(f32(wind.x)) ||
		   !physics_finite_f32(f32(wind.y)) ||
		   !physics_finite_f32(f32(wind.z)) {
			_ = vm.RaiseError(L, "Workspace.GlobalWind must be finite")
			return true
		}
		workspace.global_wind = wind
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
	context = tracy.DefaultContext()
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
	if count, handled := Replication_Replay_Namecall(&workspace.input_replays, L, method);
	   handled {return count, true}

	if count, handled := World_Cells_Namecall(workspace, L, datatype_registry, method);
	   handled {return count, true}
	switch method {
	case "ConfigureRewind",
	     "GetHistoricalTransform",
	     "RaycastRewind",
	     "GetRewindStats",
	     "GetRewindTime":
		replicator := cast(^ReplicatorService)Service_Get_Service(
			&workspace.service,
			"ReplicatorService",
		)
		return Replication_Rewind_Namecall(
			&workspace.rewind,
			replicator,
			L,
			datatype_registry,
			method,
		)
	}

	physics: ^Physics
	if vm.ThreadIsParallel(L) {
		if model := workspace.service.data_model; model != nil {
			if descriptor := Find_Service(model.registry, "Physics"); descriptor != nil {
				physics = cast(^Physics)descriptor.object
			}
		}
	} else {
		physics = workspace_physics(workspace)
	}
	switch method {
	case "UnloadRegion":
		return workspace_stream_unload(L, workspace), true
	case "LoadRegion":
		return workspace_stream_load(L, workspace), true
	case "GetUnloadedRegions":
		return workspace_stream_list(L, workspace), true
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
			synchronize = !vm.ThreadIsParallel(L),
		)
		if !hit {vm.PushNil(L)} else {datatypes.Push_RaycastResult(L, datatype_registry, result)}
		return 1, true
	case "GetPartBoundsInBox", "GetPartBoundsInRadius":
		return workspace_get_part_bounds(
				L,
				object,
				datatype_registry,
				method == "GetPartBoundsInBox",
			),
			true
	case "GetPartsInPart":
		return workspace_get_parts_in_part(L, object, physics, datatype_registry), true
	case "JoinToOutsiders", "UnjoinFromOutsiders":
		return workspace_update_outsider_welds(
				L,
				object,
				physics,
				enum_registry,
				method == "JoinToOutsiders",
			),
			true
	case "Disable3D":
		workspace.enable_3d = false
		return 1, true
	case "Enable3D":
		workspace.enable_3d = true
		return 1, true
	case "GetNumAwakeParts":
		vm.PushNumber(L, f64(Physics_Get_Num_Awake_Parts(physics)))
		return 1, true
	case "Dimension":
		if enum_registry == nil {return 0, false}
		_ = enums.Push_Item_By_Value(L, enum_registry, "Dimension", i64(workspace.dimension))
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
		width, height: i32
		if workspace.data_model != nil && workspace.data_model.registry != nil {
			r := workspace.data_model.registry.classes.renderer
			if r != nil && r.Window != nil {
				_ = platform.GetWindowSizeInPixels(r.Window, &width, &height)
			}
		}
		vec2 := datatypes.Vector2 {
			max(f32(width) - platform.UI_Safe_Left - platform.UI_Safe_Right, 0) /
			platform.UI_Scale,
			max(f32(height) - platform.UI_Safe_Top - platform.UI_Safe_Bottom, 0) /
			platform.UI_Scale,
		}
		datatypes.Push_Vector2(L, datatype_registry, vec2)
		return 1, true
	}
	return 0, false
}

workspace_parallel_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "Terrain":
		workspace := cast(^Workspace)object
		if model := workspace.service.data_model; model != nil {
			if descriptor := Find_Service(model.registry, "Terrain");
			   descriptor != nil && Service_Access_Allowed(L, descriptor) {
				classes.Push_Object(L, descriptor.object)
				return true
			}
		}
		vm.PushNil(L)
		return true
	case "CurrentCamera",
	     "SimulatePhysics",
	     "AutoSimulate",
	     "GlobalWind",
	     "Dimension",
	     "DistributedGameTime",
	     "Enable3dRendering",
	     "FallenPartsDestroyHeight",
	     "FallHeightEnabled",
	     "RenderCulling",
	     "MaxDrawDistance",
	     "LODDistance",
	     "Raycast",
	     "GetPartBoundsInBox",
	     "GetPartBoundsInRadius",
	     "GetPartsInPart":
		return workspace_get(L, object, d, e, key)
	}
	return false
}

workspace_parallel_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	d: ^datatypes.Registry,
	e: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	switch method {
	case "Raycast", "GetPartBoundsInBox", "GetPartBoundsInRadius", "GetPartsInPart":
		return workspace_namecall(L, object, d, e, method)
	}
	return 0, false
}

workspace_existing_service :: proc(workspace: ^Workspace, name: string) -> ^classes.Object {
	if workspace == nil ||
	   workspace.data_model == nil ||
	   workspace.data_model.registry == nil {return nil}
	descriptor := Find_Service(workspace.data_model.registry, name)
	if descriptor == nil {return nil}
	return descriptor.object
}

workspace_update :: proc(object: ^classes.Object, ctx: ^classes.Class_Step_Context) {
	workspace := cast(^Workspace)object
	if ctx == nil {return}
	if ctx.renderer == nil ||
	   ctx.renderer.Filament == nil ||
	   !workspace.enable_3d ||
	   workspace.dimension != .D3 {
		terrain := cast(^Terrain)workspace_existing_service(workspace, "Terrain")
		if terrain != nil {Terrain_Process_Background(terrain)}
	}
	World_Cells_Step(workspace, ctx.L)
	if workspace.rewind.enabled {
		replicator := cast(^ReplicatorService)workspace_existing_service(
			workspace,
			"ReplicatorService",
		)
		if replicator !=
		   nil {Replication_Rewind_Capture(&workspace.rewind, replicator, f64(replicator.clock))}
	}
}

workspace_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	workspace := cast(^Workspace)object

	World_Cells_Destroy(workspace)
	Replication_Rewind_Destroy(&workspace.rewind)
	Replication_Replay_Destroy_All(&workspace.input_replays)

	materials.shutdown(renderer)

	if renderer != nil && renderer.Filament != nil {
		meshes := [?]^kineffi.KineFilamentMesh {
			workspace.cube_mesh,
			workspace.surface_mesh,
			workspace.sphere_mesh,
			workspace.cylinder_mesh,
			workspace.cone_mesh,
			workspace.torus_mesh,
			workspace.pyramid_mesh,
			workspace.truss_mesh,
			workspace.wedge_mesh,
			workspace.triangle_wedge_mesh,
			workspace.corner_wedge_mesh,
			workspace.capsule_mesh,
			workspace.water_grid_mesh,
		}
		for texture in workspace.surface_textures {
			if texture != nil {_ = kineffi.Kine_Filament_DestroyTex(renderer.Filament, texture)}
		}
		for mesh in meshes {
			if mesh != nil {_ = kineffi.Kine_Filament_DestroyMesh(renderer.Filament, mesh)}
		}
	}
	delete(workspace.draw_items)
	for region in workspace.streamed_regions {
		delete(region.name)
		delete(region.payload)
	}
	delete(workspace.streamed_regions)
	classes.Object_Destroy(object)
	free(workspace)
}

Register_Workspace_Class :: proc(registry: ^classes.Registry) {
	classes.ViewportFrame_MeshPart_Provider = workspace_meshpart_mesh
	classes.Highlight_Part_Mesh_Provider = proc(
		data_model: rawptr,
		ctx: ^kineffi.KineFilamentContext,
		shape: enums.PartType,
	) -> ^kineffi.KineFilamentMesh {
		workspace := cast(^Workspace)DataModel_Get_Service(cast(^DataModel)data_model, "Workspace")
		if workspace == nil {return nil}
		return workspace_part_mesh(workspace, ctx, shape)
	}
	classes.Register_Class(
		registry,
		&Workspace_Class,
		workspace_construct,
		workspace_destroy,
		creatable = false,
		get = workspace_get,
		set = workspace_set,
		render_state = workspace_render_state,
		namecall = workspace_namecall,
		_step = workspace_update,
		_step_phase = .Update,
		parallel_get = workspace_parallel_get,
		parallel_namecall = workspace_parallel_namecall,
		properties = []string {
			"CurrentCamera",
			"Gravity",
			"SimulatePhysics",
			"GlobalWind",
			"FallenPartsDestroyHeight",
			"FallHeightEnabled",
			"DistributedGameTime",
			"FluidForces",
			"Dimension",
			"RenderCulling",
			"MaxDrawDistance",
			"Enable3dRendering",
			"LODDistance",
			"FinishedReplicating",
		},
		methods = []string {
			"Raycast",
			"GetPartBoundsInBox",
			"GetPartBoundsInRadius",
			"GetPartsInPart",
			"JoinToOutsiders",
			"UnjoinFromOutsiders",
			"GetNumAwakeParts",
			"GetPhysicsThrottling",
			"Disable3D",
			"Enable3D",
			"GetRealPhysicsFPS",
			"PGSIsEnabled",
			"UnloadRegion",
			"LoadRegion",
			"GetUnloadedRegions",
			"ConfigureCellStreaming",
			"RegisterWorldCell",
			"SetCellStreamingFocus",
			"GetCellStreamingStats",
			"GetWorldCells",
			"RetryWorldCell",
			"UnregisterWorldCell",
			"ConfigureRewind",
			"GetHistoricalTransform",
			"RaycastRewind",
			"GetRewindStats",
			"GetRewindTime",
			"CreateInputReplay",
			"PushReplayInput",
			"ReconcileInputReplay",
			"GetInputReplayState",
			"DestroyInputReplay",
		},
		events = []string{"FinishedReplicating"},
		exports = []classes.Class_Export{{name = "Raycast", handler = workspace_kne_raycast}},
	)
}
