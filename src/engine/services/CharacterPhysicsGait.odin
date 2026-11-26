package services

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import "core:math"


solver_forward :: proc(root: ^classes.Part) -> datatypes.Vector3 {
	return solver_mul(datatypes.CFrame_LookVector(root.cframe), -1)
}

solver_plan_gait :: proc(
	s: ^classes.CharacterPhysicsSolver,
	rig: ^classes.MeshPart,
	cc: ^classes.CharacterController,
	root: ^classes.Part,
	physics: ^Physics,
	delta: datatypes.Vector3,
	dt: f32,
) {
	elapsed := f64(dt)
	velocity := solver_mul(delta, 1 / elapsed)
	velocity.y = 0
	alpha := 1 - math.exp(-elapsed * 14)
	s.motion_velocity = solver_add(
		s.motion_velocity,
		solver_mul(solver_sub(velocity, s.motion_velocity), alpha),
	)
	speed := solver_len(s.motion_velocity)
	stride := max(f64(s.stride_length), s.leg_length * 0.5)
	duration := clamp(
		f64(s.step_duration) *
		math.sqrt(max(s.leg_length, 0.25) / 1.5) *
		math.sqrt(5 / max(speed, 1)),
		0.12,
		0.48,
	)
	weight := clamp(speed / 2, 0.0, 1.0)
	s.gait_weight += (weight - s.gait_weight) * (1 - math.exp(-elapsed * 10))
	s.air_weight += (f64(s.grounded ? 0 : 1) - s.air_weight) * (1 - math.exp(-elapsed * 16))
	forward := solver_forward(root)
	probe := max(2.5, s.leg_length * 0.9)

	rest: [2]datatypes.Vector3
	contacts: [2]datatypes.Vector3
	normals: [2]datatypes.Vector3
	hits: [2]bool
	ids: [2]kineffi.JPH_BodyID
	anchors, local_normals: [2]datatypes.Vector3
	for i in 0 ..< 2 {
		f := &s.foot[i]
		rest[i] = solver_world_from_skeleton(rig, solver_rest_position(s, s.leg_bones[i][2]))


		horizon := duration * 1.25
		if f.swinging {horizon = f64(f.duration) * (1 - f64(f.progress) + 0.25)}
		forecast := solver_add(rest[i], solver_mul(s.motion_velocity, horizon))
		contacts[i], normals[i], hits[i], ids[i], anchors[i], local_normals[i] =
			solver_ground_target(physics, cc.parent, forecast, probe, s.sole_height)
		if !s.grounded {
			f.planted = false
			f.swinging = false
			f.platform_id = kineffi.JPH_BODY_ID_INVALID


			tuck :=
				(0.35 + 0.65 * clamp(f64(cc.vertical_speed) / 32, 0.0, 1.0)) *
				clamp(1 + f64(cc.vertical_speed) / 50, 0.0, 1.0) *
				s.air_weight *
				s.leg_length *
				0.22
			f.current = rest[i]
			f.current.y += s.standing_height + tuck
			f.current = solver_add(f.current, solver_mul(forward, tuck * (i == 0 ? 0.45 : -0.2)))
			continue
		}
		if !f.planted {

			point, normal, hit, id, anchor, n := solver_ground_target(
				physics,
				cc.parent,
				rest[i],
				probe,
				s.sole_height,
			)
			f.current = hit ? point : rest[i]
			f.start = f.current
			f.target = f.current
			f.normal = normal
			f.planted = hit
			f.platform_id = id
			f.platform_anchor = anchor
			f.platform_normal = n
		}
		if f.platform_id != kineffi.JPH_BODY_ID_INVALID && !f.swinging {
			platform, found := physics.body_to_part[f.platform_id]
			if found && platform != nil && !platform.destroyed {
				f.current = datatypes.CFrame_PointToWorldSpace(platform.cframe, f.platform_anchor)
				f.normal = solver_normalize(
					datatypes.CFrame_VectorToWorldSpace(platform.cframe, f.platform_normal),
				)
			} else {f.platform_id = kineffi.JPH_BODY_ID_INVALID}
		}
		if f.swinging {


			if f.progress < 0.7 && hits[i] {
				f.target = contacts[i]
				f.normal = normals[i]
				f.target_platform_id = ids[i]
				f.target_platform_anchor = anchors[i]
				f.target_platform_normal = local_normals[i]
			}
			f.progress = min(f.progress + dt / max(f.duration, 0.08), 1)
			t := f64(f.progress)


			u := t * t * t * (10 + t * (-15 + 6 * t))
			f.current = solver_add(f.start, solver_mul(solver_sub(f.target, f.start), u))
			lift := min(f64(s.foot_lift), s.leg_length * 0.16)
			f.current.y += lift * 16 * t * t * (1 - t) * (1 - t)
			s.gait_phase = (f64(i) + t) * math.PI
			if f.progress >= 1 {
				f.current = f.target
				f.platform_id = f.target_platform_id
				f.platform_anchor = f.target_platform_anchor
				f.platform_normal = f.target_platform_normal
				f.swinging = false
				s.next_step = 1 - i
			}
		}
	}
	if s.grounded && !s.foot[0].swinging && !s.foot[1].swinging {
		chosen := -1
		error_max := stride * 0.42
		for offset in 0 ..< 2 {
			i := (s.next_step + offset) % 2
			if offset > 0 && chosen >= 0 {break}
			difference := solver_sub(contacts[i], s.foot[i].current)
			difference.y = 0
			error := solver_len(difference)
			if hits[i] && error > error_max {chosen = i; error_max = error}
		}
		if chosen >= 0 {
			f := &s.foot[chosen]
			f.swinging = true
			f.planted = true
			f.progress = 0
			f.duration = f32(duration)
			f.start = f.current
			f.target = contacts[chosen]
			f.normal = normals[chosen]
			f.target_platform_id = ids[chosen]
			f.target_platform_anchor = anchors[chosen]
			f.target_platform_normal = local_normals[chosen]
		}
	}
	height_ceiling := 1.0e9
	if s.grounded {
		height, points: f64
		for i in 0 ..< 2 {
			f := &s.foot[i]
			if !f.planted {continue}
			height += (f.swinging ? f.target.y : f.current.y) - rest[i].y
			points += 1
		}
		if points > 0 {


			target := clamp(
				height / points - s.leg_length * 0.025,
				-s.leg_length * 0.8,
				s.leg_length * 0.5,
			)
			for i in 0 ..< 2 {
				foot := &s.foot[i]
				if !foot.planted {continue}
				hip := solver_world_from_skeleton(rig, solver_rest_position(s, s.leg_bones[i][0]))
				dx, dz := foot.current.x - hip.x, foot.current.z - hip.z
				reach := s.leg_length * 0.98
				allowed := math.sqrt(max(reach * reach - dx * dx - dz * dz, reach * reach * 0.25))
				target = min(target, foot.current.y + allowed - hip.y)
			}
			height_ceiling = target
			if !s.height_initialized {s.standing_height = target; s.height_initialized = true}
			s.standing_height += (target - s.standing_height) * (1 - math.exp(-elapsed * 18))
		}
	}
	bob := (math.cos(s.gait_phase * 2) - 1) * s.leg_length * 0.008 * s.gait_weight
	target_height := s.standing_height + bob
	s.pelvis_height += (target_height - s.pelvis_height) * (1 - math.exp(-elapsed * 20))


	s.pelvis_height = min(s.pelvis_height, height_ceiling)
}

solver_orient_foot :: proc(
	s: ^classes.CharacterPhysicsSolver,
	rig: ^classes.MeshPart,
	root: ^classes.Part,
	side: int,
	pose: [][16]f32,
) {
	if !s.grounded {return}
	globals := full_body_globals(rig, pose)
	if globals == nil {return}
	bone := s.leg_bones[side][2]
	parent := kineffi.Kine_Filament_GetMeshBoneParent(rig.native_mesh, bone)
	if parent < 0 {return}


	normal := datatypes.CFrame_VectorToObjectSpace(rig.cframe, s.foot[side].normal)
	tilt := solver_rotation_between({0, 1, 0}, normal)
	ankle := classes.Animation_Matrix_To_CFrame(s.bind_global[bone])
	ankle = datatypes.CFrame_Mul_CFrame(tilt, ankle)
	ankle.x = f64(
		globals[bone][3],
	); ankle.y = f64(globals[bone][7]); ankle.z = f64(globals[bone][11])
	pose[bone] = classes.Animation_CFrame_To_Matrix(
		datatypes.CFrame_Mul_CFrame(
			datatypes.CFrame_Inverse(classes.Animation_Matrix_To_CFrame(globals[parent])),
			ankle,
		),
	)
}
