package services

// wire:service global="workspace"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import kineffi "../bindings"
import materials "../material"
import vm "../vm"

Workspace_Class := classes.Class_Info{
	name   = "Workspace",
	parent = &Service_Class,
}

Workspace :: struct {
	using service: Service,
	cube_mesh:     ^kineffi.KineFilamentMesh,
	sphere_mesh:   ^kineffi.KineFilamentMesh,
	cylinder_mesh: ^kineffi.KineFilamentMesh,
	fallen_parts_destroy_height: f32,
	fall_height_enabled: bool,
	distributed_game_time: f64,
	current_camera: ^classes.Camera,
}

workspace_construct :: proc(renderer: ^classes.Renderer_Object, data_model: rawptr) -> ^classes.Object {
	workspace := new(Workspace)
	workspace.service = Service_Init(&Workspace_Class, "Workspace", data_model)
	workspace.fallen_parts_destroy_height = -500
	workspace.fall_height_enabled = true
	return &workspace.object
}

workspace_ensure_meshes :: proc(workspace: ^Workspace, renderer: ^classes.Renderer_Object) -> bool {
	if renderer == nil || renderer.Filament == nil { return false }
	if workspace.cube_mesh == nil {
		workspace.cube_mesh = kineffi.Kine_Filament_CreateMesh(renderer.Filament, kineffi.KINE_MESH_CUBE)
		workspace.sphere_mesh = kineffi.Kine_Filament_CreateMesh(renderer.Filament, kineffi.KINE_MESH_SPHERE)
		workspace.cylinder_mesh = kineffi.Kine_Filament_CreateMesh(renderer.Filament, kineffi.KINE_MESH_CYLINDER)
	}
	return workspace.cube_mesh != nil
}

workspace_part_mesh :: proc(workspace: ^Workspace, shape: enums.PartType) -> ^kineffi.KineFilamentMesh {
	#partial switch shape {
	case .Ball: return workspace.sphere_mesh
	case .Cylinder: return workspace.cylinder_mesh
	case: return workspace.cube_mesh
	}
}

workspace_has_parts :: proc(object: ^classes.Object) -> bool {
	if object == nil { return false }
	for child in object.children {
		if child == nil || child.destroyed { continue }
		if classes.Is_A(child, "Part") || workspace_has_parts(child) { return true }
	}
	return false
}

workspace_prepare_3d :: proc(workspace: ^Workspace, renderer: ^classes.Renderer_Object) {
	if workspace == nil || !workspace_has_parts(&workspace.object) { return }
	if !workspace_ensure_meshes(workspace, renderer) { return }

	materials.init(renderer)
}

Workspace_Apply_View :: proc(renderer: ^classes.Renderer_Object, cframe: datatypes.CFrame) -> datatypes.CFrame {
	if renderer == nil || !renderer.HasWorldToView { return cframe }
	view := renderer.WorldToView
	return datatypes.CFrame_Mul_CFrame(datatypes.CFrame{
		x = view[0], y = view[1], z = view[2],
		r00 = view[3], r01 = view[4], r02 = view[5],
		r10 = view[6], r11 = view[7], r12 = view[8],
		r20 = view[9], r21 = view[10], r22 = view[11],
	}, cframe)
}

workspace_append_draw_items :: proc(
	workspace: ^Workspace,
	object: ^classes.Object,
	renderer: ^classes.Renderer_Object,
	items: ^[dynamic]kineffi.KineFilamentDrawItem,
) {
	for child in object.children {
		if child == nil || child.destroyed { continue }

		if classes.Is_A(child, "Part") {
			part := cast(^classes.Part)child
			cframe := part.cframe
			size := part.size

			render_material := materials.Get(part.material)
			material_kind, param1, param2, param3, transmission :=
				materials.Draw_Parameters(render_material)

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

			append(items, kineffi.KineFilamentDrawItem{
				mesh = workspace_part_mesh(workspace, part.shape),
				tex = render_material.texture,
				transform = {
					cframe.r00*size.x, cframe.r01*size.y, cframe.r02*size.z, cframe.x,
					cframe.r10*size.x, cframe.r11*size.y, cframe.r12*size.z, cframe.y,
					cframe.r20*size.x, cframe.r21*size.y, cframe.r22*size.z, cframe.z,
					0, 0, 0, 1,
				},
				r = part.color.R,
				g = part.color.G,
				b = part.color.B,
				param1 = param1,
				param2 = param2,
				param3 = param3,
				transmission = transmission,
				materialKind = material_kind,
				flags = kineffi.KINE_FILAMENT_DRAW_CAST_SHADOWS |
				        kineffi.KINE_FILAMENT_DRAW_RECEIVE_SHADOWS |
				        kineffi.KINE_FILAMENT_DRAW_CULLING,
			})
		}

		workspace_append_draw_items(workspace, child, renderer, items)
	}
}

workspace_render_3d :: proc(object: ^classes.Object, ctx: ^classes.Class_Step_Context) {
	workspace := cast(^Workspace)object
	if !workspace_has_parts(object) { return }
	if ctx == nil || ctx.renderer == nil || ctx.renderer.Filament == nil { return }
	if !workspace_ensure_meshes(workspace, ctx.renderer) { return }

	materials.init(ctx.renderer)

	items: [dynamic]kineffi.KineFilamentDrawItem
	workspace_append_draw_items(workspace, object, ctx.renderer, &items)
	if len(items) > 0 {
		_ = kineffi.Kine_Filament_DrawMeshList(
			ctx.renderer.Filament,
			raw_data(items),
			u32(len(items)),
		)
	}
	delete(items)
}

workspace_physics :: proc(workspace: ^Workspace) -> ^Physics {
	object := Service_Get_Service(&workspace.service, "Physics")
	if object == nil { return nil }
	return cast(^Physics)object
}

workspace_get :: proc(L: ^vm.State, object: ^classes.Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, key: string) -> bool {
	workspace := cast(^Workspace)object
	physics := workspace_physics(workspace)
	switch key {
	case "CurrentCamera": classes.Push_Object(L, cast(^classes.Object)workspace.current_camera)
	case "Gravity": vm.PushNumber(L, physics == nil ? 196.2 : f64(physics.gravity))
	case "FallenPartsDestroyHeight": vm.PushNumber(L, f64(workspace.fallen_parts_destroy_height))
	case "FallHeightEnabled": vm.PushBoolean(L, workspace.fall_height_enabled)
	case "DistributedGameTime": vm.PushNumber(L, workspace.distributed_game_time)
	case "Raycast", "GetNumAwakeParts", "GetPhysicsThrottling", "GetRealPhysicsFPS", "PGSIsEnabled": vm.PushUserdataMethod(L, key)
	case: return false
	}
	return true
}

workspace_set :: proc(L: ^vm.State, object: ^classes.Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, key: string, value_index: int) -> bool {
	workspace := cast(^Workspace)object
	switch key {
	case "CurrentCamera":
		camera := classes.object_from_argument(L, value_index)
		if camera == nil || !classes.Is_A(camera, "Camera") { return false }
		workspace.current_camera = cast(^classes.Camera)camera
		registry := cast(^DataModel)workspace.data_model
		if registry != nil && registry.registry.classes.renderer != nil {
			registry.registry.classes.renderer.ActiveCamera = camera
		}
	case "Gravity":
		physics := workspace_physics(workspace)
		if physics == nil { return false }
		Physics_Set_Gravity(physics, f32(vm.ArgNumber(L, value_index)))
	case "FallenPartsDestroyHeight":
		workspace.fallen_parts_destroy_height = clamp(f32(vm.ArgNumber(L, value_index)), -50_000, 50_000)
	case "FallHeightEnabled":
		workspace.fall_height_enabled = vm.ArgBoolean(L, value_index)
	case: return false
	}
	return true
}

workspace_namecall :: proc(L: ^vm.State, object: ^classes.Object, datatype_registry: ^datatypes.Registry, enum_registry: ^enums.Registry, method: string) -> (i32, bool) {
	workspace := cast(^Workspace)object
	physics := workspace_physics(workspace)
	switch method {
	case "Raycast":
		if datatype_registry == nil { return vm.RaiseError(L, "datatype registry is unavailable"), true }
		x, y, z := vm.ArgVector3(L, 2)
		dx, dy, dz := vm.ArgVector3(L, 3)
		params: ^datatypes.RaycastParams
		if !vm.IsNoneOrNil(L, 4) { params = datatypes.Arg_RaycastParams(L, 4, datatype_registry) }
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
		if !hit { vm.PushNil(L) } else { datatypes.Push_RaycastResult(L, datatype_registry, result) }
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
		if workspace.cube_mesh != nil { _ = kineffi.Kine_Filament_DestroyMesh(renderer.Filament, workspace.cube_mesh) }
		if workspace.sphere_mesh != nil { _ = kineffi.Kine_Filament_DestroyMesh(renderer.Filament, workspace.sphere_mesh) }
		if workspace.cylinder_mesh != nil { _ = kineffi.Kine_Filament_DestroyMesh(renderer.Filament, workspace.cylinder_mesh) }
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
