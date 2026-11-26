package services

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import "core:math"


full_body_globals :: proc(part: ^classes.MeshPart, local_pose: [][16]f32) -> [][16]f32 {
	if part == nil || part.native_mesh == nil || len(local_pose) == 0 {return nil}
	result := make([][16]f32, len(local_pose), context.temp_allocator)
	states := make([]u8, len(local_pose), context.temp_allocator)
	for i in 0 ..< len(local_pose) {
		if !classes.Animation_Eval_Bone_Global(
			i,
			local_pose,
			result,
			states,
			part.native_mesh,
		) {return nil}
	}
	return result
}

full_body_position :: proc(m: [16]f32) -> datatypes.Vector3 {
	return {f64(m[3]), f64(m[7]), f64(m[11])}
}

full_body_limb_available :: proc(indices: [3]i32, count: int) -> bool {
	for index in indices {
		if index < 0 || int(index) >= count {return false}
	}
	return indices[0] != indices[1] && indices[1] != indices[2]
}

full_body_two_bone_ik :: proc(
	solver: ^classes.CharacterPhysicsSolver,
	rig: ^classes.MeshPart,
	local_pose: [][16]f32,
	chain: [3]i32,
	target_world: datatypes.Vector3,
	strength: f64,
	pole_world: datatypes.Vector3 = {},
) -> bool {
	if rig == nil ||
	   !full_body_limb_available(chain, len(local_pose)) ||
	   strength <= 0.001 {return false}
	globals := full_body_globals(rig, local_pose)
	if globals == nil {return false}

	a, b, c := int(chain[0]), int(chain[1]), int(chain[2])
	hip := full_body_position(globals[a])
	joint := full_body_position(globals[b])
	tip := full_body_position(globals[c])
	l1, l2 := solver_len(solver_sub(joint, hip)), solver_len(solver_sub(tip, joint))
	if l1 <= 1.0e-5 || l2 <= 1.0e-5 {return false}

	target := solver_skeleton_from_world(rig, target_world)
	hip_to_target := solver_sub(target, hip)
	distance := solver_len(hip_to_target)
	if distance < 1.0e-4 {return false}

	direction := solver_mul(hip_to_target, 1 / distance)
	reach := clamp(distance, math.abs(l1 - l2) + 0.001, l1 + l2 - 0.001)
	target = solver_add(hip, solver_mul(direction, reach))


	bend := solver_sub(joint, hip)
	pole := solver_sub(bend, solver_mul(direction, solver_dot(bend, direction)))
	if solver_len(pole_world) > 0.001 {
		local_pole := datatypes.CFrame_VectorToObjectSpace(rig.cframe, pole_world)
		pole = solver_sub(local_pole, solver_mul(direction, solver_dot(local_pole, direction)))
	}
	if solver_len(pole) < 1.0e-4 {
		pole = solver_cross(direction, {0, 0, 1})
		if solver_len(pole) < 1.0e-4 {pole = solver_cross(direction, {1, 0, 0})}
	}
	along := (l1 * l1 - l2 * l2 + reach * reach) / (2 * reach)
	offset := math.sqrt(max(l1 * l1 - along * along, 0.0))
	proposed_joint := solver_add(
		solver_add(hip, solver_mul(direction, along)),
		solver_mul(solver_normalize(pole), offset),
	)

	start_axis := solver_sub(joint, hip)
	target_axis := solver_sub(proposed_joint, hip)
	upper_delta := solver_rotation_between(start_axis, target_axis, strength)

	parent := kineffi.Kine_Filament_GetMeshBoneParent(rig.native_mesh, chain[0])
	parent_world := datatypes.CFrame_Identity
	if parent >= 0 && int(parent) < len(globals) {
		parent_world = classes.Animation_Matrix_To_CFrame(globals[int(parent)])
	}

	upper_original := classes.Animation_Matrix_To_CFrame(globals[a])
	upper_final := solver_rotate_pivot(upper_delta, hip, upper_original)
	lower_original_local := classes.Animation_Matrix_To_CFrame(local_pose[b])
	lower_final := datatypes.CFrame_Mul_CFrame(upper_final, lower_original_local)
	lower_pivot := solver_cf_pos(lower_final)


	tip_local := classes.Animation_Matrix_To_CFrame(local_pose[c])
	current_tip := solver_cf_pos(datatypes.CFrame_Mul_CFrame(lower_final, tip_local))
	lower_delta := solver_rotation_between(
		solver_sub(current_tip, lower_pivot),
		solver_sub(target, lower_pivot),
		strength,
	)
	lower_final = solver_rotate_pivot(lower_delta, lower_pivot, lower_final)


	local_pose[a] = classes.Animation_CFrame_To_Matrix(
		datatypes.CFrame_Mul_CFrame(datatypes.CFrame_Inverse(parent_world), upper_final),
	)
	local_pose[b] = classes.Animation_CFrame_To_Matrix(
		datatypes.CFrame_Mul_CFrame(datatypes.CFrame_Inverse(upper_final), lower_final),
	)
	return true
}

full_body_contact_ray :: proc(
	physics: ^Physics,
	model: ^classes.Object,
	start, direction: datatypes.Vector3,
) -> (
	datatypes.RaycastResult,
	bool,
) {
	if physics == nil ||
	   physics.data_model == nil ||
	   model == nil ||
	   solver_len(direction) < 0.0001 {return {}, false}
	workspace := DataModel_Get_Service(physics.data_model, "Workspace")
	if workspace == nil {return {}, false}
	params := datatypes.RaycastParams_New()
	params.RespectCanCollide = true
	params.ExcludeFilterSet = true
	append(&params.ExcludeInstances, datatypes.Raycast_Instance_Reference{object = model})
	defer delete(params.ExcludeInstances)
	return Physics_Raycast(physics, workspace, start, direction, &params, synchronize = false)
}

full_body_plan_hands :: proc(
	solver: ^classes.CharacterPhysicsSolver,
	rig: ^classes.MeshPart,
	controller: ^classes.CharacterController,
	root: ^classes.Part,
	physics: ^Physics,
	dt: f32,
) {
	solver.hand_contact_count = 0
	if rig == nil || controller == nil || root == nil {return}
	look := solver_forward(root)
	up := datatypes.CFrame_UpVector(root.cframe)
	right := datatypes.CFrame_RightVector(root.cframe)
	smooth := 1 - math.exp(-10 * f64(dt))

	for i in 0 ..< 2 {
		hand := &solver.hand[i]
		chain := solver.arm_bones[i]
		if !full_body_limb_available(chain, len(solver.bind_global)) {
			hand.active = false
			hand.weight = 0
			continue
		}

		offset := datatypes.Vector3{0, solver.pelvis_height - solver.impact_compression, 0}
		start := solver_add(
			solver_world_from_skeleton(rig, solver_rest_position(solver, chain[2])),
			offset,
		)
		shoulder := solver_add(
			solver_world_from_skeleton(rig, solver_rest_position(solver, chain[0])),
			offset,
		)
		elbow := solver_add(
			solver_world_from_skeleton(rig, solver_rest_position(solver, chain[1])),
			offset,
		)
		arm_reach := solver_len(solver_sub(shoulder, elbow)) + solver_len(solver_sub(elbow, start))
		sign := solver_dot(solver_sub(start, shoulder), right) >= 0 ? 1.0 : -1.0


		desired := solver_add(
			shoulder,
			solver_add(
				solver_mul(up, -arm_reach * 0.94),
				solver_add(
					solver_mul(right, arm_reach * 0.07 * sign),
					solver_mul(look, arm_reach * 0.05),
				),
			),
		)


		inertia := solver_mul(
			solver.reaction_acceleration,
			-0.0015 * f64(solver.reaction_strength),
		)
		inertia_length := solver_len(inertia)
		if inertia_length > 0.25 {inertia = solver_mul(inertia, 0.25 / inertia_length)}
		desired = solver_add(desired, inertia)
		active := false
		normal := datatypes.Vector3{0, 0, 0}

		if solver.hand_ik_enabled && solver.contact_reach > 0 {


			ray, hit := full_body_contact_ray(
				physics,
				controller.parent,
				solver_add(desired, solver_mul(look, -0.12)),
				solver_mul(look, f64(solver.contact_reach)),
			)
			if hit && ray.Normal.y < 0.75 && solver_dot(ray.Normal, look) < -0.25 {
				candidate := solver_add(ray.Position, solver_mul(ray.Normal, 0.08))
				max_reach := arm_reach


				if solver_len(solver_sub(candidate, shoulder)) <= max_reach * 1.03 {
					desired = candidate
					active = true
					normal = ray.Normal
				}
			}
		}

		hand.active = active
		hand.normal = normal
		hand.weight = f32(f64(hand.weight) + (f64(active ? 1.0 : 0.0) - f64(hand.weight)) * smooth)
		if active {
			if hand.weight <=
			   0.1 {hand.target = desired} else {hand.target = solver_add(hand.target, solver_mul(solver_sub(desired, hand.target), smooth))}
			solver.hand_contact_count += 1
		} else {
			if solver.arm_swing_enabled {


				travel := math.cos(solver.gait_phase) * (i == 0 ? 1.0 : -1.0) * solver.gait_weight
				desired = solver_add(desired, solver_mul(look, travel * arm_reach * 0.22))
				desired = solver_add(desired, solver_mul(up, math.abs(travel) * arm_reach * 0.035))
				desired = solver_add(
					desired,
					solver_mul(
						up,
						solver.impact_compression * 0.5 + solver.air_weight * arm_reach * 0.08,
					),
				)
			}
			if solver.solve_count ==
			   0 {hand.target = desired} else {hand.target = solver_add(hand.target, solver_mul(solver_sub(desired, hand.target), smooth))}
		}
	}
}

full_body_support :: proc(
	solver: ^classes.CharacterPhysicsSolver,
	rig: ^classes.MeshPart,
	root: ^classes.Part,
	delta: datatypes.Vector3,
	dt: f32,
) {
	if solver == nil || rig == nil || root == nil {return}
	solver.has_support = false
	solver.support_center = {}
	points: f64
	for &foot in solver.foot {
		if !foot.planted || foot.swinging {continue}
		solver.support_center = solver_add(solver.support_center, foot.current)
		points += 1
	}
	if points > 0 {
		solver.support_center = solver_mul(solver.support_center, 1 / points)
		solver.has_support = solver.grounded
	}

	pelvis := solver.pelvis_bone
	spine := solver.spine_upper_bone
	center := solver_cf_pos(root.cframe)
	if pelvis >= 0 {
		center = solver_world_from_skeleton(rig, solver_rest_position(solver, pelvis))
		center.y += solver.pelvis_height
	}
	if spine >= 0 {
		high := solver_world_from_skeleton(rig, solver_rest_position(solver, spine))
		high.y += solver.pelvis_height
		center = solver_add(solver_mul(center, 0.65), solver_mul(high, 0.35))
	}

	solver.center_of_mass = center

	facing := solver_forward(root)
	angular_speed: f64
	if solver.facing_valid {
		angular_speed =
			math.atan2(
				solver_cross(solver.last_facing, facing).y,
				solver_dot(solver.last_facing, facing),
			) /
			max(f64(dt), 0.0001)
	}
	solver.reaction_yaw +=
		(clamp(angular_speed, -12.0, 12.0) - solver.reaction_yaw) * (1 - math.exp(-f64(dt) * 12))
	solver.last_facing = facing
	solver.facing_valid = true


	velocity := solver_mul(delta, 1 / max(f64(dt), 0.0001))
	solver.reaction_acceleration = solver_mul(
		solver_sub(velocity, solver.last_velocity),
		1 / max(f64(dt), 0.0001),
	)
	magnitude := solver_len(solver.reaction_acceleration)
	if magnitude >
	   500 {solver.reaction_acceleration = solver_mul(solver.reaction_acceleration, 500 / magnitude)}
	solver.last_velocity = velocity

	vertical_speed := delta.y / f64(dt)
	if solver.grounded && !solver.previous_grounded && solver.previous_vertical_speed < -2 {
		solver.impact_compression = clamp(-solver.previous_vertical_speed * 0.015, 0.02, 0.35)
	}
	solver.impact_compression *= math.exp(-11 * f64(dt))
	solver.previous_vertical_speed = vertical_speed
	solver.previous_grounded = solver.grounded
}

full_body_pelvis_and_balance :: proc(
	solver: ^classes.CharacterPhysicsSolver,
	rig: ^classes.MeshPart,
	root: ^classes.Part,
	delta: datatypes.Vector3,
	dt: f32,
	pose: [][16]f32,
) {
	if solver == nil || rig == nil || root == nil {return}
	look := solver_forward(root)
	right := datatypes.CFrame_RightVector(root.cframe)
	forward_speed := solver_dot(delta, look) / max(f64(dt), 0.0001)
	side_speed := solver_dot(delta, right) / max(f64(dt), 0.0001)
	strength := f64(solver.balance_strength) * f64(solver.pose_blend)

	compensation: datatypes.Vector3
	if solver.balance_enabled && solver.has_support {
		error := solver_sub(solver.support_center, solver.center_of_mass)
		error.y = 0
		compensation = solver_mul(error, clamp(strength * 0.22, 0.0, 0.25))
		magnitude := solver_len(compensation)
		if magnitude > 0.18 {compensation = solver_mul(compensation, 0.18 / magnitude)}
	}

	if solver.pelvis_bone >= 0 && int(solver.pelvis_bone) < len(pose) {
		index := int(solver.pelvis_bone)
		hip := classes.Animation_Matrix_To_CFrame(pose[index])

		local := datatypes.CFrame_VectorToObjectSpace(rig.cframe, compensation)
		hip.x += local.x / max(f64(rig.size.x) * 0.5, 0.0001)
		hip.z += local.z / max(f64(rig.size.z) * 0.5, 0.0001)
		hip.y +=
			(solver.pelvis_height - solver.impact_compression) / max(f64(rig.size.y) * 0.5, 0.0001)
		twist := datatypes.CFrame_FromEulerAnglesXYZ(
			0,
			math.sin(solver.gait_phase) * 0.045 * solver.gait_weight -
			clamp(solver.reaction_yaw * 0.025, -0.18, 0.18),
			0,
		)
		hip = datatypes.CFrame_Mul_CFrame(hip, twist)
		pose[index] = classes.Animation_CFrame_To_Matrix(hip)
	}

	if solver.balance_enabled && solver.spine_bone >= 0 && int(solver.spine_bone) < len(pose) {
		support := datatypes.Vector3{}
		if solver.has_support {support = solver_sub(solver.support_center, solver.center_of_mass)}
		forward_accel := solver_dot(solver.reaction_acceleration, look)
		side_accel := solver_dot(solver.reaction_acceleration, right)
		target_pitch :=
			clamp(
				forward_speed * 0.004 -
				forward_accel * 0.00045 * f64(solver.reaction_strength) -
				solver_dot(look, solver.ground_normal) * 0.07 +
				solver_dot(support, look) * 0.045,
				-0.19,
				0.19,
			) *
			strength
		target_roll :=
			clamp(
				-side_speed * 0.003 +
				side_accel * 0.0004 * f64(solver.reaction_strength) +
				solver_dot(support, right) * 0.06 -
				solver.reaction_yaw * f64(solver.horizontal_speed) * 0.002,
				-0.15,
				0.15,
			) *
			strength
		alpha := 1 - math.exp(-f64(dt) * 8)
		solver.balance_pitch += (target_pitch - solver.balance_pitch) * alpha
		solver.balance_roll += (target_roll - solver.balance_roll) * alpha
		index := int(solver.spine_bone)
		base := classes.Animation_Matrix_To_CFrame(pose[index])
		correction := datatypes.CFrame_FromEulerAnglesXYZ(
			solver.balance_pitch,
			-math.sin(solver.gait_phase) * 0.03 * solver.gait_weight,
			solver.balance_roll,
		)
		pose[index] = classes.Animation_CFrame_To_Matrix(
			datatypes.CFrame_Mul_CFrame(base, correction),
		)
	}
}

full_body_head_stabilize :: proc(
	solver: ^classes.CharacterPhysicsSolver,
	dt: f32,
	pose: [][16]f32,
) {
	if !solver.head_stabilization_enabled {return}


	bones := [2]i32{solver.neck_bone, solver.head_bone}
	for bone, index in bones {
		if bone < 0 || int(bone) >= len(pose) {continue}
		factor := index == 0 ? -0.52 : -0.3
		base := classes.Animation_Matrix_To_CFrame(pose[int(bone)])
		correction := datatypes.CFrame_FromEulerAnglesXYZ(
			solver.balance_pitch * factor,
			0,
			solver.balance_roll * factor,
		)
		pose[int(bone)] = classes.Animation_CFrame_To_Matrix(
			datatypes.CFrame_Mul_CFrame(base, correction),
		)
	}
}

full_body_pose_arms :: proc(
	solver: ^classes.CharacterPhysicsSolver,
	rig: ^classes.MeshPart,
	pose: [][16]f32,
) {
	root := classes.CharacterController_Root(cast(^classes.CharacterController)solver.parent)
	if root == nil {return}
	forward := solver_forward(root)
	right := datatypes.CFrame_RightVector(root.cframe)
	for i in 0 ..< 2 {
		chain := solver.arm_bones[i]
		if !full_body_limb_available(chain, len(pose)) {continue}
		hand := &solver.hand[i]
		if hand.active && solver.hand_ik_enabled {
			_ = full_body_two_bone_ik(
				solver,
				rig,
				pose,
				chain,
				hand.target,
				f64(solver.pose_blend) * f64(hand.weight),
				solver_add(solver_mul(forward, -1), solver_mul(right, i == 0 ? 0.15 : -0.15)),
			)
		} else if solver.arm_swing_enabled {
			_ = full_body_two_bone_ik(
				solver,
				rig,
				pose,
				chain,
				hand.target,
				f64(solver.pose_blend) * f64(1 - hand.weight),
				solver_add(solver_mul(forward, -1), solver_mul(right, i == 0 ? 0.15 : -0.15)),
			)
		}
	}
}
