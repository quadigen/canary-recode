package services

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import vm "../vm"
import "core:math"
import "core:strings"


solver_find_rig :: proc(node: ^classes.Object) -> ^classes.MeshPart {
	if node == nil || node.destroyed {return nil}
	if classes.Is_A_Class(node, &classes.MeshPart_Class) {
		mesh := cast(^classes.MeshPart)node
		if mesh.native_mesh != nil &&
		   kineffi.Kine_Filament_GetMeshBoneCount(mesh.native_mesh) > 0 {
			return mesh
		}
	}
	for child in node.children {
		if mesh := solver_find_rig(child); mesh != nil {return mesh}
	}
	return nil
}

solver_rig :: proc(
	solver: ^classes.CharacterPhysicsSolver,
	controller: ^classes.CharacterController,
) -> ^classes.MeshPart {
	if controller == nil || controller.parent == nil {return nil}
	model := controller.parent
	candidate := classes.CharacterPhysicsSolver_Live_Rig(solver)
	if solver.rig_mesh != nil {
		if candidate == nil ||
		   !classes.Is_Descendant_Of(candidate, model) ||
		   !classes.Is_A_Class(candidate, &classes.MeshPart_Class) {
			solver.rig_mesh = nil
			classes.CharacterPhysicsSolver_Clear_Rig(solver)
		} else {
			return cast(^classes.MeshPart)candidate
		}
	}
	if solver.rig_name != "" {
		named := classes.CharacterPhysicsSolver_Find_Named_Rig(model, solver.rig_name)
		if named != nil && classes.Is_A_Class(named, &classes.MeshPart_Class) {
			return cast(^classes.MeshPart)named
		}
		return nil
	}
	return solver_find_rig(model)
}

solver_calibrate :: proc(
	solver: ^classes.CharacterPhysicsSolver,
	mesh: ^classes.MeshPart,
) -> bool {
	if mesh == nil || mesh.native_mesh == nil {return false}
	if mesh.native_mesh == solver.cached_mesh &&
	   mesh.size == solver.calibrated_size &&
	   len(solver.bind_local) > 0 {return true}
	classes.CharacterPhysicsSolver_Clear_Rig(solver)
	native := mesh.native_mesh
	locals := classes.Animation_MeshPart_Bone_Transforms(mesh)
	if len(locals) == 0 {return false}
	n := len(locals)
	solver.bind_local = make([][16]f32, n)
	solver.bind_global = make([][16]f32, n)


	for i in 0 ..< n {
		if !kineffi.Kine_Filament_CopyMeshBoneBindTransform(
			native,
			i32(i),
			&solver.bind_local[i][0],
		) {
			classes.CharacterPhysicsSolver_Clear_Rig(solver)
			return false
		}
	}
	states := make([]u8, n)
	defer delete(states)
	for i in 0 ..< n {
		if !classes.Animation_Eval_Bone_Global(
			i,
			solver.bind_local,
			solver.bind_global,
			states,
			native,
		) {
			classes.CharacterPhysicsSolver_Clear_Rig(solver)
			return false
		}
	}


	for i in 0 ..< n {
		name_ptr := kineffi.Kine_Filament_GetMeshBoneName(native, i32(i))
		if name_ptr == nil {continue}
		name := string(name_ptr)
		if strings.contains(name, "LeftUpLeg") {solver.leg_bones[0][0] = i32(i)}
		if strings.contains(name, "LeftLeg") && !strings.contains(name, "LeftUpLeg") {
			solver.leg_bones[0][1] = i32(i)
		}
		if strings.contains(name, "LeftFoot") {solver.leg_bones[0][2] = i32(i)}
		if strings.contains(name, "RightUpLeg") {solver.leg_bones[1][0] = i32(i)}
		if strings.contains(name, "RightLeg") && !strings.contains(name, "RightUpLeg") {
			solver.leg_bones[1][1] = i32(i)
		}
		if strings.contains(name, "RightFoot") {solver.leg_bones[1][2] = i32(i)}
		if strings.contains(name, "LeftArm") &&
		   !strings.contains(name, "LeftForeArm") {solver.arm_bones[0][0] = i32(i)}
		if strings.contains(name, "LeftForeArm") {solver.arm_bones[0][1] = i32(i)}
		if strings.contains(name, "LeftHand_") || strings.has_suffix(name, "LeftHand") {
			solver.arm_bones[0][2] = i32(i)
		}
		if strings.contains(name, "RightArm") &&
		   !strings.contains(name, "RightForeArm") {solver.arm_bones[1][0] = i32(i)}
		if strings.contains(name, "RightForeArm") {solver.arm_bones[1][1] = i32(i)}
		if strings.contains(name, "RightHand_") || strings.has_suffix(name, "RightHand") {
			solver.arm_bones[1][2] = i32(i)
		}
		if strings.contains(name, "Neck") {solver.neck_bone = i32(i)}
		if strings.contains(name, "Head") &&
		   !strings.contains(name, "HeadTop") {solver.head_bone = i32(i)}
		if strings.contains(name, "Spine2") {solver.spine_upper_bone = i32(i)}
		if strings.contains(name, "Hips") {solver.pelvis_bone = i32(i)}
		if strings.contains(name, "Spine") &&
		   !strings.contains(name, "Spine1") &&
		   !strings.contains(name, "Spine2") {
			solver.spine_bone = i32(i)
		}
	}
	valid := true
	for leg in solver.leg_bones {
		for index in leg {if index < 0 || int(index) >= n {valid = false}}
	}
	if !valid {
		classes.CharacterPhysicsSolver_Clear_Rig(solver)
		solver.status = "MissingLegBones"
		return false
	}

	hip := solver_world_from_skeleton(mesh, solver_rest_position(solver, solver.leg_bones[0][0]))
	knee := solver_world_from_skeleton(mesh, solver_rest_position(solver, solver.leg_bones[0][1]))
	ankle := solver_world_from_skeleton(mesh, solver_rest_position(solver, solver.leg_bones[0][2]))
	solver.leg_length = solver_len(solver_sub(hip, knee)) + solver_len(solver_sub(knee, ankle))
	center, extent: [3]f32
	if kineffi.Kine_Filament_GetMeshBounds(native, &center[0], &extent[0]) {
		ankle_local := solver_rest_position(solver, solver.leg_bones[0][2])
		sole := f64(center[1] - extent[1])
		solver.sole_height = clamp(
			(ankle_local.y - sole) * mesh.size.y * 0.5,
			0.03,
			solver.leg_length * 0.16,
		)
	}
	solver.calibrated_size = mesh.size
	solver.cached_mesh = native
	solver.status = "Ready"
	return true
}

solver_len :: proc(v: datatypes.Vector3) -> f64 {
	return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
}
solver_add :: proc(a, b: datatypes.Vector3) -> datatypes.Vector3 {
	return {a.x + b.x, a.y + b.y, a.z + b.z}
}
solver_sub :: proc(a, b: datatypes.Vector3) -> datatypes.Vector3 {
	return {a.x - b.x, a.y - b.y, a.z - b.z}
}
solver_mul :: proc(v: datatypes.Vector3, s: f64) -> datatypes.Vector3 {
	return {v.x * s, v.y * s, v.z * s}
}
solver_normalize :: proc(v: datatypes.Vector3) -> datatypes.Vector3 {
	m := solver_len(v)
	return m > 0.00001 ? solver_mul(v, 1 / m) : datatypes.Vector3{0, 1, 0}
}
solver_dot :: proc(a, b: datatypes.Vector3) -> f64 {return a.x * b.x + a.y * b.y + a.z * b.z}
solver_cross :: proc(a, b: datatypes.Vector3) -> datatypes.Vector3 {
	return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}
}
solver_cf_pos :: proc(cf: datatypes.CFrame) -> datatypes.Vector3 {
	return {cf.x, cf.y, cf.z}
}
solver_rest_position :: proc(
	solver: ^classes.CharacterPhysicsSolver,
	index: i32,
) -> datatypes.Vector3 {
	if index < 0 || int(index) >= len(solver.bind_global) {return {}}
	return solver_cf_pos(classes.Animation_Matrix_To_CFrame(solver.bind_global[int(index)]))
}

solver_world_from_skeleton :: proc(
	mesh: ^classes.MeshPart,
	v: datatypes.Vector3,
) -> datatypes.Vector3 {
	return datatypes.CFrame_PointToWorldSpace(
		mesh.cframe,
		{v.x * mesh.size.x * 0.5, v.y * mesh.size.y * 0.5, v.z * mesh.size.z * 0.5},
	)
}
solver_skeleton_from_world :: proc(
	mesh: ^classes.MeshPart,
	v: datatypes.Vector3,
) -> datatypes.Vector3 {
	local := datatypes.CFrame_PointToObjectSpace(mesh.cframe, v)
	return {
		local.x / max(mesh.size.x * 0.5, 0.00001),
		local.y / max(mesh.size.y * 0.5, 0.00001),
		local.z / max(mesh.size.z * 0.5, 0.00001),
	}
}

solver_rotation_between :: proc(
	start, finish: datatypes.Vector3,
	weight: f64 = 1,
) -> datatypes.CFrame {
	a, b := solver_normalize(start), solver_normalize(finish)
	cross := solver_cross(a, b)
	d := clamp(solver_dot(a, b), -1.0, 1.0)
	magnitude := solver_len(cross)
	if magnitude < 0.00001 {
		if d > 0 {return datatypes.CFrame_Identity}
		cross = solver_cross(a, {1, 0, 0})
		if solver_len(cross) < 0.00001 {cross = solver_cross(a, {0, 0, 1})}
		return datatypes.CFrame_FromAxisAngle(solver_normalize(cross), math.PI * weight)
	}
	return datatypes.CFrame_FromAxisAngle(
		solver_mul(cross, 1 / magnitude),
		math.atan2(magnitude, d) * weight,
	)
}

solver_rotate_pivot :: proc(
	rotation: datatypes.CFrame,
	pivot: datatypes.Vector3,
	original: datatypes.CFrame,
) -> datatypes.CFrame {
	translation := datatypes.CFrame_New_Position(pivot)
	reverse := datatypes.CFrame_New_Position(solver_mul(pivot, -1))
	return datatypes.CFrame_Mul_CFrame(
		datatypes.CFrame_Mul_CFrame(datatypes.CFrame_Mul_CFrame(translation, rotation), reverse),
		original,
	)
}


solver_solve_leg :: proc(
	solver: ^classes.CharacterPhysicsSolver,
	mesh: ^classes.MeshPart,
	leg_index: int,
	target_world: datatypes.Vector3,
	posed: [][16]f32,
) {
	ids := solver.leg_bones[leg_index]
	upper, lower, ankle := int(ids[0]), int(ids[1]), int(ids[2])
	n := len(solver.bind_local)
	if upper < 0 || lower < 0 || ankle < 0 || upper >= n || lower >= n || ankle >= n {return}
	hip := solver_rest_position(solver, ids[0])
	knee := solver_rest_position(solver, ids[1])
	foot := solver_rest_position(solver, ids[2])
	l1, l2 := solver_len(solver_sub(knee, hip)), solver_len(solver_sub(foot, knee))
	if l1 < 0.0001 || l2 < 0.0001 {return}
	goal := solver_skeleton_from_world(mesh, target_world)
	delta := solver_sub(goal, hip)
	d := solver_len(delta)
	if d < 0.0001 {return}
	dir := solver_mul(delta, 1 / d)
	reach := clamp(d, math.abs(l1 - l2) + 0.001, l1 + l2 - 0.001)
	goal = solver_add(hip, solver_mul(dir, reach))
	along := (l1 * l1 - l2 * l2 + reach * reach) / (2 * reach)
	spread := math.sqrt(max(l1 * l1 - along * along, 0.0))
	old_knee := solver_sub(knee, hip)
	pole := solver_sub(old_knee, solver_mul(dir, solver_dot(old_knee, dir)))
	if solver_len(pole) < 0.0001 {pole = solver_cross(dir, {0, 0, 1})}
	if solver_len(pole) < 0.0001 {pole = solver_cross(dir, {1, 0, 0})}
	new_knee := solver_add(
		solver_add(hip, solver_mul(dir, along)),
		solver_mul(solver_normalize(pole), spread),
	)
	start_upper := solver_sub(knee, hip)
	new_upper := solver_sub(new_knee, hip)
	delta_upper := solver_rotation_between(start_upper, new_upper, f64(solver.pose_blend))
	parent_idx := kineffi.Kine_Filament_GetMeshBoneParent(mesh.native_mesh, ids[0])
	parent_global := datatypes.CFrame_Identity
	if parent_idx >= 0 && int(parent_idx) < len(solver.bind_global) {
		parent_global = classes.Animation_Matrix_To_CFrame(solver.bind_global[int(parent_idx)])
	}
	base_upper := classes.Animation_Matrix_To_CFrame(solver.bind_global[upper])
	moved_upper := solver_rotate_pivot(delta_upper, hip, base_upper)
	upper_local := datatypes.CFrame_Mul_CFrame(
		datatypes.CFrame_Inverse(parent_global),
		moved_upper,
	)
	posed[upper] = classes.Animation_CFrame_To_Matrix(upper_local)

	base_lower_local := classes.Animation_Matrix_To_CFrame(solver.bind_local[lower])
	moved_lower := datatypes.CFrame_Mul_CFrame(moved_upper, base_lower_local)
	knee_pos := solver_cf_pos(moved_lower)
	old_shin := datatypes.CFrame_PointToWorldSpace(delta_upper, solver_sub(foot, knee))

	shin_goal := solver_sub(goal, knee_pos)
	delta_lower := solver_rotation_between(old_shin, shin_goal, f64(solver.pose_blend))
	moved_lower = solver_rotate_pivot(delta_lower, knee_pos, moved_lower)
	posed[lower] = classes.Animation_CFrame_To_Matrix(
		datatypes.CFrame_Mul_CFrame(datatypes.CFrame_Inverse(moved_upper), moved_lower),
	)
}

solver_ground_target :: proc(
	physics: ^Physics,
	model: ^classes.Object,
	world: datatypes.Vector3,
	height: f64,
	sole_height: f64 = 0.07,
) -> (
	datatypes.Vector3,
	datatypes.Vector3,
	bool,
	kineffi.JPH_BodyID,
	datatypes.Vector3,
	datatypes.Vector3,
) {
	result := world
	normal := datatypes.Vector3{0, 1, 0}
	platform_id := kineffi.JPH_BODY_ID_INVALID
	anchor, normal_local: datatypes.Vector3
	if physics == nil || physics.data_model == nil {
		return result, normal, false, platform_id, anchor, normal_local
	}
	workspace := DataModel_Get_Service(physics.data_model, "Workspace")
	if workspace == nil {return result, normal, false, platform_id, anchor, normal_local}
	params := datatypes.RaycastParams_New()
	params.RespectCanCollide = true
	params.ExcludeFilterSet = true
	append(&params.ExcludeInstances, datatypes.Raycast_Instance_Reference{object = model})
	defer delete(params.ExcludeInstances)
	ray, hit := Physics_Raycast(
		physics,
		workspace,
		datatypes.Vector3{world.x, world.y + height, world.z},
		datatypes.Vector3{0, -height * 2.5, 0},
		&params,
		synchronize = false,
	)
	if !hit || ray.Normal.y < 0.2 {
		return result, normal, false, platform_id, anchor, normal_local
	}
	result.y = ray.Position.y + sole_height
	if ray.ObjectRef != nil {
		part_obj := cast(^classes.Object)ray.ObjectRef
		if classes.Is_A(part_obj, "Part") {
			part := cast(^classes.Part)part_obj


			for body in physics.bodies {
				if body.object == part_obj {
					platform_id = body.body_id
					anchor = datatypes.CFrame_PointToObjectSpace(part.cframe, result)
					normal_local = datatypes.CFrame_VectorToObjectSpace(part.cframe, ray.Normal)
					break
				}
			}
		}
	}
	return result, ray.Normal, true, platform_id, anchor, normal_local
}

CharacterPhysicsSolver_Advance :: proc(
	controller: ^classes.CharacterController,
	physics: ^Physics,
	root: ^classes.Part,
	contact_normal: datatypes.Vector3,
	dt: f32,
) {
	if controller == nil || root == nil || dt <= 0 {return}
	object := classes.CharacterController_Find(controller, "CharacterPhysicsSolver")
	if object == nil {return}
	solver := cast(^classes.CharacterPhysicsSolver)object
	if !solver.enabled {
		if solver.status != "Disabled" {
			rig := solver_rig(solver, controller)
			if rig != nil && rig.native_mesh != nil && rig.native_context != nil {
				_ = kineffi.Kine_Filament_ClearMeshProceduralPose(
					rig.native_context,
					rig.native_mesh,
				)
				classes.MeshPart_Reset_Bone_Transforms(rig)
			}
		}
		solver.status = "Disabled"
		return
	}
	if controller.parent == nil ||
	   controller.parent.destroyed {solver.status = "NoCharacterModel"; return}
	model := controller.parent
	rig := solver_rig(solver, controller)
	if rig == nil {solver.status = "WaitingForRig"; return}
	if rig.native_mesh == nil || rig.native_context == nil {
		solver.status = "WaitingForMesh"
		return
	}
	if !solver_calibrate(solver, rig) {return}
	gd := cast(^classes.GroundDetector)classes.CharacterController_Find(
		controller,
		"GroundDetector",
	)
	solver.grounded = gd != nil && gd.grounded
	solver.ground_normal =
		solver.grounded ? solver_normalize(contact_normal) : datatypes.Vector3{0, 1, 0}
	root_pos := datatypes.Vector3{root.cframe.x, root.cframe.y, root.cframe.z}
	root_delta: datatypes.Vector3
	if solver.last_root_valid {
		d := solver_sub(root_pos, solver.last_root)
		root_delta = d
		dist := math.sqrt(d.x * d.x + d.z * d.z)
		if solver_len(d) > max(12, solver.leg_length * 4) {
			for &f in solver.foot {
				f = {}
				f.platform_id = kineffi.JPH_BODY_ID_INVALID
				f.target_platform_id = kineffi.JPH_BODY_ID_INVALID
			}
			root_delta = {}
			dist = 0
			solver.motion_velocity = {}
			solver.last_velocity = {}
			solver.gait_weight = 0
			solver.height_initialized = false
			solver.facing_valid = false
		}
		solver.horizontal_speed = f32(dist / f64(dt))
	} else {
		solver.horizontal_speed = 0
	}
	solver.last_root_valid = true
	solver.last_root = root_pos

	solver_plan_gait(solver, rig, controller, root, physics, root_delta, dt)

	solver.frame_time += f64(dt)
	full_body_support(solver, rig, root, root_delta, dt)
	full_body_plan_hands(solver, rig, controller, root, physics, dt)

	if solver.pose_blend <= 0 {
		_ = kineffi.Kine_Filament_ClearMeshProceduralPose(rig.native_context, rig.native_mesh)
		classes.MeshPart_Reset_Bone_Transforms(rig)
		solver.status = "TrackingContacts"
		return
	}
	locals := classes.Animation_MeshPart_Bone_Transforms(rig)
	if len(locals) != len(solver.bind_local) {solver.status = "RigChanged"; return}
	posed := make([][16]f32, len(locals), context.temp_allocator)
	copy(posed, solver.bind_local)


	full_body_pelvis_and_balance(solver, rig, root, root_delta, dt, posed)
	if solver.foot_ik_enabled {
		for i in 0 ..< 2 {
			if solver.foot[i].planted || !solver.grounded {
				_ = full_body_two_bone_ik(
					solver,
					rig,
					posed,
					solver.leg_bones[i],
					solver.foot[i].current,
					f64(solver.pose_blend),
					solver_forward(root),
				)
				solver_orient_foot(solver, rig, root, i, posed)
			}
		}
	}
	full_body_pose_arms(solver, rig, posed)
	full_body_head_stabilize(solver, dt, posed)


	changed := make([]u8, len(posed), context.temp_allocator)
	for i in 0 ..< len(posed) {
		for j in 0 ..< 16 {
			if math.abs(posed[i][j] - solver.bind_local[i][j]) > 0.00001 {
				changed[i] = 1
				break
			}
		}
	}


	if !kineffi.Kine_Filament_SetMeshProceduralLocalPose(
		rig.native_context,
		rig.native_mesh,
		&posed[0][0],
		&changed[0],
		i32(len(posed)),
	) {
		solver.status = "PoseRejected"
		return
	}
	copy(locals, posed)
	solver.status = "Solving"
	solver.solve_count += 1
}
