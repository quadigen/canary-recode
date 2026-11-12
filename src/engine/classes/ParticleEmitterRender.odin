package classes

import assetstore "../assetstore"
import kineffi "../bindings"
import datatypes "../datatypes"
import enums "../enum"
import "core:c"
import "core:math"
import "core:math/rand"
import image "vendor:stb/image"

PARTICLE_EMITTER_LIMIT :: 2048
PARTICLE_DEGREES :: f32(math.PI / 180)

Emitter_Particle :: struct {
	position, velocity: datatypes.Vector3,
	age, lifetime:      f32,
	rotation, spin:     f32,
	size_variation:     f32,
	alpha_variation:    f32,
	flipbook_fps:       f32,
	flipbook_offset:    int,
}

particle_emitter_frame :: proc(
	emitter: ^ParticleEmitter,
) -> (
	datatypes.CFrame,
	datatypes.Vector3,
	bool,
) {
	parent := emitter.parent
	if parent == nil || parent.destroyed {return {}, {}, false}
	part := parent
	local_frame := datatypes.CFrame_Identity
	attached := Is_A_Class(parent, &Attachment_Class)
	if attached {
		attachment := cast(^Attachment)parent
		rotation := attachment.orientation
		local_frame = datatypes.CFrame_FromOrientation(
			rotation.x * PARTICLE_DEGREES,
			rotation.y * PARTICLE_DEGREES,
			rotation.z * PARTICLE_DEGREES,
		)
		local_frame = datatypes.CFrame_Add_Vector3(local_frame, attachment.position)
		part = parent.parent
	}
	if part == nil || part.destroyed || !Is_A_Class(part, &Part_Class) {return {}, {}, false}
	for ancestor := part.parent; ancestor != nil; ancestor = ancestor.parent {
		if Is_A(ancestor, "Workspace") {
			body := cast(^Part)part
			if attached {return datatypes.CFrame_Mul_CFrame(body.cframe, local_frame), {}, true}
			return body.cframe, body.size, true
		}
	}
	return {}, {}, false
}

particle_emitter_direction :: proc(
	face: enums.NormalId,
	spread: datatypes.Vector2,
) -> datatypes.Vector3 {
	directions := [enums.NormalId]datatypes.Vector3 {
		.Right  = {1, 0, 0},
		.Left   = {-1, 0, 0},
		.Top    = {0, 1, 0},
		.Bottom = {0, -1, 0},
		.Back   = {0, 0, 1},
		.Front  = {0, 0, -1},
	}
	forward := directions[face]
	reference := datatypes.Vector3_YAxis if forward.y == 0 else datatypes.Vector3_ZAxis
	right := datatypes.Vec3_Cross(reference, forward)
	up := datatypes.Vec3_Cross(forward, right)
	yaw := (rand.float32() - 0.5) * spread.X * PARTICLE_DEGREES
	pitch := (rand.float32() - 0.5) * spread.Y * PARTICLE_DEGREES
	return datatypes.Vec3_Add(
		datatypes.Vec3_Multiply(forward, math.cos(yaw) * math.cos(pitch)),
		datatypes.Vec3_Add(
			datatypes.Vec3_Multiply(right, math.sin(yaw) * math.cos(pitch)),
			datatypes.Vec3_Multiply(up, math.sin(pitch)),
		),
	)
}

particle_emitter_sample :: proc(range: datatypes.NumberRange) -> f32 {
	return range.Min + rand.float32() * (range.Max - range.Min)
}

particle_emitter_emit :: proc(emitter: ^ParticleEmitter, count: int) {
	frame, size, in_world := particle_emitter_frame(emitter)
	if !in_world {return}
	particle_emitter_spawn(emitter, frame, size, count)
}

particle_emitter_spawn :: proc(
	emitter: ^ParticleEmitter,
	frame: datatypes.CFrame,
	size: datatypes.Vector3,
	count: int,
) {
	for _ in 0 ..< min(count, PARTICLE_EMITTER_LIMIT - len(emitter.particles)) {
		lifetime := particle_emitter_sample(emitter.lifetime)
		if lifetime <= 0 {continue}
		local_position := datatypes.Vector3 {
			(rand.float32() - 0.5) * size.x,
			(rand.float32() - 0.5) * size.y,
			(rand.float32() - 0.5) * size.z,
		}
		direction := particle_emitter_direction(emitter.emission_direction, emitter.spread_angle)
		append(
			&emitter.particles,
			Emitter_Particle {
				position = datatypes.CFrame_PointToWorldSpace(frame, local_position),
				velocity = datatypes.Vec3_Multiply(
					datatypes.CFrame_VectorToWorldSpace(frame, direction),
					particle_emitter_sample(emitter.speed),
				),
				lifetime = lifetime,
				rotation = particle_emitter_sample(emitter.rotation) * PARTICLE_DEGREES,
				spin = particle_emitter_sample(emitter.rot_speed) * PARTICLE_DEGREES,
				size_variation = rand.float32() * 2 - 1,
				alpha_variation = rand.float32() * 2 - 1,
				flipbook_fps = particle_emitter_sample(emitter.flipbook_framerate),
				flipbook_offset = int(rand.float32() * 64),
			},
		)
	}
	if len(emitter.particles) > 0 {Render_3D_Mark_Dirty()}
}

ParticleEmitter_Step :: proc(registry: ^Registry, delta_time: f32, wind: datatypes.Vector3) {
	descriptor := Find_Class(registry, "ParticleEmitter")
	if descriptor == nil || !(delta_time > 0) {return}
	dt := min(delta_time, 0.1)
	for object in descriptor.instances {
		if object == nil || object.destroyed {continue}
		emitter := cast(^ParticleEmitter)object
		if len(emitter.particles) > 0 {
			Render_3D_Mark_Dirty()
			target := wind if emitter.wind_affects_drag else datatypes.Vector3{}
			retention := math.exp(-emitter.drag * dt)
			survivors := 0
			for current in emitter.particles {
				particle := current
				particle.age += dt
				if particle.age >= particle.lifetime {continue}
				particle.velocity = datatypes.Vec3_Add(
					particle.velocity,
					datatypes.Vec3_Multiply(emitter.acceleration, dt),
				)
				particle.velocity = datatypes.Vec3_Add(
					target,
					datatypes.Vec3_Multiply(
						datatypes.Vec3_Subtract(particle.velocity, target),
						retention,
					),
				)
				particle.position = datatypes.Vec3_Add(
					particle.position,
					datatypes.Vec3_Multiply(particle.velocity, dt),
				)
				emitter.particles[survivors] = particle
				survivors += 1
			}
			resize(&emitter.particles, survivors)
		}
		if !emitter.enabled || emitter.rate <= 0 {continue}
		frame, size, in_world := particle_emitter_frame(emitter)
		if !in_world {continue}
		emitter.emission_credit += emitter.rate * dt
		count := int(emitter.emission_credit)
		emitter.emission_credit -= f32(count)
		if count > 0 {particle_emitter_spawn(emitter, frame, size, count)}
	}
}

particle_emitter_release_texture :: proc(emitter: ^ParticleEmitter, renderer: ^Renderer_Object) {
	if emitter.native_texture != nil &&
	   renderer != nil &&
	   renderer.Filament != nil &&
	   renderer.Filament == emitter.texture_context {
		_ = kineffi.Kine_Filament_DestroyTex(renderer.Filament, emitter.native_texture)
	}
	emitter.native_texture = nil
	emitter.texture_context = nil
}

particle_emitter_load_texture :: proc(emitter: ^ParticleEmitter, renderer: ^Renderer_Object) {
	particle_emitter_release_texture(emitter, renderer)
	emitter.texture_context = renderer.Filament
	when ODIN_OS != .JS {
		width, height, channels: c.int
		pixels: [^]u8
		if data, found := Texture_Resolve_Bytes(emitter.texture); found && len(data) > 0 {
			if len(data) <= int(max(c.int)) {
				pixels = image.load_from_memory(
					raw_data(data),
					c.int(len(data)),
					&width,
					&height,
					&channels,
					4,
				)
			}
		} else {
			path := assetstore.Resolve_C_Path(emitter.texture)
			defer delete(path)
			if path != nil {pixels = image.load(path, &width, &height, &channels, 4)}
		}
		if pixels == nil {
			assetstore.Report_Missing_Asset(emitter.texture, "ParticleEmitter texture")
			return
		}
		defer image.image_free(pixels)
		emitter.native_texture = kineffi.Kine_Filament_CreateTexFromPixels(
			renderer.Filament,
			i32(width),
			i32(height),
			i32(width) * 4,
			pixels,
		)
	}
}

particle_emitter_grid :: proc(layout: enums.ParticleFlipbookLayout) -> int {
	#partial switch layout {
	case .Grid2x2:
		return 2
	case .Grid4x4:
		return 4
	case .Grid8x8:
		return 8
	}
	return 1
}

particle_emitter_flipbook_frame :: proc(
	emitter: ^ParticleEmitter,
	particle: Emitter_Particle,
	frames: int,
) -> int {
	step := int(particle.age * particle.flipbook_fps)
	switch emitter.flipbook_mode {
	case .Loop:
		return step % frames
	case .OneShot:
		return min(int(particle.age / particle.lifetime * f32(frames)), frames - 1)
	case .PingPong:
		period := (frames - 1) * 2
		position := step % period
		return min(position, period - position)
	case .Random:
		return (particle.flipbook_offset + step * 17) % frames
	}
	return 0
}

particle_emitter_channel :: proc(value: f32) -> u8 {
	if math.is_nan(value) {return 0}
	return u8(clamp(value, 0, 1) * 255 + 0.5)
}

ParticleEmitter_Render :: proc(registry: ^Registry, renderer: ^Renderer_Object) {
	if renderer == nil || renderer.Filament == nil || !renderer.HasWorldToView {return}
	descriptor := Find_Class(registry, "ParticleEmitter")
	if descriptor == nil {return}
	view := renderer.WorldToView
	right := datatypes.Vector3{view[3], view[4], view[5]}
	up := datatypes.Vector3{view[6], view[7], view[8]}
	back := datatypes.Vector3{view[9], view[10], view[11]}
	for object in descriptor.instances {
		if object == nil || object.destroyed {continue}
		emitter := cast(^ParticleEmitter)object
		if len(emitter.particles) == 0 {continue}
		_, _, in_world := particle_emitter_frame(emitter)
		if !in_world {continue}
		if emitter.texture != "" && emitter.texture_context != renderer.Filament {
			particle_emitter_load_texture(emitter, renderer)
		}
		if emitter.texture != "" && emitter.native_texture == nil {continue}

		grid := particle_emitter_grid(emitter.flipbook_layout)
		clear(&emitter.draw_items)
		for particle in emitter.particles {
			age := particle.age / particle.lifetime
			size, size_envelope := datatypes.NumberSequence_At(emitter.size, age)
			size += size_envelope * particle.size_variation
			transparency, alpha_envelope := datatypes.NumberSequence_At(emitter.transparency, age)
			alpha := particle_emitter_channel(
				1 - transparency - alpha_envelope * particle.alpha_variation,
			)
			if !(size > 0) || math.is_inf(size) || alpha == 0 {continue}
			tint := datatypes.ColorSequence_At(emitter.color, age)
			angle := particle.rotation + particle.spin * particle.age
			sin, cos := math.sin(angle) * size, math.cos(angle) * size
			x_axis := datatypes.Vec3_Add(
				datatypes.Vec3_Multiply(right, cos),
				datatypes.Vec3_Multiply(up, sin),
			)
			y_axis := datatypes.Vec3_Add(
				datatypes.Vec3_Multiply(right, -sin),
				datatypes.Vec3_Multiply(up, cos),
			)
			position := datatypes.Vec3_Add(
				particle.position,
				datatypes.Vec3_Multiply(back, emitter.z_offset),
			)
			item := kineffi.KineFilamentParticleItem {
				transform = {
					x_axis.x,
					y_axis.x,
					back.x,
					position.x,
					x_axis.y,
					y_axis.y,
					back.y,
					position.y,
					x_axis.z,
					y_axis.z,
					back.z,
					position.z,
					0,
					0,
					0,
					1,
				},
				r         = particle_emitter_channel(tint.R * emitter.brightness),
				g         = particle_emitter_channel(tint.G * emitter.brightness),
				b         = particle_emitter_channel(tint.B * emitter.brightness),
				a         = alpha,
			}
			if grid == 1 {
				append(&emitter.draw_items, item)
			} else {
				frame := particle_emitter_flipbook_frame(emitter, particle, grid * grid)
				scale := 1 / f32(grid)
				kineffi.Kine_Filament_DrawParticles(
					renderer.Filament,
					emitter.native_texture,
					&item,
					1,
					scale,
					scale,
					f32(frame % grid) * scale,
					f32(frame / grid) * scale,
					false,
					false,
				)
			}
		}
		if len(emitter.draw_items) > 0 {
			kineffi.Kine_Filament_DrawParticles(
				renderer.Filament,
				emitter.native_texture,
				raw_data(emitter.draw_items),
				u32(len(emitter.draw_items)),
				1,
				1,
				0,
				0,
				false,
				false,
			)
		}
	}
}
