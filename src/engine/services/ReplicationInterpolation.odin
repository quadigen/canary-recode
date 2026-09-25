#+build !js
package services

import "core:math"
import classes "../classes"
import datatypes "../datatypes"

replication_render_interpolated :: proc(service: ^ReplicatorService, delta_time: f32) {
	if service.mode != .Client {return}
	players := cast(^Players)DataModel_Get_Service(service.data_model, "Players")

	// Maximum time (seconds) we trust dead-reckoning before giving up.
	// At 50 ms/frame and 20 Hz snapshots, two missed snapshots = 100 ms.
	// Cap at 300 ms to prevent wild extrapolation.
	DR_MAX_AGE :: f32(0.3)

	// Maximum displacement (studs) allowed per frame from dead-reckoning.
	// This prevents a parts launched at extreme speed from teleporting a client.
	DR_MAX_STEP :: f32(8.0)

	// Fraction of a snap that is smoothed per second instead of applied
	// instantly. A value of 8 means the residual halves in ~1/8 s.
	SNAP_BLEND_RATE :: f32(8.0)

	for &entity in service.entities {
		if entity.object == nil ||
		   entity.object.destroyed ||
		   !classes.Is_A(entity.object, "Part") {continue}

		// Skip parts owned by or belonging to the local player's character.
		if players != nil && players.local_player != nil {
			if entity.object.parent != nil &&
			   classes.Is_A(entity.object.parent, "CharacterModel") {
				model := cast(^classes.CharacterModel)entity.object.parent
				if model.owner_user_id == players.local_player.user_id {continue}
			} else if entity.owner_id == players.local_player.user_id {continue}
		}

		part := cast(^classes.Part)entity.object

		// No samples at all — nothing to interpolate or extrapolate.
		if len(entity.samples) == 0 {continue}

		entity.sample_age += delta_time
		latest := entity.samples[len(entity.samples) - 1]

		// The "target" tick we want to render at, lagging behind the latest
		// received tick by interpolation_delay_ticks.
		target :=
			f64(latest.tick) -
			f64(service.interpolation_delay_ticks) +
			f64(entity.sample_age) * f64(service.snapshot_rate)

		// -----------------------------------------------------------------------
		// Normal interpolation path: target is within the sample window.
		// -----------------------------------------------------------------------
		have_data := target <= f64(latest.tick) + 0.5
		frame := datatypes.CFrame{}

		if have_data {
			if target >= f64(latest.tick) {
				frame = latest.frame
			} else {
				// Walk the sample ring and lerp.
				found := false
				for index := 1; index < len(entity.samples); index += 1 {
					right := entity.samples[index]
					if target > f64(right.tick) {continue}
					left := entity.samples[index - 1]
					span := f64(right.tick - left.tick)
					if span > 0 {
						alpha := f32(clamp((target - f64(left.tick)) / span, 0, 1))
						frame = datatypes.CFrame_Lerp(left.frame, right.frame, alpha)
					} else {
						frame = right.frame
					}
					found = true
					break
				}
				if !found {frame = latest.frame}
			}

			// Estimate velocity from the two most recent samples so we have
			// something to extrapolate with if the buffer runs dry.
			if len(entity.samples) >= 2 {
				prev := entity.samples[len(entity.samples) - 2]
				dt_ticks := f32(latest.tick - prev.tick)
				if dt_ticks > 0 {
					inv := f32(service.snapshot_rate) / dt_ticks
					entity.last_velocity = datatypes.Vector3{
						(latest.frame.x - prev.frame.x) * inv,
						(latest.frame.y - prev.frame.y) * inv,
						(latest.frame.z - prev.frame.z) * inv,
					}
				}
			}
			entity.last_frame = frame
			entity.dr_age = 0
		} else {
			// -----------------------------------------------------------------------
			// Dead-reckoning path: no fresh snapshot in the buffer.
			// Extrapolate linearly from the last known frame using the estimated
			// velocity, capped to DR_MAX_AGE and DR_MAX_STEP per frame to prevent
			// runaway divergence.
			// -----------------------------------------------------------------------
			entity.dr_age += delta_time
			if entity.dr_age > DR_MAX_AGE {
				// Too long without data — freeze at last known position.
				frame = entity.last_frame
			} else {
				step_x := entity.last_velocity.x * delta_time
				step_y := entity.last_velocity.y * delta_time
				step_z := entity.last_velocity.z * delta_time
				// Clamp step magnitude per frame so a single dead-reckoning
				// step never moves a part more than DR_MAX_STEP studs.
				step_sq := step_x * step_x + step_y * step_y + step_z * step_z
				if step_sq > DR_MAX_STEP * DR_MAX_STEP {
					mag := math.sqrt(step_sq)
					if mag > 1e-12 {
						scale := DR_MAX_STEP / mag
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

		// -----------------------------------------------------------------------
		// Jitter clamping: when re-entering from dead-reckoning back into
		// normal interpolation, blend rather than snap if the gap is small.
		// A gap under teleport_threshold gets smoothed; above it we snap.
		// -----------------------------------------------------------------------
		dx := frame.x - part.cframe.x
		dy := frame.y - part.cframe.y
		dz := frame.z - part.cframe.z
		dist_sq := dx * dx + dy * dy + dz * dz
		tele_sq := service.teleport_threshold * service.teleport_threshold

		if dist_sq > tele_sq {
			// Large gap — snap immediately (could be a genuine teleport).
			part.cframe = frame
		} else if dist_sq > 0.0001 {
			// Small gap — blend toward target to suppress jitter.
			blend := f32(clamp(f64(SNAP_BLEND_RATE) * f64(delta_time), 0, 1))
			part.cframe = datatypes.CFrame_Lerp(part.cframe, frame, blend)
		}
		// Always keep the position in sync with cframe for physics queries.
		part.position = datatypes.Vector3{part.cframe.x, part.cframe.y, part.cframe.z}
	}
}
