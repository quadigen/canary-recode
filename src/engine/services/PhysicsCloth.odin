package services

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import jolt "../physics"
import tracy "../util/odin-tracy"
import "core:math"
import "core:math/linalg"
import "core:slice"

CLOTH_COLLISION_RADIUS :: 0.04
CLOTH_COLLISION_SAMPLE_SPACING :: 0.75
CLOTH_COLLISION_MAX_LINK_SAMPLES :: 8
CLOTH_MAX_SUBSTEP :: f32(1.0 / 120.0)

physics_replication_client :: proc(data_model: ^DataModel) -> bool {
	if data_model == nil {return false}
	replicator := cast(^ReplicatorService)DataModel_Get_Service(data_model, "ReplicatorService")
	return replicator != nil && replicator.mode == .Client
}

Physics_Step_Cloth :: proc(service: ^Physics, workspace: ^Workspace, delta_time: f32) {
	tracy.ZoneNC("Cloth Physics", 0x61AFEF)
	if physics_replication_client(service.data_model) {return}
	descriptor := classes.Find_Class(service.signal_registry, "Cloth")
	if descriptor == nil || len(descriptor.instances) == 0 || !(delta_time > 0) {return}

	candidates := &service.cloth_candidates
	clear(candidates)
	clear(&service.cloth_jobs)
	sphere: kineffi.JPH_ShapeRef
	prepared_collisions := false

	for object in descriptor.instances {
		if object.destroyed {continue}
		cloth := cast(^classes.Cloth)object
		anchors, pin_count := classes.Cloth_Anchors(cloth, &workspace.object)
		if !cloth.enabled || !classes.Is_Descendant_Of(object, &workspace.object) ||
		   (pin_count == 0 && !cloth.initialized && !cloth.custom_pins && cloth.cloth_type == .Flat) {
			cloth.impulse = {}
			continue
		}
		if cloth.can_collide && !prepared_collisions {
			prepared_collisions = true
			for _, id in service.terrain_bodies {
				if id != kineffi.JPH_BODY_ID_INVALID {append(candidates, id)}
			}
			for body in service.bodies {
				part := cast(^classes.Part)body.object
				if part != nil &&
				   !part.destroyed &&
				   part.can_collide &&
				   part.material != .Water &&
				   body.body_id != kineffi.JPH_BODY_ID_INVALID {
					append(candidates, body.body_id)
				}
			}
			for body_id in service.character_capsules {append(candidates, body_id)}
			if len(candidates^) > 0 {
				slice.sort(candidates^[:])
				if service.cloth_collision_shape == nil {
					service.cloth_collision_shape = kineffi.JPH_SphereShape_Create(CLOTH_COLLISION_RADIUS)
				}
				sphere = service.cloth_collision_shape
			}
		}
		physics_prepare_cloth(cloth, &workspace.object, anchors, pin_count)
		job := Cloth_Physics_Job {
			cloth = cloth,
			wind = workspace.global_wind,
			gravity = service.gravity,
			iterations = physics_cloth_iterations(service, workspace, cloth),
			delta_time = min(delta_time, 0.1),
		}
		if cloth.can_collide && sphere != nil {
			physics_step_cloth(job, service, sphere, candidates^[:])
		} else if len(cloth.particles) >= 256 {
			append(&service.cloth_jobs, job)
		} else {
			physics_step_cloth(job)
		}
	}
	physics_run_cloth_jobs(service)
}

physics_prepare_cloth :: proc(
	cloth: ^classes.Cloth,
	workspace: ^classes.Object,
	anchors: [2]datatypes.CFrame,
	pin_count: int,
) {
	reset := !cloth.initialized || (!cloth.custom_pins && cloth.cloth_type == .Flat && cloth.pin_count != pin_count && pin_count > 0)
	if reset {classes.Cloth_Initialize(cloth, anchors, pin_count, workspace)}
	classes.Cloth_Pin_Targets(cloth, workspace, anchors, pin_count)
	if !cloth.custom_pins && cloth.cloth_type == .Flat && pin_count == 2 {
		width := classes.Cloth_Width(cloth, cloth.pin_targets[cloth.segments_x] - cloth.pin_targets[0])
		if abs(width - cloth.width) > 0.00001 {
			// Legacy Flat cloth changes its rest width as the rail span changes.
			axis := linalg.normalize(cloth.rest[cloth.segments_x] - cloth.rest[0])
			for &position in cloth.rest {
				position += axis * (linalg.dot(position - cloth.rest[0], axis) * (width / cloth.width - 1))
			}
			cloth.width = width
			classes.Cloth_Build_Links(cloth)
		}
	}
	cloth.pose_anchors = anchors
	cloth.pin_count = pin_count
}

Cloth_Physics_Job :: struct {
	cloth: ^classes.Cloth,
	wind: datatypes.Vector3,
	gravity, delta_time: f32,
	iterations: int,
}

physics_step_cloth :: proc(
	job: Cloth_Physics_Job,
	service: ^Physics = nil,
	sphere: kineffi.JPH_ShapeRef = nil,
	candidates: []kineffi.JPH_BodyID = nil,
) {
	cloth := job.cloth
	moved, any_free := false, false
	for particle, i in cloth.particles {
		target := cloth.pin_targets[i]
		if cloth.active_weights[i] > 0 && target != particle.position {moved = true}
		if !cloth.pinned[i] {any_free = true}
		cloth.pin_starts[i] = particle.position
	}
	acceleration := cloth.force / cloth.mass + [3]f32{0, -job.gravity, 0}
	wind_velocity := [3]f32{f32(job.wind.x), f32(job.wind.y), f32(job.wind.z)}
	kick := cloth.impulse / cloth.mass
	cloth.impulse = {}
	if moved || kick != {} || acceleration != cloth.sleep_acceleration || wind_velocity != cloth.sleep_wind {
		cloth.sleep_frames = 0
	}
	cloth.sleep_acceleration, cloth.sleep_wind = acceleration, wind_velocity
	if (!any_free && !moved) || (sphere == nil && cloth.sleep_frames >= 45) {return}
	cloth.pose_source = .Simulation
	delta_time := job.delta_time
	substeps := int(math.ceil(delta_time / CLOTH_MAX_SUBSTEP))
	dt := delta_time / f32(substeps)
	drag := math.exp(-cloth.damping * dt)
	inverse_mass := 1 / cloth.mass
	// Convert normalized stiffness to XPBD compliance before the iteration loop.
	compliances: [classes.Cloth_Link_Kind]f32
	stiffnesses := [classes.Cloth_Link_Kind]f32{
		.Stretch = cloth.stretch_stiffness, .Shear = cloth.shear_stiffness, .Bend = cloth.bend_stiffness,
		.Fold = cloth.fold_stiffness if cloth.fold_count > 0 && cloth.fold_depth > 0 else cloth.bend_stiffness,
	}
	for stiffness, kind in stiffnesses {
		compliances[kind] = physics_cloth_compliance(stiffness, dt)
	}
	for &link in cloth.links {link.compliance = compliances[link.kind]}
	previous := cloth.previous
	for substep in 1 ..= substeps {
		t := f32(substep) / f32(substeps)
		for particle, i in cloth.particles {previous[i] = particle.position}
		for &particle, i in cloth.particles {
			if cloth.pinned[i] {
				particle.position = cloth.pin_starts[i] + (cloth.pin_targets[i] - cloth.pin_starts[i]) * t
				if substep == substeps {particle.position = cloth.pin_targets[i]}
				particle.velocity = {}
				continue
			}
			air := physics_cloth_air_drag(cloth, i, wind_velocity - particle.velocity)
			for axis in 0 ..< 3 {
				a := clamp(acceleration[axis] + air[axis], -10000, 10000)
				v := clamp(particle.velocity[axis] + kick[axis], -500, 500)
				particle.position[axis] += (v * drag + a * dt) * dt
			}
		}
		kick = {}
		physics_solve_cloth_links(cloth, job.iterations, inverse_mass, dt, t)
		if cloth.self_collision {physics_cloth_self_collision(cloth)}
		for &particle, i in cloth.particles {
			if cloth.pinned[i] {continue}
			particle.velocity = (particle.position - previous[i]) / dt
			if sphere != nil {
				hit := physics_collide_cloth_particle(
					service,
					sphere,
					candidates,
					cloth.simulation_origin,
					previous[i],
					&particle,
					dt,
				)
				if hit != kineffi.JPH_BODY_ID_INVALID {
					physics_report_deformable_contact(service, &cloth.object, hit)
				}
			}
		}
		if sphere != nil {
			physics_collide_cloth_wide_links(cloth, service, sphere, candidates, previous, dt)
		}
	}
	settled := sphere == nil
	for particle, i in cloth.particles {
		drift := particle.position - previous[i]
		if linalg.dot(drift, drift) > 0.00000004 {settled = false; break}
	}
	cloth.sleep_frames = cloth.sleep_frames + 1 if settled else 0
	cloth.revision += 1
}

// Wide cloth can have a gap between particle colliders large enough for a
// character to pass through. Sample the links without changing the mesh or
// its replicated particle layout.
physics_collide_cloth_wide_links :: proc(
	cloth: ^classes.Cloth,
	service: ^Physics,
	sphere: kineffi.JPH_ShapeRef,
	candidates: []kineffi.JPH_BodyID,
	previous: [][3]f32,
	dt: f32,
) {
	stride := cloth.segments_x + 1
	for axis in 0..<2 {
		step := 1 if axis == 0 else stride
		length := (cloth.width if axis == 0 else cloth.size.Y) / f32(cloth.segments_x if axis == 0 else cloth.segments_y)
		samples := clamp(int(math.ceil(length / CLOTH_COLLISION_SAMPLE_SPACING)), 1, CLOTH_COLLISION_MAX_LINK_SAMPLES)
		if samples == 1 {continue}
		for a in 0..<len(cloth.particles) {
			if (a % stride == cloth.segments_x && axis == 0) ||
			   (a / stride == cloth.segments_y && axis == 1) {continue}
			b := a + step
			free_a := !cloth.pinned[a]
			free_b := !cloth.pinned[b]
			if !free_a && !free_b {continue}
			for i in 1..<samples {
				t := f32(i) / f32(samples)
				s := 1 - t
				old_position := previous[a] * s + previous[b] * t
				position := cloth.particles[a].position * s + cloth.particles[b].position * t
				velocity := cloth.particles[a].velocity * s + cloth.particles[b].velocity * t
				sample := classes.Cloth_Particle{position, velocity}
				hit := physics_collide_cloth_particle(service, sphere, candidates, cloth.simulation_origin, old_position, &sample, dt)
				if hit == kineffi.JPH_BODY_ID_INVALID {continue}
				physics_report_deformable_contact(service, &cloth.object, hit)
				weight_a := s if free_a else 0
				weight_b := t if free_b else 0
				total := weight_a * s + weight_b * t
				correction := (sample.position - position) / total
				kick := (sample.velocity - velocity) / total
				cloth.particles[a].position += correction * weight_a
				cloth.particles[b].position += correction * weight_b
				cloth.particles[a].velocity += kick * weight_a
				cloth.particles[b].velocity += kick * weight_b
			}
		}
	}
}

physics_cloth_iterations :: proc(service: ^Physics, workspace: ^Workspace, cloth: ^classes.Cloth) -> int {
	camera := workspace.current_camera
	if camera == nil || cloth.can_collide || !cloth.initialized {return cloth.solver_iterations}
	if service.data_model != nil {
		replicator := cast(^ReplicatorService)DataModel_Get_Service(service.data_model, "ReplicatorService")
		if replicator != nil && replicator.mode == .Server {return cloth.solver_iterations}
	}
	delta := datatypes.Vec3_Subtract(classes.Cloth_World_Pin(cloth), datatypes.CFrame_Position(camera.CFrame))
	sq := delta.x * delta.x + delta.y * delta.y + delta.z * delta.z
	if sq > 300 * 300 {return min(cloth.solver_iterations, 2)}
	if sq > 150 * 150 {return max(1, cloth.solver_iterations / 2)}
	return cloth.solver_iterations
}

physics_cloth_air_drag :: proc(cloth: ^classes.Cloth, i: int, relative_wind: [3]f32) -> [3]f32 {
	if linalg.dot(relative_wind, relative_wind) < 0.000001 {return {}}
	stride := cloth.segments_x + 1
	column, row := i % stride, i / stride
	left, right := max(column - 1, 0), min(column + 1, cloth.segments_x)
	top, bottom := max(row - 1, 0), min(row + 1, cloth.segments_y)
	dx := cloth.previous[row * stride + right] - cloth.previous[row * stride + left]
	dy := cloth.previous[bottom * stride + column] - cloth.previous[top * stride + column]
	normal := linalg.cross(dx, dy)
	area := linalg.dot(normal, normal)
	if area < 1.0e-12 {return relative_wind * 0.12}
	normal /= math.sqrt(area)
	pressure := linalg.dot(relative_wind, normal)
	return relative_wind * 0.12 + normal * pressure * (0.38 + min(abs(pressure), 80) * 0.01)
}

physics_cloth_compliance :: proc(stiffness, dt: f32) -> f32 {
	if stiffness <= 0 {return -1}
	return (1 - stiffness) / stiffness * 0.00002 / (dt * dt)
}

physics_solve_cloth_links :: proc(cloth: ^classes.Cloth, iterations: int, inverse_mass, dt, fraction: f32) {
	tracy.ZoneNC("Cloth XPBD", 0x61AFEF)
	for &link in cloth.links {link.lambda = 0}
	for &lambda in cloth.pin_links {lambda = 0}
	for _ in 0..<iterations {
		for &link in cloth.links {
			if link.compliance < 0 {continue}
			a, b := link.a, link.b
			weight_a := inverse_mass if !cloth.pinned[a] else 0
			weight_b := inverse_mass if !cloth.pinned[b] else 0
			if weight_a + weight_b == 0 {continue}
			delta := cloth.particles[b].position - cloth.particles[a].position
			length := linalg.length(delta)
			if !(length > 0.000001) {continue}
			change := (link.length - length - link.compliance * link.lambda) / (weight_a + weight_b + link.compliance)
			link.lambda += change
			correction := delta * (change / length)
			cloth.particles[a].position -= correction * weight_a
			cloth.particles[b].position += correction * weight_b
		}
		if !cloth.custom_pins {continue}
		for weight, i in cloth.active_weights {
			if weight <= 0 || weight >= 1 {continue}
			target := cloth.pin_starts[i] + (cloth.pin_targets[i] - cloth.pin_starts[i]) * fraction
			delta := cloth.particles[i].position - target
			length := linalg.length(delta)
			if !(length > 0.000001) {continue}
			alpha := physics_cloth_compliance(weight, dt)
			change := (-length - alpha * cloth.pin_links[i]) / (inverse_mass + alpha)
			cloth.pin_links[i] += change
			cloth.particles[i].position += delta * (change * inverse_mass / length)
		}
	}
}

physics_cloth_hash :: proc(cell: [3]int, buckets: int) -> int {
	hash := (u32(cell.x) * 73856093) ~ (u32(cell.y) * 19349663) ~ (u32(cell.z) * 83492791)
	return int(hash % u32(buckets))
}

physics_cloth_self_collision :: proc(cloth: ^classes.Cloth) {
	tracy.ZoneNC("Cloth Self Collision", 0x61AFEF)
	spacing := min(cloth.width / f32(cloth.segments_x), cloth.size.Y / f32(cloth.segments_y))
	diameter := min(2 * f32(CLOTH_COLLISION_RADIUS), spacing * 0.75)
	for &head in cloth.self_heads {head = -1}
	for particle, i in cloth.particles {
		cell: [3]int
		for axis in 0..<3 {cell[axis] = int(math.floor(particle.position[axis] / diameter))}
		bucket := physics_cloth_hash(cell, len(cloth.self_heads))
		cloth.self_positions[i] = particle.position
		cloth.self_cells[i] = cell
		cloth.self_next[i] = cloth.self_heads[bucket]
		cloth.self_heads[bucket] = i
	}
	stride := cloth.segments_x + 1
	for cell, a in cloth.self_cells {
		for y in -1..=1 {
			for x in -1..=1 {
				for z in -1..=1 {
					near := cell + [3]int{x, y, z}
					bucket := physics_cloth_hash(near, len(cloth.self_heads))
					for b := cloth.self_heads[bucket]; b >= 0; b = cloth.self_next[b] {
						if b <= a || cloth.self_cells[b] != near || (cloth.pinned[a] && cloth.pinned[b]) {continue}
						if abs(a % stride - b % stride) <= 1 && abs(a / stride - b / stride) <= 1 {continue}
						delta := cloth.self_positions[b] - cloth.self_positions[a]
						sq := linalg.dot(delta, delta)
						if sq >= diameter * diameter {continue}
						length := math.sqrt(sq)
						axis := delta / length if length > 0.000001 else [3]f32{0, 0, 1}
						share: f32 = 1.0 if cloth.pinned[a] || cloth.pinned[b] else 0.5
						// Resolve at the current position while retaining the initial hash.
						separation := linalg.dot(cloth.particles[b].position - cloth.particles[a].position, axis)
						if separation >= diameter {continue}
						correction := axis * clamp(diameter - separation, 0, diameter) * share
						if !cloth.pinned[a] {cloth.particles[a].position -= correction}
						if !cloth.pinned[b] {cloth.particles[b].position += correction}
					}
				}
			}
		}
	}
}

physics_collide_cloth_particle :: proc(
	service: ^Physics,
	sphere: kineffi.JPH_ShapeRef,
	candidates: []kineffi.JPH_BodyID,
	origin: datatypes.Vector3,
	previous: [3]f32,
	particle: ^classes.Cloth_Particle,
	dt: f32,
) -> kineffi.JPH_BodyID {
	displacement := particle.position - previous
	penetration_depth: f32
	hit, collided := jolt.System_Cast_Shape(
		&service.system,
		{origin.x+f64(previous.x), origin.y+f64(previous.y), origin.z+f64(previous.z)},
		{displacement.x, displacement.y, displacement.z},
		sphere,
		candidates,
		.Include_Sorted,
		linalg.length(displacement) + CLOTH_COLLISION_RADIUS,
		&penetration_depth,
	)
	if !collided {return kineffi.JPH_BODY_ID_INVALID}
	normal := linalg.normalize([3]f32{hit.normal.x, hit.normal.y, hit.normal.z})
	if !(linalg.dot(normal, normal) > 0) {return kineffi.JPH_BODY_ID_INVALID}

	// A moving collider can already overlap the sphere when the cast starts.
	skin := max(penetration_depth, 0) + 0.001
	particle.position = previous + displacement * clamp(hit.fraction, 0, 1) + normal * skin

	linear, angular: kineffi.JPH_Vec3
	center: kineffi.JPH_RVec3
	bi := service.system.body_interface
	kineffi.JPH_BodyInterface_GetLinearVelocity(bi, hit.bodyID, &linear)
	kineffi.JPH_BodyInterface_GetAngularVelocity(bi, hit.bodyID, &angular)
	kineffi.JPH_BodyInterface_GetCenterOfMassPosition(bi, hit.bodyID, &center)
	offset := particle.position - [3]f32{f32(center.x-origin.x), f32(center.y-origin.y), f32(center.z-origin.z)}
	surface_velocity :=
		[3]f32{linear.x, linear.y, linear.z} +
		linalg.cross([3]f32{angular.x, angular.y, angular.z}, offset)
	relative := particle.velocity - surface_velocity
	speed := linalg.dot(relative, normal)
	tangent := relative - normal * speed
	particle.velocity = surface_velocity + normal * max(speed, 0) + tangent * math.exp(-10 * dt)
	return hit.bodyID
}
