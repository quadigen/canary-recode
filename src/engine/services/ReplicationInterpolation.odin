package services

import classes "../classes"
import datatypes "../datatypes"
import "core:math"

replication_predict_body :: proc(
	sample: Replication_Sample,
	seconds, max_distance: f32,
) -> datatypes.CFrame {
	displacement := datatypes.Vec3_Multiply(sample.linear_velocity, f64(seconds))
	distance := datatypes.Vec3_Magnitude(displacement)
	if max_distance > 0 && distance > f64(max_distance) {
		displacement = datatypes.Vec3_Multiply(displacement, f64(max_distance) / distance)
	}
	rotation := datatypes.CFrame_Rotation(sample.frame)
	speed := datatypes.Vec3_Magnitude(sample.angular_velocity)
	if speed > 1e-5 {
		delta := datatypes.CFrame_FromAxisAngle(sample.angular_velocity, speed * f64(seconds))
		rotation = datatypes.CFrame_Mul_CFrame(delta, rotation)
	}
	position := datatypes.Vec3_Add(datatypes.CFrame_Position(sample.frame), displacement)
	rotation.x, rotation.y, rotation.z = position.x, position.y, position.z
	return rotation
}

replication_render_interpolated :: proc(service: ^ReplicatorService, delta_time: f32) {
	if service.mode != .Client {return}
	changed := false
	defer {if changed {classes.Render_3D_Mark_Dirty()}}
	players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")


	DR_MAX_AGE :: f32(0.3)


	DR_MAX_STEP :: f32(8.0)


	CORRECTION_DECAY_RATE :: f32(8.0)

	for entity in service.entity_list {
		if entity.object == nil ||
		   entity.object.destroyed ||
		   !classes.Is_A(entity.object, "Part") {continue}


		if players != nil && players.local_player != nil {
			if entity.object.parent != nil &&
			   classes.Is_A(entity.object.parent, "CharacterModel") {
				model := cast(^classes.CharacterModel)entity.object.parent
				if model.owner_user_id == players.local_player.user_id {continue}
			} else if entity.owner_id == players.local_player.user_id {continue}
		}

		part := cast(^classes.Part)entity.object
		model := classes.PhysicsModel_For(entity.object)
		max_age := DR_MAX_AGE
		if model != nil {max_age = model.max_extrapolation_time}

		if len(entity.samples) == 0 {continue}

		entity.sample_age += delta_time
		latest := entity.samples[len(entity.samples) - 1]
		if model != nil && !model.interpolation_enabled {
			changed = changed || part.cframe != latest.frame
			part.cframe = latest.frame
			part.position = datatypes.CFrame_Position(latest.frame)
			entity.frame_seeded = false
			entity.render_correction = {}
			entity.dr_age = 0
			continue
		}

		if !entity.frame_seeded {
			entity.last_frame = latest.frame
			entity.last_velocity = datatypes.Vector3{0, 0, 0}
			entity.dr_age = 0
			entity.render_correction = {}
			entity.frame_seeded = true
		}


		rate := f64(service.snapshot_rate)
		if rate <= 0 {rate = 20}
		clock_rate := f64(service.snapshot_clock_rate)
		if clock_rate <= 0 {clock_rate = rate}
		delay_ticks := f64(service.interpolation_delay_ticks) * clock_rate / rate
		if model != nil && model.interpolation_delay >= 0 {
			delay_ticks = f64(model.interpolation_delay) * clock_rate
		}
		target: f64
		if service.time_offset_measured {
			target = (f64(service.clock) + f64(service.time_offset)) * clock_rate - delay_ticks
		} else {
			target = f64(latest.tick) - delay_ticks + f64(entity.sample_age) * clock_rate
		}


		have_data := target <= f64(latest.tick) + 0.5 * clock_rate / rate
		frame := datatypes.CFrame{}


		previous_dr_age := entity.dr_age
		was_predicting :=
			previous_dr_age > 0 &&
			previous_dr_age <= max_age &&
			(entity.last_velocity != (datatypes.Vector3{}) || latest.has_velocity)

		if have_data {
			if target >= f64(latest.tick) {
				frame = latest.frame
			} else if target <= f64(entity.samples[0].tick) {
				frame = entity.samples[0].frame
			} else {

				found := false
				for index := 1; index < len(entity.samples); index += 1 {
					right := entity.samples[index]
					if target > f64(right.tick) {continue}
					left := entity.samples[index - 1]
					span := f64(right.tick - left.tick)
					if span > 0 {
						alpha := f32(clamp((target - f64(left.tick)) / span, 0, 1))
						frame = datatypes.CFrame_Lerp(left.frame, right.frame, f64(alpha))
					} else {
						frame = right.frame
					}
					found = true
					break
				}
				if !found {frame = latest.frame}
			}


			if latest.has_velocity {
				entity.last_velocity = latest.linear_velocity
			} else if len(entity.samples) >= 2 {
				prev := entity.samples[len(entity.samples) - 2]
				dt_ticks := f32(latest.tick - prev.tick)
				dx := latest.frame.x - prev.frame.x
				dy := latest.frame.y - prev.frame.y
				dz := latest.frame.z - prev.frame.z
				tele_sq := service.teleport_threshold * service.teleport_threshold
				if dx * dx + dy * dy + dz * dz > f64(tele_sq) {
					entity.last_velocity = datatypes.Vector3{0, 0, 0}
				} else if dt_ticks > 0 {
					inv := f32(clock_rate) / dt_ticks
					entity.last_velocity = datatypes.Vector3{dx * f64(inv), dy * f64(inv), dz * f64(inv)}
				}
			}
			entity.last_frame = frame
			entity.dr_age = 0
		} else {


			entity.dr_age += delta_time
			if latest.has_velocity && max_age > 0 {
				// Predict from the latest authoritative pose, not yesterday's
				// predicted pose. Bound both time and travel to avoid runaway.
				age := clamp(f32((target - f64(latest.tick)) / clock_rate), 0, max_age)
				entity.dr_age = age
				entity.last_velocity = latest.linear_velocity
				frame = replication_predict_body(latest, age, service.teleport_threshold)
				entity.last_frame = frame
			} else if entity.dr_age > max_age || max_age <= 0 {


				frame = latest.frame
				entity.last_frame = frame
			} else {
				step_x := entity.last_velocity.x * f64(delta_time)
				step_y := entity.last_velocity.y * f64(delta_time)
				step_z := entity.last_velocity.z * f64(delta_time)


				step_sq := step_x * step_x + step_y * step_y + step_z * step_z
				if step_sq > f64(DR_MAX_STEP * DR_MAX_STEP) {
					mag := math.sqrt(step_sq)
					if mag > 1e-12 {
						scale := f64(DR_MAX_STEP) / mag
						step_x *= scale
						step_y *= scale
						step_z *= scale
					}
				}
				frame = entity.last_frame
				frame.x += step_x
				frame.y += step_y
				frame.z += step_z
				entity.last_frame = frame
			}
		}


		dx := frame.x - part.cframe.x
		dy := frame.y - part.cframe.y
		dz := frame.z - part.cframe.z
		dist_sq := dx * dx + dy * dy + dz * dz
		tele_sq := service.teleport_threshold * service.teleport_threshold


		recovering := was_predicting && (have_data || entity.dr_age > max_age)

		if dist_sq > f64(tele_sq) {
			entity.render_correction = {}
		} else if recovering {
			entity.render_correction = {-dx, -dy, -dz}
		}

		// Decay the prediction error independently of the moving target.
		if entity.render_correction != (datatypes.Vector3{}) {
			decay := math.exp(-CORRECTION_DECAY_RATE * delta_time)
			entity.render_correction = datatypes.Vec3_Multiply(entity.render_correction, f64(decay))
			if datatypes.Vec3_Magnitude_Squared(entity.render_correction) < 1e-6 {
				entity.render_correction = {}
			}
			frame = datatypes.CFrame_Add_Vector3(frame, entity.render_correction)
		}
		changed = changed || part.cframe != frame
		part.cframe = frame
		part.position = datatypes.Vector3{part.cframe.x, part.cframe.y, part.cframe.z}
	}
}
