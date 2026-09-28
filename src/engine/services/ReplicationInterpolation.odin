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

	for entity in service.entity_list {
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

		// Seed the dead-reckoning origin from the newest authoritative sample.
		//
		// last_frame is only ever written by the two branches below, so until one
		// of them has run it holds the zero CFrame: position at the world origin
		// with an all-zero rotation basis. That basis is singular, so a Part left
		// holding it has world bounds collapsed to a point (which the renderer
		// rejects as an empty AABB), and the origin position drops every Part in
		// that state on top of every other one. A client whose very first
		// interpolation pass for a Part takes the dead-reckoning branch therefore
		// put it at the origin with a degenerate basis instead of at the position
		// the server had just sent, and the jitter clamp below then snapped it
		// there because the distance from the real position to the origin is large.
		//
		// This used to be masked on the client: the client also ran its own
		// dynamic solver over these Parts, and the physics write-back replaced the
		// degenerate frame with a valid one every tick. With the client no longer
		// simulating Parts the server owns, the seeding has to be explicit.
		//
		// The newest sample is an authoritative transform the client has already
		// accepted, so seeding from it is exactly as trustworthy as the snap path
		// and can never be degenerate.
		if !entity.frame_seeded {
			entity.last_frame = latest.frame
			entity.last_velocity = datatypes.Vector3{0, 0, 0}
			entity.frame_seeded = true
		}

		// Pick the timebase the render target is expressed in.
		//
		// Samples are stamped with the server's snapshot tick, so the target has
		// to be in that same timebase for the sample walk below to mean anything.
		// Once a real clock offset has been measured, the target is derived from
		// the local clock shifted onto the server's, which is immune to the two
		// clocks drifting apart at different rates.
		//
		// Before the first time sync reply lands there is no offset, and the local
		// clock is not a substitute: a client that joins a server which has been
		// up for a while starts its own clock at zero while the server's tick is
		// already large. Anchoring to the local clock there would put the target
		// far behind the sample window, so the walk below would clamp to the
		// oldest buffered sample and render a stale position. Anchoring to the
		// newest sample received is correct on its own terms: it is the freshest
		// thing known, and it degrades to a slightly smaller interpolation delay
		// rather than to a wrong position.
		rate := f64(service.snapshot_rate)
		if rate <= 0 {rate = 20}
		target: f64
		if service.time_offset_measured {
			target =
				(f64(service.clock) + f64(service.time_offset)) * rate -
				f64(service.interpolation_delay_ticks)
		} else {
			target =
				f64(latest.tick) -
				f64(service.interpolation_delay_ticks) +
				f64(entity.sample_age) * rate
		}

		// -----------------------------------------------------------------------
		// Normal interpolation path: target is within the sample window.
		// -----------------------------------------------------------------------
		have_data := target <= f64(latest.tick) + 0.5
		frame := datatypes.CFrame{}
		// Whether the PREVIOUS pass was extrapolating. This has to be sampled
		// before the branch below, because the dead-reckoning arm increments
		// dr_age itself and so would otherwise report true on every pass that
		// extrapolates, which is the opposite of what this flag means.
		was_extrapolating := entity.dr_age > 0

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
			//
			// A sample pair straddling a teleport is not motion. Differentiating
			// across the discontinuity yields a huge but entirely fictional
			// velocity, and dead reckoning then drives the Part past where it
			// actually is. Because the server suppresses state that has not
			// changed, a Part that stopped moving sends nothing more, so the
			// client never receives the sample that would pull it back and it
			// sits permanently displaced. So a gap past the teleport threshold
			// contributes no velocity at all, which leaves dead reckoning holding
			// the last authoritative position instead of running off it.
			if len(entity.samples) >= 2 {
				prev := entity.samples[len(entity.samples) - 2]
				dt_ticks := f32(latest.tick - prev.tick)
				dx := latest.frame.x - prev.frame.x
				dy := latest.frame.y - prev.frame.y
				dz := latest.frame.z - prev.frame.z
				tele_sq := service.teleport_threshold * service.teleport_threshold
				if dx * dx + dy * dy + dz * dz > tele_sq {
					entity.last_velocity = datatypes.Vector3{0, 0, 0}
				} else if dt_ticks > 0 {
					inv := f32(service.snapshot_rate) / dt_ticks
					entity.last_velocity = datatypes.Vector3{dx * inv, dy * inv, dz * inv}
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
				// Too long without data — hold the last position the server
				// actually reported.
				//
				// The obvious choice here, last_frame, is the last EXTRAPOLATED
				// position, not the last known one, so it carries whatever the
				// velocity estimate was still paying out. For a Part that has
				// since stopped moving that is a fiction, and it becomes
				// permanent: the server suppresses state whose content has not
				// changed, so a stationary Part stops being sent and no later
				// sample ever arrives to pull the client back. The Part then sits
				// visibly displaced for the rest of the session.
				//
				// Returning to the newest authoritative sample instead matches
				// what this branch has always claimed to do, and bounds the error
				// to "the last thing the server said" rather than "a guess".
				frame = latest.frame
				entity.last_frame = frame
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
		// Committing the render target.
		//
		// The interpolated target is already smooth: it is a CFrame_Lerp between
		// two authoritative samples, walked by a clock that advances every frame.
		// So in the steady state the committed transform follows it directly.
		//
		// The blend below used to run on every frame that had any gap at all,
		// which turned it into a low-pass filter over the render target rather
		// than the one-shot smoothing it was meant to be. A per-frame positional
		// low-pass with gain `blend`, against a target advancing v*dt per frame,
		// settles into a steady-state lag of v*dt/blend. With SNAP_BLEND_RATE 8
		// that is v/8, so 125 ms of extra lag that scales with speed, on top of
		// the interpolation_delay_ticks the target already sits behind. A falling
		// body therefore rendered well behind where it actually was, and the
		// faster it moved the further behind it got.
		//
		// Smoothing is still wanted in exactly one place: the frame where a Part
		// comes back from dead-reckoning, where the target can jump and a direct
		// follow would pop. That is the only case that blends now.
		// -----------------------------------------------------------------------
		dx := frame.x - part.cframe.x
		dy := frame.y - part.cframe.y
		dz := frame.z - part.cframe.z
		dist_sq := dx * dx + dy * dy + dz * dz
		tele_sq := service.teleport_threshold * service.teleport_threshold
		// Only the frame that comes back from dead reckoning has a target that
		// can jump, so only that frame eases. This flag is the previous pass's
		// extrapolation state AND the presence of real samples this pass:
		// while extrapolating the target is already smooth, and blending it
		// would put the very lag this change removes straight back.
		recovering := was_extrapolating && have_data

		if dist_sq > tele_sq {
			// Large gap — snap immediately (could be a genuine teleport).
			part.cframe = frame
		} else if recovering && dist_sq > 0.0001 {
			// Re-entering from dead-reckoning — ease in rather than pop.
			blend := f32(clamp(f64(SNAP_BLEND_RATE) * f64(delta_time), 0, 1))
			part.cframe = datatypes.CFrame_Lerp(part.cframe, frame, blend)
		} else {
			// Steady state — the target is smooth, so follow it. A gap under the
			// teleport threshold is ordinary interpolation offset, not an error
			// that needs smoothing away.
			part.cframe = frame
		}
		// Always keep the position in sync with cframe for physics queries.
		part.position = datatypes.Vector3{part.cframe.x, part.cframe.y, part.cframe.z}
	}
}
