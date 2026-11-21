package classes

import kineffi "../bindings"
import datatypes "../datatypes"
import jolt "../physics"
import "core:math"

PARTICLE_COLLISION_MAX_IMPACTS :: 4
PARTICLE_COLLISION_SKIN :: 0.001
PARTICLE_COLLISION_BOUNCE_THRESHOLD :: 0.5

ParticleEmitter_Has_Collisions :: proc(registry: ^Registry) -> bool {
	descriptor := Find_Class(registry, "ParticleEmitter")
	if descriptor == nil {return false}
	for object in descriptor.instances {
		if object == nil || object.destroyed {continue}
		emitter := cast(^ParticleEmitter)object
		if emitter.collision_enabled && len(emitter.particles) > 0 {
			_, _, in_world := particle_emitter_frame(emitter)
			if in_world {return true}
		}
	}
	return false
}

particle_emitter_collide :: proc(
	emitter: ^ParticleEmitter,
	particle: ^Emitter_Particle,
	system: ^jolt.System,
	sphere: kineffi.JPH_ShapeRef,
	excluded: []kineffi.JPH_BodyID,
	dt: f32,
) {
	remaining := f64(dt)
	for _ in 0 ..< PARTICLE_COLLISION_MAX_IMPACTS {
		displacement := datatypes.Vec3_Multiply(particle.velocity, remaining)
		distance := datatypes.Vec3_Magnitude(displacement)
		depth: f32
		hit, collided := jolt.System_Cast_Shape(
			system,
			{particle.position.x, particle.position.y, particle.position.z},
			{f32(displacement.x), f32(displacement.y), f32(displacement.z)},
			sphere,
			excluded,
			.Exclude,
			f32(distance) + emitter.collision_radius,
			&depth,
		)
		if !collided {
			particle.position = datatypes.Vec3_Add(particle.position, displacement)
			return
		}
		normal := datatypes.Vector3{f64(hit.normal.x), f64(hit.normal.y), f64(hit.normal.z)}
		length := datatypes.Vec3_Magnitude(normal)
		if !(length > 0.000001) || math.is_inf(length) {return}
		normal = datatypes.Vec3_Multiply(normal, 1 / length)
		fraction := f64(clamp(hit.fraction, 0, 1))
		particle.position = datatypes.Vec3_Add(
			datatypes.Vec3_Add(particle.position, datatypes.Vec3_Multiply(displacement, fraction)),
			datatypes.Vec3_Multiply(normal, f64(max(depth, 0)) + PARTICLE_COLLISION_SKIN),
		)
		surface_velocity: datatypes.Vector3
		bi := system.body_interface
		if kineffi.JPH_BodyInterface_GetMotionType(bi, hit.bodyID) != .Static {
			linear, angular: kineffi.JPH_Vec3
			center: kineffi.JPH_RVec3
			kineffi.JPH_BodyInterface_GetLinearVelocity(bi, hit.bodyID, &linear)
			kineffi.JPH_BodyInterface_GetAngularVelocity(bi, hit.bodyID, &angular)
			kineffi.JPH_BodyInterface_GetCenterOfMassPosition(bi, hit.bodyID, &center)
			contact := datatypes.Vec3_Subtract(
				particle.position,
				datatypes.Vec3_Multiply(normal, f64(emitter.collision_radius)),
			)
			offset := datatypes.Vec3_Subtract(contact, {center.x, center.y, center.z})
			surface_velocity = datatypes.Vec3_Add(
				{f64(linear.x), f64(linear.y), f64(linear.z)},
				datatypes.Vec3_Cross({f64(angular.x), f64(angular.y), f64(angular.z)}, offset),
			)
		}
		relative := datatypes.Vec3_Subtract(particle.velocity, surface_velocity)
		speed := datatypes.Vec3_Dot(relative, normal)
		if speed < 0 {
			tangent := datatypes.Vec3_Subtract(relative, datatypes.Vec3_Multiply(normal, speed))
			bounce :=
				-speed * f64(emitter.collision_restitution) if -speed >= PARTICLE_COLLISION_BOUNCE_THRESHOLD else 0
			particle.velocity = datatypes.Vec3_Add(
				surface_velocity,
				datatypes.Vec3_Add(
					datatypes.Vec3_Multiply(tangent, 1 - f64(emitter.collision_friction)),
					datatypes.Vec3_Multiply(normal, bounce),
				),
			)
		}
		remaining *= 1 - fraction
		if remaining <= 0.000001 {return}
	}

}
