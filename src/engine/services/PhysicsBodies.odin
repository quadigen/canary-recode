package services

import "core:math"
import "core:strings"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import jolt "../physics"
import kineffi "../bindings"
import vm "../vm"

physics_finite_f32 :: proc(value: f32) -> bool {
	return value == value && value > -1.0e20 && value < 1.0e20
}

physics_valid_cframe :: proc(cf: datatypes.CFrame) -> bool {
	return physics_finite_f32(cf.x) && physics_finite_f32(cf.y) && physics_finite_f32(cf.z) &&
		physics_finite_f32(cf.r00) && physics_finite_f32(cf.r01) && physics_finite_f32(cf.r02) &&
		physics_finite_f32(cf.r10) && physics_finite_f32(cf.r11) && physics_finite_f32(cf.r12) &&
		physics_finite_f32(cf.r20) && physics_finite_f32(cf.r21) && physics_finite_f32(cf.r22)
}

physics_quaternion_from_cframe :: proc(cf: datatypes.CFrame) -> kineffi.JPH_Quat {
	trace := cf.r00 + cf.r11 + cf.r22
	result: kineffi.JPH_Quat
	if trace > 0 {
		s := math.sqrt(trace+1.0)*2.0
		result = kineffi.JPH_Quat{(cf.r21-cf.r12)/s, (cf.r02-cf.r20)/s, (cf.r10-cf.r01)/s, 0.25*s}
	} else if cf.r00 > cf.r11 && cf.r00 > cf.r22 {
		s := math.sqrt(1.0+cf.r00-cf.r11-cf.r22)*2.0
		result = kineffi.JPH_Quat{0.25*s, (cf.r01+cf.r10)/s, (cf.r02+cf.r20)/s, (cf.r21-cf.r12)/s}
	} else if cf.r11 > cf.r22 {
		s := math.sqrt(1.0+cf.r11-cf.r00-cf.r22)*2.0
		result = kineffi.JPH_Quat{(cf.r01+cf.r10)/s, 0.25*s, (cf.r12+cf.r21)/s, (cf.r02-cf.r20)/s}
	} else {
		s := math.sqrt(1.0+cf.r22-cf.r00-cf.r11)*2.0
		result = kineffi.JPH_Quat{(cf.r02+cf.r20)/s, (cf.r12+cf.r21)/s, 0.25*s, (cf.r10-cf.r01)/s}
	}
	return result
}

physics_shape_for_part :: proc(
	service: ^Physics,
	part: ^classes.Part,
) -> kineffi.JPH_ShapeRef {
	half := datatypes.Vector3{max(part.size.x*0.5, 0.001), max(part.size.y*0.5, 0.001), max(part.size.z*0.5, 0.001)}
	scale := datatypes.Vector3{half.x, half.y, half.z}

	if classes.Is_A(&part.object, "MeshPart") {
		if shape := physics_meshpart_shape(service, cast(^classes.MeshPart)part, scale); shape != nil {
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

physics_wedge_verts := [6]datatypes.Vector3{
	{ 1, -1, -1},
	{ 1, -1,  1},
	{-1,  1, -1},
	{-1, -1, -1},
	{-1,  1,  1},
	{-1, -1,  1},
}

physics_corner_wedge_verts := [7]datatypes.Vector3{
	{-1, -1, 1},
	{-1, -1, -1},
	{ 1, -1, 1},
	{ 1, -1, -1},
	{-1,  1, 1},
	{-1,  1, -1},
	{ 1,  1, 1},
}

physics_pyramid_verts := [5]datatypes.Vector3{
	{-1, -1, 1},
	{-1, -1, -1},
	{ 1, -1, 1},
	{ 1, -1, -1},
	{ 0,  1,  0},
}

physics_triangle_wedge_verts := [5]datatypes.Vector3{
	{-1, -1, 1},
	{-1, -1, -1},
	{ 1, -1, 1},
	{ 1, -1, -1},
	{-1,  1,  1},
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
		points[i] = kineffi.JPH_Vec3{
			vert.x * scale.x,
			vert.y * scale.y,
			vert.z * scale.z,
		}
	}
	return kineffi.JPH_ConvexHullShape_Create(raw_data(points), u32(len(points)), 0)
}

physics_cone_shape :: proc(scale: datatypes.Vector3) -> kineffi.JPH_ShapeRef {
	SEGMENTS :: 16
	points := make([dynamic]kineffi.JPH_Vec3, 0, SEGMENTS+1)
	defer delete(points)
	for i in 0 ..< SEGMENTS {
		angle := f32(i) * 2.0 * math.PI / SEGMENTS
		append(&points, kineffi.JPH_Vec3{
			math.cos(angle) * scale.x,
			-scale.y,
			math.sin(angle) * scale.z,
		})
	}
	append(&points, kineffi.JPH_Vec3{0, scale.y, 0})
	return kineffi.JPH_ConvexHullShape_Create(raw_data(points), u32(len(points)), 0)
}

physics_capsule_shape :: proc(size: datatypes.Vector3) -> kineffi.JPH_ShapeRef {
	radius := max(min(size.x, size.z) * 0.5, 0.001)
	half_height := max(size.y*0.5 - radius, 0)
	return kineffi.JPH_CapsuleShape_Create(half_height, radius, 0)
}

physics_meshpart_shape :: proc(
	service: ^Physics,
	mesh_part: ^classes.MeshPart,
	scale: datatypes.Vector3,
) -> kineffi.JPH_ShapeRef {
	if classes.Is_A(&mesh_part.object, "MeshPart") && mesh_part.mesh_id != "" {
		#partial switch mesh_part.collision_fidelity {
		case .Box:
			half := datatypes.Vector3{max(mesh_part.size.x*0.5, 0.001), max(mesh_part.size.y*0.5, 0.001), max(mesh_part.size.z*0.5, 0.001)}
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
) -> ([]kineffi.JPH_Vec3, [dynamic]u32, bool) {
	path := mesh_part.mesh_id
	if strings.has_prefix(path, "file://") {
		path = path[len("file://"):]
	}
	c_path := strings.clone_to_cstring(path)
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
	positions := make([]f32, vertex_count*3)
	defer delete(positions)
	indices := make([]u32, index_count)
	defer delete(indices)
	if kineffi.Kine_Filament_CopyMeshDataPositions(data, raw_data(positions), i32(len(positions))) == 0 ||
	   kineffi.Kine_Filament_CopyMeshDataIndices(data, raw_data(indices), i32(len(indices))) == 0 {
		return nil, nil, false
	}
	verts := make([]kineffi.JPH_Vec3, vertex_count)
	for i in 0 ..< vertex_count {
		verts[i] = kineffi.JPH_Vec3{positions[i*3], positions[i*3+1], positions[i*3+2]}
	}
	idx := make([dynamic]u32, index_count)
	copy(idx[:], indices)
	return verts, idx, true
}

physics_mesh_hull_shape :: proc(
	mesh_part: ^classes.MeshPart,
	scale: datatypes.Vector3,
) -> kineffi.JPH_ShapeRef {
	verts, _, ok := physics_load_mesh_data(mesh_part)
	if !ok {
		return nil
	}
	defer delete(verts)
	for i in 0 ..< len(verts) {
		verts[i] = kineffi.JPH_Vec3{
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

physics_mesh_pcd_shape :: proc(
	service: ^Physics,
	mesh_part: ^classes.MeshPart,
	scale: datatypes.Vector3,
) -> kineffi.JPH_ShapeRef {
	key := Physics_Shape_Cache_Key{
		mesh_id = strings.clone(mesh_part.mesh_id),
		size = mesh_part.size,
	}
	if service != nil && service.pcd_cache != nil {
		if cached, ok := service.pcd_cache[key]; ok {
			delete(key.mesh_id)
			kineffi.JPH_Shape_AddRef(cached)
			return cached
		}
	}
	verts, idx, ok := physics_load_mesh_data(mesh_part)
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
		if classes.Is_A(node, "CharacterModel") {return true}
		node = node.parent
	}
	return false
}

physics_remote_owned :: proc(service: ^Physics, part: ^classes.Part) -> bool {
	if service == nil || service.data_model == nil || part == nil {return false}
	replicator := cast(^ReplicatorService)DataModel_Get_Service(service.data_model, "ReplicatorService")
	if replicator == nil || replicator.mode == .Stopped {return false}
	entity := replication_entity(replicator, &part.object)
	if entity == nil || entity.owner_id == 0 {return false}
	if replicator.mode == .Server {return true}
	players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")
	if players == nil || players.local_player == nil {return true}
	return entity.owner_id != players.local_player.user_id
}

physics_create_body :: proc(service: ^Physics, part: ^classes.Part) -> (Physics_Body, bool) {
	if part == nil {return Physics_Body{}, false}
	if part_in_character_model(part) {return Physics_Body{}, false}

	shape := physics_shape_for_part(service, part)
	if shape == nil {
		return Physics_Body{}, false
	}
	defer kineffi.JPH_Shape_Destroy(shape)

	position := kineffi.JPH_RVec3{
		f64(part.cframe.x),
		f64(part.cframe.y),
		f64(part.cframe.z),
	}

	rotation := physics_quaternion_from_cframe(part.cframe)

	remote := physics_remote_owned(service, part)

	static := part.anchored || remote

	motion_type: kineffi.JPH_MotionType =
		static ? .Static : .Dynamic

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

	kineffi.JPH_BodyCreationSettings_SetFriction(
		settings,
		properties.friction,
	)

	kineffi.JPH_BodyCreationSettings_SetRestitution(
		settings,
		properties.restitution,
	)

	body := kineffi.JPH_BodyInterface_CreateBody(
		service.system.body_interface,
		settings,
	)

	if body == nil {
		return Physics_Body{}, false
	}

	body_id := kineffi.JPH_Body_GetID(body)

	if body_id == kineffi.JPH_BODY_ID_INVALID {
		kineffi.JPH_BodyInterface_DestroyBody(service.system.body_interface, body)
		return Physics_Body{}, false
	}

	activation: kineffi.JPH_ActivationMode =
		static ? .DontActivate : .Activate

	kineffi.JPH_BodyInterface_AddBody(
		service.system.body_interface,
		body_id,
		activation,
	)

	service.body_to_part[body_id] = part

	mesh_id := ""

	if classes.Is_A(&part.object, "MeshPart") {
		mesh_id = strings.clone(
			(cast(^classes.MeshPart)part).mesh_id,
		)
	}

	return Physics_Body{
		&part.object,
		body_id,
		part.size,
		part.shape,
		part.anchored,
		part.cframe,
		mesh_id,
		mesh_part_collision_fidelity(part),
	}, true
}

mesh_part_collision_fidelity :: proc(part: ^classes.Part) -> enums.CollisionFidelity {
	if classes.Is_A(&part.object, "MeshPart") {
		return (cast(^classes.MeshPart)part).collision_fidelity
	}
	return enums.CollisionFidelity.Default
}

physics_refresh_part :: proc(service: ^Physics, part: ^classes.Part) {
	if service == nil || !service.initialized || part == nil {return}
	body_index := physics_find_body_index(service, &part.object)
	if body_index < 0 {return}
	body := service.bodies[body_index]
	physics_destroy_body(service, body)
	new_body, ok := physics_create_body(service, part)
	if ok {
		service.bodies[body_index] = new_body
	} else {
		ordered_remove(&service.bodies, body_index)
	}
	kineffi.JPH_PhysicsSystem_OptimizeBroadPhase(service.system.handle)
}

physics_destroy_body :: proc(service: ^Physics, body: Physics_Body) {
	if service.system.body_interface != nil && body.body_id != kineffi.JPH_BODY_ID_INVALID {
		kineffi.JPH_BodyInterface_RemoveAndDestroyBody(service.system.body_interface, body.body_id)
	}
	delete_key(&service.body_to_part, body.body_id)
	delete(body.mesh_id)
}

physics_part_for_body :: proc(service: ^Physics, body_id: kineffi.JPH_BodyID) -> ^classes.Part {
	if service == nil {return nil}
	part, ok := service.body_to_part[body_id]
	if !ok {return nil}
	return part
}

physics_collect_parts :: proc(object: ^classes.Object, parts: ^[dynamic]^classes.Part) {
	if object == nil { return }
	for child in object.children {
		if child == nil || child.destroyed { continue }
		if classes.Is_A(child, "Part") { append(parts, cast(^classes.Part)child) }
		physics_collect_parts(child, parts)
	}
}

physics_contains_part :: proc(parts: []^classes.Part, object: ^classes.Object) -> bool {
	for part in parts { if &part.object == object { return true } }
	return false
}

physics_find_body_index :: proc(service: ^Physics, object: ^classes.Object) -> int {
	for body, i in service.bodies { if body.object == object { return i } }
	return -1
}

Physics_Synchronize :: proc(service: ^Physics, workspace: ^classes.Object) {
	if service == nil || !service.initialized || workspace == nil { return }
	parts: [dynamic]^classes.Part
	defer delete(parts)
	physics_collect_parts(workspace, &parts)
	i := len(service.bodies)
	topology_changed := false
	for i > 0 {
		i -= 1
		if !physics_contains_part(parts[:], service.bodies[i].object) {
			physics_destroy_body(service, service.bodies[i])
			ordered_remove(&service.bodies, i)
			topology_changed = true
		}
	}
	for part in parts {
		body_index := physics_find_body_index(service, &part.object)
		if body_index < 0 {
			body, ok := physics_create_body(service, part)
			if ok {
				append(&service.bodies, body)
				topology_changed = true
			}
			continue
		}
		body := &service.bodies[body_index]
		mesh_id := ""
		if classes.Is_A(&part.object, "MeshPart") {
			mesh_id = (cast(^classes.MeshPart)part).mesh_id
		}
		if body.size != part.size || body.shape != part.shape || body.anchored != part.anchored || body.mesh_id != mesh_id || body.collision_fidelity != mesh_part_collision_fidelity(part) {
			physics_destroy_body(service, body^)
			new_body, ok := physics_create_body(service, part)
			if ok {
				body^ = new_body
			} else {
				ordered_remove(&service.bodies, body_index)
			}
			topology_changed = true
			continue
		}
		if body.last_cframe != part.cframe {
			position := kineffi.JPH_RVec3{f64(part.cframe.x), f64(part.cframe.y), f64(part.cframe.z)}
			activation: kineffi.JPH_ActivationMode = part.anchored ? .DontActivate : .Activate
			if body.last_cframe.r00 == part.cframe.r00 &&
			   body.last_cframe.r01 == part.cframe.r01 &&
			   body.last_cframe.r02 == part.cframe.r02 &&
			   body.last_cframe.r10 == part.cframe.r10 &&
			   body.last_cframe.r11 == part.cframe.r11 &&
			   body.last_cframe.r12 == part.cframe.r12 &&
			   body.last_cframe.r20 == part.cframe.r20 &&
			   body.last_cframe.r21 == part.cframe.r21 &&
			   body.last_cframe.r22 == part.cframe.r22 {
				kineffi.JPH_BodyInterface_SetPosition(
					service.system.body_interface,
					body.body_id,
					&position,
					activation,
				)
			} else {
				rotation := physics_quaternion_from_cframe(part.cframe)
				kineffi.JPH_BodyInterface_SetPositionAndRotation(
					service.system.body_interface,
					body.body_id,
					&position,
					&rotation,
					activation,
				)
			}
			body.last_cframe = part.cframe
		}
	}
	if topology_changed {
		kineffi.JPH_PhysicsSystem_OptimizeBroadPhase(service.system.handle)
	}
}

physics_capsule_size_from_root :: proc(root: ^classes.Part) -> (radius, half_height: f32) {
	radius = max(root.size.x, root.size.z) / 2 * 0.55
	half_height = root.size.y / 2 - radius
	if radius <= 0.001 {radius = 0.001}
	if half_height < 0.01 {half_height = 0.01}
	return
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
	settings := kineffi.JPH_BodyCreationSettings_Create3(coll.shape, &pos, &identity, .Kinematic, jolt.OBJECT_LAYER_MOVING)
	if settings == nil {return}
	defer kineffi.JPH_BodyCreationSettings_Destroy(settings)
	body := kineffi.JPH_BodyInterface_CreateBody(service.system.body_interface, settings)
	if body == nil {return}
	body_id := kineffi.JPH_Body_GetID(body)
	if body_id == kineffi.JPH_BODY_ID_INVALID {
		kineffi.JPH_BodyInterface_DestroyBody(service.system.body_interface, body)
		return
	}
	kineffi.JPH_BodyInterface_AddBody(service.system.body_interface, body_id, .DontActivate)
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
	if service == nil || coll == nil || !coll.body_created || service.system.body_interface == nil {return}
	cf := datatypes.CFrame_FromEulerAnglesYXZ(0, math.to_radians(yaw), 0)
	cf.x = position.x
	cf.y = position.y
	cf.z = position.z
	rotation := physics_quaternion_from_cframe(cf)
	pos := kineffi.JPH_RVec3{f64(position.x), f64(position.y), f64(position.z)}
	kineffi.JPH_BodyInterface_SetPositionAndRotation(service.system.body_interface, coll.body_id, &pos, &rotation, .DontActivate)
}

Physics_Destroy_Character_Capsule :: proc(service: ^Physics, coll: ^classes.CollisionController) {
	if service == nil || coll == nil {return}
	if coll.body_created {
		if service.system.body_interface != nil && coll.body_id != kineffi.JPH_BODY_ID_INVALID {
			kineffi.JPH_BodyInterface_RemoveAndDestroyBody(service.system.body_interface, coll.body_id)
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

Physics_Candidate_Bodies :: proc(service: ^Physics, exclude: kineffi.JPH_BodyID) -> [dynamic]kineffi.JPH_BodyID {
	result: [dynamic]kineffi.JPH_BodyID
	if service == nil {return result}
	for body in service.bodies {
		if body.body_id == exclude || body.body_id == kineffi.JPH_BODY_ID_INVALID {continue}
		append(&result, body.body_id)
	}
	return result
}

physics_fire_touched :: proc(service: ^Physics, body_id: kineffi.JPH_BodyID, owner: ^classes.Part) {
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

// Sweeps the character capsule from `origin` along `displacement` against the
// scene's collidable bodies, excluding the character's own capsule. The reported
// `position` is where the capsule centre ends up when it first touches its target.
physics_character_sweep :: proc(
	service: ^Physics,
	coll: ^classes.CollisionController,
	origin: datatypes.Vector3,
	displacement: datatypes.Vector3,
) -> (
	position: datatypes.Vector3,
	normal: datatypes.Vector3,
	body_id: kineffi.JPH_BodyID,
	fraction: f32,
	hit: bool,
) {
	if service == nil || coll == nil || !coll.body_created || coll.shape == nil {return}
	if datatypes.Vec3_Magnitude_Squared(displacement) <= 0 {return}
	candidates := Physics_Candidate_Bodies(service, coll.body_id)
	defer delete(candidates)
	if len(candidates) == 0 {return}
	native, did_hit := jolt.System_Cast_Shape(
		&service.system,
		kineffi.JPH_RVec3{f64(origin.x), f64(origin.y), f64(origin.z)},
		kineffi.JPH_Vec3{displacement.x, displacement.y, displacement.z},
		coll.shape,
		candidates[:],
		.Include,
	)
	if !did_hit {return}
	position = datatypes.Vector3{f32(native.position.x), f32(native.position.y), f32(native.position.z)}
	normal = datatypes.Vector3{native.normal.x, native.normal.y, native.normal.z}
	body_id = native.bodyID
	fraction = native.fraction
	hit = true
	return
}
