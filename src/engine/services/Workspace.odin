package services

// wire:service global="workspace"

import kineffi "../bindings"
import assetstore "../assetstore"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import materials "../material"
import profiling "../profiling"
import tracy "../util/odin-tracy"
import vm "../vm"
import "core:strings"

Workspace_Class := classes.Class_Info {
	name   = "Workspace",
	parent = &Service_Class,
}

Workspace :: struct {
	using service:               Service,

	// meshes
	cube_mesh:                   ^kineffi.KineFilamentMesh,
	// Dense subdivided top-face grid; the water material displaces these
	// vertices on the GPU with Gerstner waves (KINE_MESH_WATER_GRID).
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
	current_camera:              ^classes.Camera,
}

load_mesh :: proc(
	ctx: ^kineffi.KineFilamentContext,
	data: string,
	format_hint: cstring = "glb",
) -> ^kineffi.KineFilamentMesh {
	return kineffi.Kine_Filament_CreateMeshFromMemory(
		ctx,
		raw_data(data),
		uintptr(len(data)),
		format_hint,
	)
}

workspace_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	workspace := new(Workspace)
	workspace.service = Service_Init(&Workspace_Class, "Workspace", data_model)
	workspace.fallen_parts_destroy_height = -500
	workspace.fall_height_enabled = true
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

// Water parts render on a dense subdivided grid so the water material can
// displace real geometry with Gerstner waves; the Block.glb cube only has 4
// vertices per face, far too few for meaningful waves.
workspace_water_mesh :: proc(
	workspace: ^Workspace,
) -> ^kineffi.KineFilamentMesh {
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
	   !part.native_is_editable {
		return part.native_mesh
	}
	if part.native_mesh != nil && part.native_context != nil {
		_ = kineffi.Kine_Filament_DestroyMesh(part.native_context, part.native_mesh)
		part.native_mesh = nil
		part.native_context = nil
	}
	// A saved map carries its meshes inside the .kine, so try the embedded bytes
	// first. Assimp needs a format hint to pick an importer for in-memory data,
	// and the authored path recorded in the asset table is what supplies it.
	if data, found := assetstore.Resolve_Bytes(part.mesh_id); found && len(data) > 0 {
		hint := assetstore.Format_Hint(part.mesh_id)
		defer delete(hint)
		// An author can name a file without an extension, in which case there is
		// no hint to pass and the importer default is the only thing to go on.
		c_hint := hint == "" ? "glb" : strings.clone_to_cstring(hint)
		defer delete(c_hint)
		part.native_mesh = kineffi.Kine_Filament_CreateMeshFromMemory(
			ctx,
			raw_data(data),
			uintptr(len(data)),
			c_hint,
		)
		if part.native_mesh != nil {
			part.native_context = ctx
			part.native_is_editable = false
		}
		return part.native_mesh
	}

	// Otherwise the value is a plain path, which Resolve_Path passes through
	// after stripping any "file://" prefix. Reaching here with an embedded
	// reference means the store never received those bytes, so say so instead of
	// letting the load fail into a primitive box with no explanation.
	if assetstore.Is_Uri(part.mesh_id) {
		assetstore.Report_Missing_Asset(part.mesh_id, "Part mesh")
	}
	resolved := assetstore.Resolve_Path(part.mesh_id)
	defer delete(resolved)
	c_path := strings.clone_to_cstring(resolved)
	defer delete(c_path)
	part.native_mesh = kineffi.Kine_Filament_CreateMeshFromPath(ctx, c_path)
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

	vertex_count := min(len(corners), 65532)
	if vertex_count == 0 {
		part.editable_mesh_version = mesh.version
		return nil
	}

	center := classes.EditableMesh_Get_Center(mesh)
	bounds := classes.EditableMesh_Get_Size(mesh)
	scale := editable_mesh_render_scale(bounds)

	vertex_data := make([dynamic]f32, 0, vertex_count * 8)
	defer delete(vertex_data)
	indices := make([dynamic]u16, 0, vertex_count)
	defer delete(indices)

	for corner_index in 0 ..< vertex_count {
		corner := corners[corner_index]
		position := datatypes.Vector3{
			(corner.position.x - center.x) * scale.x,
			(corner.position.y - center.y) * scale.y,
			(corner.position.z - center.z) * scale.z,
		}
		append(&indices, u16(corner_index))
		append(&vertex_data, position.x, position.y, position.z)
		append(&vertex_data, corner.normal.x, corner.normal.y, corner.normal.z)
		append(&vertex_data, corner.uv.X, corner.uv.Y)
	}

	part.native_mesh = kineffi.Kine_Filament_CreateCustomMesh(
		ctx,
		cast(^f32)raw_data(vertex_data),
		i32(len(vertex_data)),
		cast(^u16)raw_data(indices),
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
		if child == nil || child.destroyed {continue}
		if classes.Is_A(child, "Part") || workspace_has_parts(child) {return true}
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

workspace_append_draw_items :: proc(
	workspace: ^Workspace,
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
	items: ^[dynamic]kineffi.KineFilamentDrawItem,
) {
	for child in object.children {
		if child == nil || child.destroyed {continue}

		if classes.Is_A(child, "Part") {
			part := cast(^classes.Part)child
			mesh := workspace_part_mesh(workspace, part.shape)
			if part.transparency >= 1.0 {
				workspace_append_draw_items(workspace, child, renderer, items)
				continue
			}

			if classes.Is_A(child, "MeshPart") {
				mesh = workspace_meshpart_mesh(cast(^classes.MeshPart)child, renderer.Filament)
				if mesh == nil {
					mesh = workspace_part_mesh(workspace, part.shape)
				}
			}
			cframe := part.cframe
			size := part.size
			render_size := datatypes.Vector3{size.x * 0.5, size.y * 0.5, size.z * 0.5}

			render_material := materials.Get(part.material)
			material_kind, param1, param2, param3, transmission := materials.Draw_Parameters(
				render_material,
			)

			if material_kind == kineffi.KINE_MAT_WATER {
				// Vertex waves only make sense on the water's top surface, so a
				// water Part swaps its shape mesh for a flat grid whose surface
				// sits at mesh y = +0.5.
				//
				// That grid is authored 1 unit wide in X/Z, while every other
				// part mesh (Block.glb and friends) is a 2-unit-wide cube. The
				// shared render_size is half the part size, which is correct for
				// the 2-unit meshes but would shrink the water surface to half
				// the part's footprint and drop it to mid-height. Scaling by the
				// full size lines the 0.5-unit offsets back up: X/Z become
				// size*0.5 = the part's half-extent, and y = +0.5*size.y is the
				// top face.
				mesh = workspace_water_mesh(workspace)
				render_size.x = size.x
				render_size.y = size.y
				render_size.z = size.z
			}

			if material_kind == kineffi.KINE_MAT_DEFAULT && render_material.texture != nil {
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

			append(
				items,
				kineffi.KineFilamentDrawItem {
					mesh = mesh,
					tex = render_material.texture,
					transform = {
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
					r = part.color.R,
					g = part.color.G,
					b = part.color.B,
					param1 = param1,
					param2 = param2,
					param3 = param3,
					transmission = transmission,
					materialKind = material_kind,
					flags = kineffi.KINE_FILAMENT_DRAW_CULLING,
				},
			)
		}

		workspace_append_draw_items(workspace, child, renderer, items)
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

	// The collect and submit halves are timed separately on purpose. This runs for
	// every part in the tree on every frame, so "the frame is slow" is never enough
	// to act on: the question is whether the cost is our per-part CPU work walking
	// the tree, or Filament consuming the submitted list. Those have completely
	// different fixes, and they are indistinguishable inside a single zone.
	//
	// The zone value is the item count, so the capture also gives a per-part cost and
	// reveals whether the frame time scales with the scene.
	{
		tc := tracy.ZoneNC("WS Collect Draw Items", 0xB48EAD)
		collect := profiling.Begin("WS Collect Draw Items", 0xB48EAD)
		items: [dynamic]kineffi.KineFilamentDrawItem
		workspace_append_draw_items(workspace, object, ctx.renderer, &items)
		tracy.ZoneValue(tc, u64(len(items)))

		if len(items) > 0 {
			ts := tracy.ZoneNC("WS Filament Submit", 0xC678DD)
			submit := profiling.Begin("WS Filament Submit", 0xC678DD)
			tracy.ZoneValue(ts, u64(len(items)))
			_ = kineffi.Kine_Filament_DrawMeshList(
				ctx.renderer.Filament,
				raw_data(items),
				u32(len(items)),
			)
		}
		delete(items)
	}
}

workspace_physics :: proc(workspace: ^Workspace) -> ^Physics {
	object := Service_Get_Service(&workspace.service, "Physics")
	if object == nil {return nil}
	return cast(^Physics)object
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
	case "Gravity":
		vm.PushNumber(L, physics == nil ? 196.2 : f64(physics.gravity))
	case "FallenPartsDestroyHeight":
		vm.PushNumber(L, f64(workspace.fallen_parts_destroy_height))
	case "FallHeightEnabled":
		vm.PushBoolean(L, workspace.fall_height_enabled)
	case "DistributedGameTime":
		vm.PushNumber(L, workspace.distributed_game_time)
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
	case:
		return false
	}
	return true
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
	classes.Object_Destroy(object)
	free(workspace)
}

Register_Workspace_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Workspace_Class,
		workspace_construct,
		workspace_destroy,
		creatable = false,
		get = workspace_get,
		set = workspace_set,
		namecall = workspace_namecall,
	)
}
