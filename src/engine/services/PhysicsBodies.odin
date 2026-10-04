package services

import assetstore "../assetstore"
import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import jolt "../physics"
import tracy "../util/odin-tracy"
import vm "../vm"
import "core:math"
import "core:strings"

physics_finite_f32 :: proc(value: f32) -> bool {
	return value == value && value > -1.0e20 && value < 1.0e20
}

physics_valid_cframe :: proc(cf: datatypes.CFrame) -> bool {
	return(
		physics_finite_f32(cf.x) &&
		physics_finite_f32(cf.y) &&
		physics_finite_f32(cf.z) &&
		physics_finite_f32(cf.r00) &&
		physics_finite_f32(cf.r01) &&
		physics_finite_f32(cf.r02) &&
		physics_finite_f32(cf.r10) &&
		physics_finite_f32(cf.r11) &&
		physics_finite_f32(cf.r12) &&
		physics_finite_f32(cf.r20) &&
		physics_finite_f32(cf.r21) &&
		physics_finite_f32(cf.r22) \
	)
}

physics_quaternion_from_cframe :: proc(cf: datatypes.CFrame) -> kineffi.JPH_Quat {
	trace := cf.r00 + cf.r11 + cf.r22
	result: kineffi.JPH_Quat
	if trace > 0 {
		s := math.sqrt(trace + 1.0) * 2.0
		result = kineffi.JPH_Quat {
			(cf.r21 - cf.r12) / s,
			(cf.r02 - cf.r20) / s,
			(cf.r10 - cf.r01) / s,
			0.25 * s,
		}
	} else if cf.r00 > cf.r11 && cf.r00 > cf.r22 {
		s := math.sqrt(1.0 + cf.r00 - cf.r11 - cf.r22) * 2.0
		result = kineffi.JPH_Quat {
			0.25 * s,
			(cf.r01 + cf.r10) / s,
			(cf.r02 + cf.r20) / s,
			(cf.r21 - cf.r12) / s,
		}
	} else if cf.r11 > cf.r22 {
		s := math.sqrt(1.0 + cf.r11 - cf.r00 - cf.r22) * 2.0
		result = kineffi.JPH_Quat {
			(cf.r01 + cf.r10) / s,
			0.25 * s,
			(cf.r12 + cf.r21) / s,
			(cf.r02 - cf.r20) / s,
		}
	} else {
		s := math.sqrt(1.0 + cf.r22 - cf.r00 - cf.r11) * 2.0
		result = kineffi.JPH_Quat {
			(cf.r02 + cf.r20) / s,
			(cf.r12 + cf.r21) / s,
			0.25 * s,
			(cf.r10 - cf.r01) / s,
		}
	}
	return result
}

physics_shape_for_part :: proc(
	service: ^Physics,
	part: ^classes.Part,
	mesh_part: ^classes.MeshPart = nil,
) -> kineffi.JPH_ShapeRef {
	half := datatypes.Vector3 {
		max(part.size.x * 0.5, 0.001),
		max(part.size.y * 0.5, 0.001),
		max(part.size.z * 0.5, 0.001),
	}
	scale := datatypes.Vector3{half.x, half.y, half.z}


	mesh := mesh_part
	if mesh == nil {
		mesh = physics_mesh_part_of(part)
	}
	if mesh != nil {
		if shape := physics_meshpart_shape(service, mesh, scale); shape != nil {
			return shape
		}
	}

	#partial switch part.shape {
	case .Ball:
		return kineffi.JPH_SphereShape_Create(max(min(half.x, min(half.y, half.z)), 0.001))
	case .Cylinder:
		return kineffi.JPH_CylinderShape_Create(half.y, max(min(half.x, half.z), 0.001), 0)
	case .Capsule:
		return physics_capsule_shape(part.size)
	case .Wedge:
		return physics_convex_hull_shape(physics_wedge_verts[:], scale)
	case .CornerWedge:
		return physics_convex_hull_shape(physics_corner_wedge_verts[:], scale)
	case .Cone:
		return physics_cone_shape(scale)
	case .Pyramid:
		return physics_convex_hull_shape(physics_pyramid_verts[:], scale)
	case .TriangleWedge:
		return physics_convex_hull_shape(physics_triangle_wedge_verts[:], scale)
	case .Truss, .Torus:
		value := kineffi.JPH_Vec3{half.x, half.y, half.z}
		return kineffi.JPH_BoxShape_Create(&value, 0)
	case:
		value := kineffi.JPH_Vec3{half.x, half.y, half.z}
		return kineffi.JPH_BoxShape_Create(&value, 0)
	}
}

physics_wedge_verts := [6]datatypes.Vector3 {
	{1, -1, -1},
	{1, -1, 1},
	{-1, 1, -1},
	{-1, -1, -1},
	{-1, 1, 1},
	{-1, -1, 1},
}

physics_corner_wedge_verts := [7]datatypes.Vector3 {
	{-1, -1, 1},
	{-1, -1, -1},
	{1, -1, 1},
	{1, -1, -1},
	{-1, 1, 1},
	{-1, 1, -1},
	{1, 1, 1},
}

physics_pyramid_verts := [5]datatypes.Vector3 {
	{-1, -1, 1},
	{-1, -1, -1},
	{1, -1, 1},
	{1, -1, -1},
	{0, 1, 0},
}

physics_triangle_wedge_verts := [5]datatypes.Vector3 {
	{-1, -1, 1},
	{-1, -1, -1},
	{1, -1, 1},
	{1, -1, -1},
	{-1, 1, 1},
}

physics_convex_hull_shape :: proc(
	unit_verts: []datatypes.Vector3,
	scale: datatypes.Vector3,
) -> kineffi.JPH_ShapeRef {
	if len(unit_verts) < 4 {
		return nil
	}
	points := make([]kineffi.JPH_Vec3, len(unit_verts))
	defer delete(points)
	for vert, i in unit_verts {
		points[i] = kineffi.JPH_Vec3{vert.x * scale.x, vert.y * scale.y, vert.z * scale.z}
	}
	return kineffi.JPH_ConvexHullShape_Create(raw_data(points), u32(len(points)), 0)
}

physics_cone_shape :: proc(scale: datatypes.Vector3) -> kineffi.JPH_ShapeRef {
	SEGMENTS :: 16
	points := make([dynamic]kineffi.JPH_Vec3, 0, SEGMENTS + 1)
	defer delete(points)
	for i in 0 ..< SEGMENTS {
		angle := f32(i) * 2.0 * math.PI / SEGMENTS
		append(
			&points,
			kineffi.JPH_Vec3{math.cos(angle) * scale.x, -scale.y, math.sin(angle) * scale.z},
		)
	}
	append(&points, kineffi.JPH_Vec3{0, scale.y, 0})
	return kineffi.JPH_ConvexHullShape_Create(raw_data(points), u32(len(points)), 0)
}

physics_capsule_shape :: proc(size: datatypes.Vector3) -> kineffi.JPH_ShapeRef {
	radius := max(min(size.x, size.z) * 0.5, 0.001)
	half_height := max(size.y * 0.5 - radius, 0)
	return kineffi.JPH_CapsuleShape_Create(half_height, radius, 0)
}

physics_meshpart_shape :: proc(
	service: ^Physics,
	mesh_part: ^classes.MeshPart,
	scale: datatypes.Vector3,
) -> kineffi.JPH_ShapeRef {
	if classes.Is_A(&mesh_part.object, "MeshPart") &&
	   (mesh_part.mesh_id != "" || mesh_part.editable_mesh_id != 0) {
		#partial switch mesh_part.collision_fidelity {
		case .Box:
			half := datatypes.Vector3 {
				max(mesh_part.size.x * 0.5, 0.001),
				max(mesh_part.size.y * 0.5, 0.001),
				max(mesh_part.size.z * 0.5, 0.001),
			}
			value := kineffi.JPH_Vec3{half.x, half.y, half.z}
			return kineffi.JPH_BoxShape_Create(&value, 0)
		case .Hull, .Default:
			return physics_mesh_hull_shape(mesh_part, scale)
		case .PreciseConvexDecomposition:
			return physics_mesh_pcd_shape(service, mesh_part, scale)
		}
	}
	return nil
}

physics_load_mesh_data :: proc(
	mesh_part: ^classes.MeshPart,
) -> (
	[]kineffi.JPH_Vec3,
	[dynamic]u32,
	bool,
) {


	resolved := assetstore.Resolve_Path(mesh_part.mesh_id)
	defer delete(resolved)
	if resolved == "" {


		assetstore.Report_Missing_Asset(mesh_part.mesh_id, "Physics collision mesh")
		return nil, nil, false
	}
	c_path := strings.clone_to_cstring(resolved)
	defer delete(c_path)
	data := kineffi.Kine_Filament_LoadMeshDataFromPath(c_path)
	if data == nil {
		return nil, nil, false
	}
	defer _ = kineffi.Kine_Filament_DestroyMeshData(data)
	vertex_count := kineffi.Kine_Filament_GetMeshDataVertexCount(data)
	index_count := kineffi.Kine_Filament_GetMeshDataIndexCount(data)
	if vertex_count <= 0 || index_count < 3 || index_count % 3 != 0 {
		return nil, nil, false
	}
	positions := make([]f32, vertex_count * 3)
	defer delete(positions)
	indices := make([]u32, index_count)
	defer delete(indices)
	if kineffi.Kine_Filament_CopyMeshDataPositions(
		   data,
		   raw_data(positions),
		   i32(len(positions)),
	   ) ==
		   0 ||
	   kineffi.Kine_Filament_CopyMeshDataIndices(data, raw_data(indices), i32(len(indices))) == 0 {
		return nil, nil, false
	}
	verts := make([]kineffi.JPH_Vec3, vertex_count)
	for i in 0 ..< vertex_count {
		verts[i] = kineffi.JPH_Vec3{positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2]}
	}
	idx := make([dynamic]u32, index_count)
	copy(idx[:], indices)
	return verts, idx, true
}

physics_mesh_hull_shape :: proc(
	mesh_part: ^classes.MeshPart,
	scale: datatypes.Vector3,
) -> kineffi.JPH_ShapeRef {
	verts: []kineffi.JPH_Vec3
	ok := false
	if mesh_part.editable_mesh_id != 0 {
		verts, ok = physics_editable_mesh_vertices(mesh_part)
	} else {
		verts, _, ok = physics_load_mesh_data(mesh_part)
	}
	if !ok {
		return nil
	}
	defer delete(verts)
	for i in 0 ..< len(verts) {
		verts[i] = kineffi.JPH_Vec3 {
			verts[i].x * scale.x,
			verts[i].y * scale.y,
			verts[i].z * scale.z,
		}
	}
	if len(verts) < 4 {
		return nil
	}
	return kineffi.JPH_ConvexHullShape_Create(raw_data(verts), u32(len(verts)), 0)
}

physics_editable_mesh_vertices :: proc(
	mesh_part: ^classes.MeshPart,
) -> (
	[]kineffi.JPH_Vec3,
	bool,
) {
	mesh := classes.EditableMesh_Of_Handle(mesh_part.editable_mesh_id)
	if mesh == nil {
		return nil, false
	}
	center := classes.EditableMesh_Get_Center(mesh)
	bounds := classes.EditableMesh_Get_Size(mesh)
	scale := editable_mesh_render_scale(bounds)

	corners: [dynamic]classes.EditableMesh_Corner_Data
	_ = classes.EditableMesh_Collect_Corners(mesh, &corners)
	defer delete(corners)

	if len(corners) == 0 {
		return nil, false
	}
	verts := make([]kineffi.JPH_Vec3, len(corners))
	for corner, i in corners {
		verts[i] = kineffi.JPH_Vec3 {
			(corner.position.x - center.x) * scale.x,
			(corner.position.y - center.y) * scale.y,
			(corner.position.z - center.z) * scale.z,
		}
	}
	return verts, true
}

physics_editable_mesh_triangles :: proc(
	mesh_part: ^classes.MeshPart,
) -> (
	[]kineffi.JPH_Vec3,
	[dynamic]u32,
	bool,
) {
	mesh := classes.EditableMesh_Of_Handle(mesh_part.editable_mesh_id)
	if mesh == nil {
		return nil, nil, false
	}
	center := classes.EditableMesh_Get_Center(mesh)
	bounds := classes.EditableMesh_Get_Size(mesh)
	scale := editable_mesh_render_scale(bounds)

	corners: [dynamic]classes.EditableMesh_Corner_Data
	_ = classes.EditableMesh_Collect_Triangles(mesh, &corners)
	defer delete(corners)

	if len(corners) == 0 || len(corners) % 3 != 0 {
		return nil, nil, false
	}
	verts := make([]kineffi.JPH_Vec3, len(corners))
	idx := make([dynamic]u32, len(corners))
	for corner, i in corners {
		verts[i] = kineffi.JPH_Vec3 {
			(corner.position.x - center.x) * scale.x,
			(corner.position.y - center.y) * scale.y,
			(corner.position.z - center.z) * scale.z,
		}
		idx[i] = u32(i)
	}
	return verts, idx, true
}

physics_mesh_pcd_shape :: proc(
	service: ^Physics,
	mesh_part: ^classes.MeshPart,
	scale: datatypes.Vector3,
) -> kineffi.JPH_ShapeRef {
	editable := mesh_part.editable_mesh_id != 0
	version := u64(0)
	if editable {
		mesh := classes.EditableMesh_Of_Handle(mesh_part.editable_mesh_id)
		if mesh != nil {
			version = mesh.version
		}
	}
	key := Physics_Shape_Cache_Key {
		mesh_id               = strings.clone(mesh_part.mesh_id),
		editable_mesh_id      = mesh_part.editable_mesh_id,
		editable_mesh_version = version,
		size                  = mesh_part.size,
	}
	if service != nil && service.pcd_cache != nil {
		if cached, ok := service.pcd_cache[key]; ok {
			delete(key.mesh_id)
			kineffi.JPH_Shape_AddRef(cached)
			return cached
		}
	}
	verts: []kineffi.JPH_Vec3
	idx: [dynamic]u32
	ok := false
	if editable {
		verts, idx, ok = physics_editable_mesh_triangles(mesh_part)
	} else {
		verts, idx, ok = physics_load_mesh_data(mesh_part)
	}
	if !ok {
		delete(key.mesh_id)
		return nil
	}
	defer delete(verts)
	defer delete(idx)
	shape := kineffi.JPH_VHACD_Compound_Create(
		raw_data(verts),
		u32(len(verts)),
		raw_data(idx),
		u32(len(idx)),
		&kineffi.JPH_Vec3{scale.x, scale.y, scale.z},
	)
	if shape == nil {
		delete(key.mesh_id)
		return nil
	}
	if service != nil && service.pcd_cache != nil {
		service.pcd_cache[key] = shape
		kineffi.JPH_Shape_AddRef(shape)
		return shape
	}
	delete(key.mesh_id)
	return shape
}

part_in_character_model :: proc(part: ^classes.Part) -> bool {
	if part == nil {return false}
	node: ^classes.Object = &part.object
	for node != nil {


		if classes.Is_A_Class(node, &classes.CharacterModel_Class) {return true}
		node = node.parent
	}
	return false
}


Physics_Ownership_Context :: struct {
	replicator: ^ReplicatorService,
	players:    ^Players,
}

physics_ownership_context :: proc(service: ^Physics) -> Physics_Ownership_Context {

	resolved: Physics_Ownership_Context
	if service == nil || service.data_model == nil {return resolved}


	when ODIN_OS == .JS {
		return resolved
	} else {
		resolved.replicator = cast(^ReplicatorService)DataModel_Get_Service(
			service.data_model,
			"ReplicatorService",
		)
		resolved.players = cast(^Players)DataModel_Get_Service(service.data_model, "Players")
		return resolved
	}
}

physics_remote_owned :: proc(
	service: ^Physics,
	part: ^classes.Part,
	ownership: Physics_Ownership_Context,
) -> bool {
	if service == nil || service.data_model == nil || part == nil {return false}


	when ODIN_OS == .JS {
		return false
	} else {
		replicator := ownership.replicator
		if replicator == nil || replicator.mode == .Stopped {return false}
		entity := replication_entity(replicator, &part.object)
		if entity == nil {return false}


		if replicator.mode == .Client {
			players := ownership.players


			if players == nil || players.local_player == nil {return true}
			return entity.owner_id != players.local_player.user_id
		}


		return entity.owner_id != 0
	}
}


physics_part_awaiting_transform :: proc(
	service: ^Physics,
	part: ^classes.Part,
	ownership: Physics_Ownership_Context,
) -> bool {
	if service == nil || service.data_model == nil || part == nil {return false}


	when ODIN_OS == .JS {
		return false
	} else {
		replicator := ownership.replicator
		if replicator == nil || replicator.mode != .Client {return false}
		entity := replication_entity(replicator, &part.object)
		return entity != nil && !entity.has_transform
	}
}

physics_create_body :: proc(
	service: ^Physics,
	part: ^classes.Part,
	ownership: Physics_Ownership_Context,
	mesh_part: ^classes.MeshPart = nil,
) -> (
	Physics_Body,
	bool,
) {
	if part == nil {return Physics_Body{}, false}
	if part_in_character_model(part) {return Physics_Body{}, false}


	if physics_part_awaiting_transform(service, part, ownership) {return Physics_Body{}, false}

	shape := physics_shape_for_part(service, part, mesh_part)
	if shape == nil {
		return Physics_Body{}, false
	}
	defer kineffi.JPH_Shape_Destroy(shape)

	position := kineffi.JPH_RVec3{f64(part.cframe.x), f64(part.cframe.y), f64(part.cframe.z)}

	rotation := physics_quaternion_from_cframe(part.cframe)

	remote := physics_remote_owned(service, part, ownership)

	static := part.anchored || remote

	motion_type: kineffi.JPH_MotionType = static ? .Static : .Dynamic

	layer: kineffi.JPH_ObjectLayer =
		static ? jolt.OBJECT_LAYER_NON_MOVING : jolt.OBJECT_LAYER_MOVING

	settings := kineffi.JPH_BodyCreationSettings_Create3(
		shape,
		&position,
		&rotation,
		motion_type,
		layer,
	)

	if settings == nil {
		return Physics_Body{}, false
	}
	defer kineffi.JPH_BodyCreationSettings_Destroy(settings)

	properties := jolt.Material_Get_Properties(part.material)

	kineffi.JPH_BodyCreationSettings_SetFriction(settings, properties.friction)

	kineffi.JPH_BodyCreationSettings_SetRestitution(settings, properties.restitution)

	body := kineffi.JPH_BodyInterface_CreateBody(service.system.body_interface, settings)

	if body == nil {
		return Physics_Body{}, false
	}

	body_id := kineffi.JPH_Body_GetID(body)

	if body_id == kineffi.JPH_BODY_ID_INVALID {
		kineffi.JPH_BodyInterface_DestroyBody(service.system.body_interface, body)
		return Physics_Body{}, false
	}

	activation: kineffi.JPH_ActivationMode = static ? .DontActivate : .Activate

	kineffi.JPH_BodyInterface_AddBody(service.system.body_interface, body_id, activation)

	service.body_to_part[body_id] = part


	mesh := mesh_part
	if mesh == nil {
		mesh = physics_mesh_part_of(part)
	}

	mesh_id := ""
	editable_mesh_id := u32(0)

	if mesh != nil {
		mesh_id = strings.clone(mesh.mesh_id)
		editable_mesh_id = mesh.editable_mesh_id
	}

	return Physics_Body {
			&part.object,
			body_id,
			part.size,
			part.shape,
			part.anchored,
			remote,
			part.cframe,
			mesh_id,
			editable_mesh_id,
			physics_mesh_part_version(mesh),
			mesh_part_collision_fidelity(mesh),
		},
		true
}


TERRAIN_COLLISION_MAX_TRIANGLES: int = 1 << 21


physics_terrain_occupies :: proc(terrain: ^Terrain, x, y, z: int) -> bool {
	cell, ok := terrain.voxels[Terrain_Voxel_Key{x, y, z}]
	return ok && cell.occupancy > 0
}

physics_terrain_corner :: proc(
	terrain: ^Terrain,
	x, y, z: int,
	corner: [3]int,
) -> kineffi.JPH_Vec3 {
	return kineffi.JPH_Vec3 {
		f32(x + corner[0]) * terrain.voxel_size,
		f32(y + corner[1]) * terrain.voxel_size,
		f32(z + corner[2]) * terrain.voxel_size,
	}
}


physics_terrain_face :: proc(
	triangles: ^[dynamic]kineffi.JPH_Triangle,
	terrain: ^Terrain,
	x, y, z: int,
	nx, ny, nz: int,
	c0, c1, c2, c3: [3]int,
) {
	if len(triangles) + 4 > TERRAIN_COLLISION_MAX_TRIANGLES {return}
	if physics_terrain_occupies(terrain, x + nx, y + ny, z + nz) {return}

	a := physics_terrain_corner(terrain, x, y, z, c0)
	b := physics_terrain_corner(terrain, x, y, z, c1)
	c := physics_terrain_corner(terrain, x, y, z, c2)
	d := physics_terrain_corner(terrain, x, y, z, c3)

	append(triangles, kineffi.JPH_Triangle{v1 = a, v2 = b, v3 = c, materialIndex = 0})
	append(triangles, kineffi.JPH_Triangle{v1 = a, v2 = c, v3 = d, materialIndex = 0})
	append(triangles, kineffi.JPH_Triangle{v1 = a, v2 = c, v3 = b, materialIndex = 0})
	append(triangles, kineffi.JPH_Triangle{v1 = a, v2 = d, v3 = c, materialIndex = 0})
}

physics_build_terrain_shape :: proc(
	terrain: ^Terrain,
) -> (
	shape: kineffi.JPH_ShapeRef,
	triangle_count: int,
) {
	triangles: [dynamic]kineffi.JPH_Triangle
	defer delete(triangles)

	for key, cell in &terrain.voxels {
		if cell.occupancy <= 0 {continue}
		x := int(key.x)
		y := int(key.y)
		z := int(key.z)


		physics_terrain_face(
			&triangles,
			terrain,
			x,
			y,
			z,
			0,
			1,
			0,
			[3]int{0, 1, 0},
			[3]int{0, 1, 1},
			[3]int{1, 1, 1},
			[3]int{1, 1, 0},
		)
		physics_terrain_face(
			&triangles,
			terrain,
			x,
			y,
			z,
			0,
			-1,
			0,
			[3]int{0, 0, 1},
			[3]int{0, 0, 0},
			[3]int{1, 0, 0},
			[3]int{1, 0, 1},
		)
		physics_terrain_face(
			&triangles,
			terrain,
			x,
			y,
			z,
			1,
			0,
			0,
			[3]int{1, 0, 1},
			[3]int{1, 1, 1},
			[3]int{1, 1, 0},
			[3]int{1, 0, 0},
		)
		physics_terrain_face(
			&triangles,
			terrain,
			x,
			y,
			z,
			-1,
			0,
			0,
			[3]int{0, 0, 0},
			[3]int{0, 1, 0},
			[3]int{0, 1, 1},
			[3]int{0, 0, 1},
		)
		physics_terrain_face(
			&triangles,
			terrain,
			x,
			y,
			z,
			0,
			0,
			1,
			[3]int{1, 0, 1},
			[3]int{1, 1, 1},
			[3]int{0, 1, 1},
			[3]int{0, 0, 1},
		)
		physics_terrain_face(
			&triangles,
			terrain,
			x,
			y,
			z,
			0,
			0,
			-1,
			[3]int{0, 0, 0},
			[3]int{0, 1, 0},
			[3]int{1, 1, 0},
			[3]int{1, 0, 0},
		)
	}

	triangle_count = len(triangles)
	if triangle_count == 0 {return}
	shape = kineffi.JPH_MeshShape_Create(&triangles[0], u32(triangle_count))
	return
}


physics_reset_scratch_parts :: proc(parts: ^[dynamic]^classes.Part) {
	resize(parts, 0)
}

physics_reset_scratch_ids :: proc(ids: ^[dynamic]kineffi.JPH_BodyID) {
	resize(ids, 0)
}

physics_destroy_terrain_body :: proc(service: ^Physics) {
	if !service.terrain_valid {return}
	kineffi.JPH_BodyInterface_RemoveAndDestroyBody(
		service.system.body_interface,
		service.terrain_body,
	)
	service.terrain_valid = false
	service.terrain_body = kineffi.JPH_BODY_ID_INVALID
	service.terrain_triangles = 0
}

Physics_Synchronize_Terrain :: proc(service: ^Physics) {
	if service == nil || !service.initialized {return}

	terrain_object := DataModel_Get_Service(service.data_model, "Terrain")
	if terrain_object == nil {return}
	terrain := cast(^Terrain)terrain_object
	if terrain == nil {return}


	if service.terrain_valid && service.terrain_version == terrain.geometry_version {
		return
	}


	physics_destroy_terrain_body(service)

	shape, triangle_count := physics_build_terrain_shape(terrain)
	if shape == nil {return}
	defer kineffi.JPH_Shape_Destroy(shape)

	position := kineffi.JPH_RVec3{0, 0, 0}
	rotation := kineffi.JPH_Quat{0, 0, 0, 1}

	settings := kineffi.JPH_BodyCreationSettings_Create3(
		shape,
		&position,
		&rotation,
		.Static,
		jolt.OBJECT_LAYER_NON_MOVING,
	)
	if settings == nil {return}
	defer kineffi.JPH_BodyCreationSettings_Destroy(settings)


	kineffi.JPH_BodyCreationSettings_SetFriction(settings, 1.0)
	kineffi.JPH_BodyCreationSettings_SetRestitution(settings, 0)

	body := kineffi.JPH_BodyInterface_CreateBody(service.system.body_interface, settings)
	if body == nil {return}

	body_id := kineffi.JPH_Body_GetID(body)
	if body_id == kineffi.JPH_BODY_ID_INVALID {
		kineffi.JPH_BodyInterface_DestroyBody(service.system.body_interface, body)
		return
	}

	kineffi.JPH_BodyInterface_AddBody(service.system.body_interface, body_id, .DontActivate)

	service.terrain_valid = true
	service.terrain_body = body_id
	service.terrain_version = terrain.geometry_version
	service.terrain_triangles = triangle_count
}


physics_mesh_part_of :: proc(part: ^classes.Part) -> ^classes.MeshPart {
	if part == nil || !classes.Is_A_Class(&part.object, &classes.MeshPart_Class) {return nil}
	return cast(^classes.MeshPart)part
}

physics_mesh_part_version :: proc(mesh_part: ^classes.MeshPart) -> u64 {
	if mesh_part != nil && mesh_part.editable_mesh_id != 0 {
		mesh := classes.EditableMesh_Of_Handle(mesh_part.editable_mesh_id)
		if mesh != nil {
			return mesh.version
		}
	}
	return 0
}

mesh_part_collision_fidelity :: proc(mesh_part: ^classes.MeshPart) -> enums.CollisionFidelity {
	if mesh_part == nil {return enums.CollisionFidelity.Default}
	return mesh_part.collision_fidelity
}

physics_refresh_part :: proc(service: ^Physics, part: ^classes.Part) {
	if service == nil || !service.initialized || part == nil {return}
	body_index := physics_find_body_index(service, &part.object)
	if body_index < 0 {return}
	body := service.bodies[body_index]
	physics_destroy_body(service, body)
	new_body, ok := physics_create_body(service, part, physics_ownership_context(service))
	if ok {
		service.bodies[body_index] = new_body

		part.part_index = body_index
	} else {
		service.bodies[body_index].body_id = kineffi.JPH_BODY_ID_INVALID
		service.bodies[body_index].object = nil
		part.part_index = -1
	}


	Physics_Reindex_Bodies(service)


	classes.Hierarchy_Touched()


	service.broadphase_dirty = true
}


physics_destroy_body :: proc(service: ^Physics, body: Physics_Body, clear_part_index := true) {
	if service.system.body_interface != nil && body.body_id != kineffi.JPH_BODY_ID_INVALID {
		kineffi.JPH_BodyInterface_RemoveAndDestroyBody(service.system.body_interface, body.body_id)
	}
	delete_key(&service.body_to_part, body.body_id)


	if clear_part_index {
		if part := cast(^classes.Part)body.object; part != nil {
			part.part_index = -1
		}
	}
	delete(body.mesh_id)
}

physics_part_for_body :: proc(service: ^Physics, body_id: kineffi.JPH_BodyID) -> ^classes.Part {
	if service == nil {return nil}
	part, ok := service.body_to_part[body_id]
	if !ok {return nil}
	return part
}


Physics_Reindex_Bodies :: proc(service: ^Physics) {
	for body, index in service.bodies {
		if part := cast(^classes.Part)body.object; part != nil {
			part.part_index = index
		}
	}
}

physics_collect_parts :: proc(object: ^classes.Object, parts: ^[dynamic]^classes.Part) {
	if object == nil {return}
	for child in object.children {
		if child == nil || child.destroyed {continue}


		if classes.Is_A_Class(child, &classes.Part_Class) {
			append(parts, cast(^classes.Part)child)
		}
		physics_collect_parts(child, parts)
	}
}


Physics_Collect_Service_Parts :: proc(
	service: ^Physics,
	workspace: ^classes.Object,
) -> [dynamic]^classes.Part {
	parts := service.scratch_parts
	physics_reset_scratch_parts(&parts)
	physics_collect_parts(workspace, &parts)
	service.scratch_parts = parts
	return parts
}

physics_contains_part :: proc(parts: []^classes.Part, object: ^classes.Object) -> bool {
	for part in parts {if &part.object == object {return true}}
	return false
}

physics_find_body_index :: proc(service: ^Physics, object: ^classes.Object) -> int {
	for body, i in service.bodies {if body.object == object {return i}}
	return -1
}


Physics_Sync_Needed :: proc(service: ^Physics) -> bool {
	if service == nil {return false}
	epoch := classes.Hierarchy_Epoch()


	if service.has_synced && service.synced_epoch == epoch && !service.sync_bumped {
		return false
	}
	service.sync_epoch = epoch
	return true
}


Physics_Sync_Complete :: proc(service: ^Physics, epoch: u64) {
	service.synced_epoch = epoch
	service.has_synced = true
	service.sync_bumped = false
}

// Physics_Request_Sync re-arms the next Physics_Synchronize.
//
// Physics_Synchronize normally short-circuits on the Instance tree's structural
// epoch, because walking the whole tree every frame is the expensive part. That
// is sound for reparenting, but it is blind to the other reason a Part can
// become collidable: eligibility that lives outside the tree. The client refuses
// to give a replicated Part a body until that Part's first authoritative
// transform arrives (physics_part_awaiting_transform), and that arrival is a
// property update, not a structural change, so it moves no epoch. A Part that
// was walked before its transform landed was skipped and was then never
// revisited, which left a permanently bodyless Part: the client could not collide
// with it and had no ground under the character standing on it.
//
// Anything that changes a Part's eligibility outside the tree calls this so the
// skipped Parts are retried on the next synchronize.
Physics_Request_Sync :: proc(service: ^Physics) {
	if service == nil {return}
	service.sync_bumped = true
}

// Physics_Request_Sync_For_Data_Model is the service-lookup form of
// Physics_Request_Sync, for callers that hold a DataModel rather than the
// Physics service itself.
Physics_Request_Sync_For_Data_Model :: proc(data_model: ^DataModel) {
	if data_model == nil {return}
	physics := cast(^Physics)DataModel_Get_Service(data_model, "Physics")
	Physics_Request_Sync(physics)
}


Physics_Part_Transform_Applied :: proc() {}

Physics_Synchronize :: proc(service: ^Physics, workspace: ^classes.Object) {
	if service == nil || !service.initialized || workspace == nil {
		return
	}


	tracy.ZoneNC("Jolt Terrain Synchronize", 0xE06C75)
	Physics_Synchronize_Terrain(service)

	if !Physics_Sync_Needed(service) {


		if service.broadphase_dirty {
			tracy.ZoneNC("Jolt Optimize Broad Phase", 0xE06C75)

			kineffi.JPH_PhysicsSystem_OptimizeBroadPhase(service.system.handle)
			service.broadphase_dirty = false
		}
		return
	}
	sync_epoch := service.sync_epoch


	tracy.ZoneNC("Physics Ownership", 0xE06C75)

	ownership := physics_ownership_context(service)


	parts := service.scratch_parts
	physics_reset_scratch_parts(&parts)
	physics_collect_parts(workspace, &parts)
	service.scratch_parts = parts

	topology_changed := false


	tracy.ZoneNC("Physics Drop Bodies", 0xE06C75)

	i := len(service.bodies)
	for i > 0 {
		i -= 1

		body := service.bodies[i]
		part := cast(^classes.Part)body.object
		if part != nil && part.part_index == i && !part.destroyed {
			continue
		}
		physics_destroy_body(service, body)
		unordered_remove(&service.bodies, i)
		topology_changed = true
	}


	if topology_changed {
		tracy.ZoneNC("Jolt Reindex", 0xE06C75)

		Physics_Reindex_Bodies(service)
	}

	tracy.ZoneNC("Physics Create Bodies", 0xE06C75)

	for part in parts {


		mesh_part := physics_mesh_part_of(part)

		body_index := part.part_index


		exists :=
			body_index >= 0 &&
			body_index < len(service.bodies) &&
			service.bodies[body_index].object == &part.object

		if !exists {
			body, ok := physics_create_body(service, part, ownership, mesh_part)

			if ok {
				part.part_index = len(service.bodies)
				append(&service.bodies, body)
				topology_changed = true
			}

			continue
		}

		body := &service.bodies[body_index]

		mesh_id := ""
		editable_mesh_id := u32(0)

		if mesh_part != nil {
			mesh_id = mesh_part.mesh_id
			editable_mesh_id = mesh_part.editable_mesh_id
		}

		mesh_version := physics_mesh_part_version(mesh_part)
		collision_fidelity := mesh_part_collision_fidelity(mesh_part)
		remote := physics_remote_owned(service, part, ownership)

		if body.size != part.size ||
		   body.shape != part.shape ||
		   body.anchored != part.anchored ||
		   body.remote != remote ||
		   body.mesh_id != mesh_id ||
		   body.editable_mesh_id != editable_mesh_id ||
		   body.editable_mesh_version != mesh_version ||
		   body.collision_fidelity != collision_fidelity {

			physics_destroy_body(service, body^)

			new_body, ok := physics_create_body(service, part, ownership, mesh_part)

			if ok {
				body^ = new_body


				part.part_index = body_index
			} else {
				body.body_id = kineffi.JPH_BODY_ID_INVALID
				body.object = nil
			}

			topology_changed = true
			continue
		}

		if body.last_cframe != part.cframe {
			position := kineffi.JPH_RVec3 {
				f64(part.cframe.x),
				f64(part.cframe.y),
				f64(part.cframe.z),
			}

			activation: kineffi.JPH_ActivationMode =
				(part.anchored || remote) ? .DontActivate : .Activate

			rotation_changed :=
				body.last_cframe.r00 != part.cframe.r00 ||
				body.last_cframe.r01 != part.cframe.r01 ||
				body.last_cframe.r02 != part.cframe.r02 ||
				body.last_cframe.r10 != part.cframe.r10 ||
				body.last_cframe.r11 != part.cframe.r11 ||
				body.last_cframe.r12 != part.cframe.r12 ||
				body.last_cframe.r20 != part.cframe.r20 ||
				body.last_cframe.r21 != part.cframe.r21 ||
				body.last_cframe.r22 != part.cframe.r22

			if rotation_changed {
				rotation := physics_quaternion_from_cframe(part.cframe)

				kineffi.JPH_BodyInterface_SetPositionAndRotation(
					service.system.body_interface,
					body.body_id,
					&position,
					&rotation,
					activation,
				)
			} else {
				kineffi.JPH_BodyInterface_SetPosition(
					service.system.body_interface,
					body.body_id,
					&position,
					activation,
				)
			}

			body.last_cframe = part.cframe
		}
	}


	i = len(service.bodies)
	for i > 0 {
		i -= 1

		if service.bodies[i].body_id == kineffi.JPH_BODY_ID_INVALID {
			unordered_remove(&service.bodies, i)
			topology_changed = true
		}
	}


	tracy.ZoneNC("Jolt Reindex", 0xE06C75)

	if topology_changed {
		Physics_Reindex_Bodies(service)
	}


	tracy.ZoneNC("Jolt Optimize Broad Phase 2", 0xE06C75)

	if topology_changed || service.broadphase_dirty {
		kineffi.JPH_PhysicsSystem_OptimizeBroadPhase(service.system.handle)
		service.broadphase_dirty = false
	}


	tracy.ZoneNC("Jolt Sync Complete", 0xE06C75)

	Physics_Sync_Complete(service, sync_epoch)
}

physics_capsule_size_from_root :: proc(root: ^classes.Part) -> (radius, half_height: f32) {
	radius = max(root.size.x, root.size.z) / 2 * 0.55
	half_height = root.size.y / 2 - radius
	if radius <= 0.001 {radius = 0.001}
	if half_height < 0.01 {half_height = 0.01}
	return
}

physics_cframe_from_quaternion :: proc(q: kineffi.JPH_Quat) -> datatypes.CFrame {
	x := q.x
	y := q.y
	z := q.z
	w := q.w
	xx := x * x
	yy := y * y
	zz := z * z
	xy := x * y
	xz := x * z
	yz := y * z
	wx := w * x
	wy := w * y
	wz := w * z
	return datatypes.CFrame {
		r00 = 1 - 2 * (yy + zz),
		r01 = 2 * (xy - wz),
		r02 = 2 * (xz + wy),
		r10 = 2 * (xy + wz),
		r11 = 1 - 2 * (xx + zz),
		r12 = 2 * (yz - wx),
		r20 = 2 * (xz - wy),
		r21 = 2 * (yz + wx),
		r22 = 1 - 2 * (xx + yy),
	}
}

Physics_Ensure_Character_Capsule :: proc(
	service: ^Physics,
	coll: ^classes.CollisionController,
	root: ^classes.Part,
	position: datatypes.Vector3,
) {
	if service == nil || coll == nil || root == nil || !service.initialized {return}
	if coll.body_created {return}
	radius, half_height := physics_capsule_size_from_root(root)
	coll.radius = radius
	coll.half_height = half_height
	coll.shape = kineffi.JPH_CapsuleShape_Create(half_height, radius, 0)
	if coll.shape == nil {return}
	pos := kineffi.JPH_RVec3{f64(position.x), f64(position.y), f64(position.z)}
	identity := kineffi.JPH_Quat{0, 0, 0, 1}
	motion: kineffi.JPH_MotionType = coll.ragdoll ? .Dynamic : .Kinematic
	settings := kineffi.JPH_BodyCreationSettings_Create3(
		coll.shape,
		&pos,
		&identity,
		motion,
		jolt.OBJECT_LAYER_MOVING,
	)
	if settings == nil {return}
	defer kineffi.JPH_BodyCreationSettings_Destroy(settings)
	body := kineffi.JPH_BodyInterface_CreateBody(service.system.body_interface, settings)
	if body == nil {return}
	body_id := kineffi.JPH_Body_GetID(body)
	if body_id == kineffi.JPH_BODY_ID_INVALID {
		kineffi.JPH_BodyInterface_DestroyBody(service.system.body_interface, body)
		return
	}
	activation: kineffi.JPH_ActivationMode = coll.ragdoll ? .Activate : .DontActivate
	kineffi.JPH_BodyInterface_AddBody(service.system.body_interface, body_id, activation)
	coll.body_id = body_id
	service.body_to_part[coll.body_id] = root
	coll.body_created = true
}

Physics_Set_Character_Capsule :: proc(
	service: ^Physics,
	coll: ^classes.CollisionController,
	position: datatypes.Vector3,
	yaw: f32,
) {
	if service == nil ||
	   coll == nil ||
	   !coll.body_created ||
	   service.system.body_interface == nil {return}
	cf := datatypes.CFrame_FromEulerAnglesYXZ(0, math.to_radians(yaw), 0)
	cf.x = position.x
	cf.y = position.y
	cf.z = position.z
	rotation := physics_quaternion_from_cframe(cf)
	pos := kineffi.JPH_RVec3{f64(position.x), f64(position.y), f64(position.z)}
	kineffi.JPH_BodyInterface_SetPositionAndRotation(
		service.system.body_interface,
		coll.body_id,
		&pos,
		&rotation,
		.DontActivate,
	)
}

// A sanity ceiling on the velocity handed to the capsule. Anything past this is
// not a character walking, it is a respawn or a teleport, and those have to
// snap rather than fling the capsule across the map.
CHARACTER_CAPSULE_MAX_SPEED :: 500.0

// Parks the capsule at `from` and gives it the velocity that carries it to `to`
// across the next physics step, so the solver integrates it onto the character
// instead of leaving it behind.
//
// This is what lets the character push unanchored Parts. The capsule is
// kinematic, and a kinematic body teleported straight onto its destination has
// no velocity as far as the contact solver is concerned: it behaves like a wall
// that Parts rest against but never move. Driving it with the frame's real
// velocity is what makes the contact constraints see the character actually
// travelling, so anything dynamic in front of it gets shoved.
//
// Callers hand over the frame's start and end and drive the body once per
// physics step, because that is the window the solver integrates over. Driving
// it per sub-step instead would solve the velocity from a position already
// several sub-steps along, and the body would spend the step chasing a target
// the character passed long ago.
Physics_Advance_Character_Capsule :: proc(
	service: ^Physics,
	coll: ^classes.CollisionController,
	from: datatypes.Vector3,
	to: datatypes.Vector3,
	yaw: f32,
	delta_time: f32,
) {
	if service == nil ||
	   coll == nil ||
	   !coll.body_created ||
	   coll.body_id == kineffi.JPH_BODY_ID_INVALID ||
	   service.system.body_interface == nil {return}
	// A ragdolling capsule is simulated rather than driven, so the solver owns
	// its transform. Leaving it alone is what keeps the ragdoll intact.
	if coll.ragdoll {return}
	body_interface := service.system.body_interface
	velocity := kineffi.JPH_Vec3{0, 0, 0}
	if delta_time > 0 {
		velocity.x = (to.x - from.x) / delta_time
		velocity.y = (to.y - from.y) / delta_time
		velocity.z = (to.z - from.z) / delta_time
	}
	// Too fast to be walking means the character was moved wholesale, so snap to
	// the destination with no velocity rather than throwing the capsule at it.
	speed_squared :=
		velocity.x * velocity.x +
		velocity.y * velocity.y +
		velocity.z * velocity.z
	limit := f32(CHARACTER_CAPSULE_MAX_SPEED)
	resting_point := to
	if delta_time <= 0 || speed_squared > limit * limit {
		velocity = kineffi.JPH_Vec3{0, 0, 0}
		resting_point = to
	} else {
		resting_point = from
	}
	cf := datatypes.CFrame_FromEulerAnglesYXZ(0, math.to_radians(yaw), 0)
	cf.x = resting_point.x
	cf.y = resting_point.y
	cf.z = resting_point.z
	rotation := physics_quaternion_from_cframe(cf)
	kineffi.JPH_BodyInterface_SetLinearVelocity(body_interface, coll.body_id, &velocity)
	// Writing the position does not clear the velocity above. While walking this
	// re-seats the body at the start of the frame and lets the solver do the
	// travelling, which is what keeps the body exactly on the character at the
	// end of the step.
	rest := kineffi.JPH_RVec3{
		f64(resting_point.x),
		f64(resting_point.y),
		f64(resting_point.z),
	}
	kineffi.JPH_BodyInterface_SetPositionAndRotation(
		body_interface,
		coll.body_id,
		&rest,
		&rotation,
		.DontActivate,
	)
}

Physics_Set_Character_Capsule_Dynamic :: proc(
	service: ^Physics,
	coll: ^classes.CollisionController,
	simulated: bool,
) -> bool {
	if service == nil || coll == nil {return false}
	coll.ragdoll = simulated
	if !coll.body_created || service.system.body_interface == nil {return false}
	if coll.body_id == kineffi.JPH_BODY_ID_INVALID {return false}
	motion: kineffi.JPH_MotionType = simulated ? .Dynamic : .Kinematic
	kineffi.JPH_BodyInterface_SetMotionType(
		service.system.body_interface,
		coll.body_id,
		motion,
		.Activate,
	)


	if simulated {
		zero := kineffi.JPH_Vec3{0, 0, 0}
		kineffi.JPH_BodyInterface_SetLinearVelocity(
			service.system.body_interface,
			coll.body_id,
			&zero,
		)
		kineffi.JPH_BodyInterface_SetAngularVelocity(
			service.system.body_interface,
			coll.body_id,
			&zero,
		)
	}
	return true
}


Physics_Start_Character_Ragdoll :: proc(
	service: ^Physics,
	coll: ^classes.CollisionController,
	root: ^classes.Part,
) -> bool {
	if service == nil || coll == nil || root == nil || !service.initialized {return false}
	coll.ragdoll = true
	Physics_Ensure_Character_Capsule(
		service,
		coll,
		root,
		datatypes.Vector3{root.cframe.x, root.cframe.y, root.cframe.z},
	)
	if !coll.body_created {return false}
	return Physics_Set_Character_Capsule_Dynamic(service, coll, true)
}


Physics_Get_Character_Capsule_CFrame :: proc(
	service: ^Physics,
	coll: ^classes.CollisionController,
) -> (
	datatypes.CFrame,
	bool,
) {
	if service == nil ||
	   coll == nil ||
	   !coll.body_created ||
	   service.system.body_interface == nil ||
	   coll.body_id == kineffi.JPH_BODY_ID_INVALID {
		return datatypes.CFrame_Identity, false
	}
	position: kineffi.JPH_RVec3
	rotation: kineffi.JPH_Quat
	kineffi.JPH_BodyInterface_GetPositionAndRotation(
		service.system.body_interface,
		coll.body_id,
		&position,
		&rotation,
	)
	cf := physics_cframe_from_quaternion(rotation)
	cf.x = f32(position.x)
	cf.y = f32(position.y)
	cf.z = f32(position.z)
	if !physics_valid_cframe(cf) {return datatypes.CFrame_Identity, false}
	return cf, true
}

Physics_Destroy_Character_Capsule :: proc(service: ^Physics, coll: ^classes.CollisionController) {
	if service == nil || coll == nil {return}
	if coll.body_created {
		if service.system.body_interface != nil && coll.body_id != kineffi.JPH_BODY_ID_INVALID {
			kineffi.JPH_BodyInterface_RemoveAndDestroyBody(
				service.system.body_interface,
				coll.body_id,
			)
		}
		delete_key(&service.body_to_part, coll.body_id)
		coll.body_created = false
		coll.body_id = kineffi.JPH_BODY_ID_INVALID
	}
	if coll.shape != nil {
		kineffi.JPH_Shape_Destroy(coll.shape)
		coll.shape = nil
	}
}


Physics_Fill_Candidate_Bodies :: proc(
	service: ^Physics,
	exclude: kineffi.JPH_BodyID,
	out: ^[dynamic]kineffi.JPH_BodyID,
	static_only := false,
) {
	physics_reset_scratch_ids(out)
	if service == nil {return}


	if service.terrain_valid &&
	   service.terrain_body != kineffi.JPH_BODY_ID_INVALID &&
	   service.terrain_body != exclude {
		append(out, service.terrain_body)
	}
	for body in service.bodies {
		if body.body_id == exclude || body.body_id == kineffi.JPH_BODY_ID_INVALID {continue}
		part := cast(^classes.Part)body.object
		if part == nil || !part.can_collide {continue}
		// A static-only pass drops everything the solver moves. The character
		// walks with one, so an unanchored Part cannot stop the character dead
		// in front of it: the capsule drives through it and the contact solver
		// shoves it aside instead.
		if static_only && !body.anchored {continue}
		append(out, body.body_id)
	}
}

physics_fire_touched :: proc(
	service: ^Physics,
	body_id: kineffi.JPH_BodyID,
	owner: ^classes.Part,
) {
	if service == nil || body_id == kineffi.JPH_BODY_ID_INVALID || owner == nil {return}
	part := physics_part_for_body(service, body_id)
	if part == nil || part == owner {return}
	L: ^vm.State
	if service.data_model != nil &&
	   service.data_model.registry != nil &&
	   service.data_model.registry.vm_state != nil &&
	   service.data_model.registry.vm_state.L != nil {
		L = service.data_model.registry.vm_state.L
	}
	if L == nil {return}
	part_touched(part, owner, L)
	part_touched(owner, part, L)
}


physics_character_sweep :: proc(
	service: ^Physics,
	coll: ^classes.CollisionController,
	origin: datatypes.Vector3,
	displacement: datatypes.Vector3,
	static_only := false,
) -> (
	position: datatypes.Vector3,
	normal: datatypes.Vector3,
	body_id: kineffi.JPH_BodyID,
	fraction: f32,
	hit: bool,
) {
	if service == nil || coll == nil || !coll.body_created || coll.shape == nil {return}
	if datatypes.Vec3_Magnitude_Squared(displacement) <= 0 {return}


	candidates := &service.scratch_sweep_candidates
	Physics_Fill_Candidate_Bodies(service, coll.body_id, candidates, static_only)
	if len(candidates^) == 0 {return}
	native, did_hit := jolt.System_Cast_Shape(
		&service.system,
		kineffi.JPH_RVec3{f64(origin.x), f64(origin.y), f64(origin.z)},
		kineffi.JPH_Vec3{displacement.x, displacement.y, displacement.z},
		coll.shape,
		candidates[:],
		.Include,
	)
	if !did_hit {return}
	position = datatypes.Vector3 {
		f32(native.position.x),
		f32(native.position.y),
		f32(native.position.z),
	}
	normal = datatypes.Vector3{native.normal.x, native.normal.y, native.normal.z}
	body_id = native.bodyID
	fraction = native.fraction
	hit = true
	return
}
