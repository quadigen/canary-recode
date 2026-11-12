package services

import kineffi "../bindings"
import classes "../classes"
import datatypes "../datatypes"
import jolt "../physics"
import "core:math"
import "core:math/linalg"

CLOTH_COLLISION_RADIUS :: 0.04
CLOTH_SOLVER_ITERATIONS :: 8
CLOTH_MAX_SUBSTEP :: f32(1.0 / 120.0)

physics_replication_client :: proc(data_model: ^DataModel) -> bool {
	if data_model == nil {return false}
	replicator := cast(^ReplicatorService)DataModel_Get_Service(data_model, "ReplicatorService")
	return replicator != nil && replicator.mode == .Client
}

Physics_Step_Cloth :: proc(service: ^Physics, workspace: ^Workspace, delta_time: f32) {
	if physics_replication_client(service.data_model) {return}
	descriptor := classes.Find_Class(service.signal_registry, "Cloth")
	if descriptor == nil || len(descriptor.instances) == 0 || !(delta_time > 0) {return}

	candidates: [dynamic]kineffi.JPH_BodyID
	defer delete(candidates)
	sphere: kineffi.JPH_ShapeRef
	defer if sphere != nil {kineffi.JPH_Shape_Destroy(sphere)}
	prepared_collisions := false

	for object in descriptor.instances {
		if object.destroyed {continue}
		cloth := cast(^classes.Cloth)object
		anchors, pin_count := classes.Cloth_Anchors(cloth, &workspace.object)
		if pin_count == 0 || !cloth.enabled || !classes.Is_Descendant_Of(object, &workspace.object) {
			cloth.initialized = false
			cloth.impulse = {}
			continue
		}
		if cloth.can_collide && !prepared_collisions {
			prepared_collisions = true
			for _, id in service.terrain_bodies {
				if id != kineffi.JPH_BODY_ID_INVALID {append(&candidates, id)}
			}
			for body in service.bodies {
				part := cast(^classes.Part)body.object
				if part != nil &&
				   !part.destroyed &&
				   part.can_collide &&
				   part.material != .Water &&
				   body.body_id != kineffi.JPH_BODY_ID_INVALID {
					append(&candidates, body.body_id)
				}
			}
			for body_id in service.character_capsules {append(&candidates, body_id)}
			if len(candidates) >
			   0 {sphere = kineffi.JPH_SphereShape_Create(CLOTH_COLLISION_RADIUS)}
		}
		physics_step_cloth(
			cloth,
			anchors,
			pin_count,
			service,
			workspace.global_wind,
			min(delta_time, 0.1),
			cloth.can_collide ? sphere : nil,
			candidates[:],
		)
	}
}

physics_step_cloth :: proc(
	cloth: ^classes.Cloth,
	anchors: [2]datatypes.CFrame,
	pin_count: int,
	service: ^Physics,
	wind: datatypes.Vector3,
	delta_time: f32,
	sphere: kineffi.JPH_ShapeRef,
	candidates: []kineffi.JPH_BodyID,
) {
	pins := [2]int{classes.CLOTH_PIN, 0}
	if pin_count == 2 {pins = {0, classes.CLOTH_SEGMENTS}}
	start_pins, target_pins: [2][3]f32
	reset := !cloth.initialized || cloth.pin_count != pin_count
	for slot in 0 ..< pin_count {
		target_pins[slot] = {anchors[slot].x, anchors[slot].y, anchors[slot].z}
		if linalg.length(target_pins[slot] - cloth.particles[pins[slot]].position) >
		   max(10, 2 * max(cloth.width, cloth.size.Y)) {reset = true}
	}
	if reset {classes.Cloth_Initialize(cloth, anchors, pin_count)}
	for slot in 0 ..< pin_count {
		start_pins[slot] = cloth.particles[pins[slot]].position
	}
	cloth.width = cloth.size.X
	substeps := int(math.ceil(delta_time / CLOTH_MAX_SUBSTEP))
	dt := delta_time / f32(substeps)
	drag := math.exp(-cloth.damping * dt)
	acceleration := cloth.force / cloth.mass + [3]f32{0, -service.gravity, 0}
	wind_velocity := [3]f32{wind.x, wind.y, wind.z}
	kick := cloth.impulse / cloth.mass
	cloth.impulse = {}

	for substep in 1 ..= substeps {
		previous: [classes.CLOTH_VERTEX_COUNT][3]f32
		for &particle, i in cloth.particles {
			previous[i] = particle.position
			pinned := false
			for slot in 0 ..< pin_count {
				if i != pins[slot] {continue}
				particle.position =
					start_pins[slot] +
					(target_pins[slot] - start_pins[slot]) * (f32(substep) / f32(substeps))
				pinned = true
				break
			}
			if pinned {continue}
			// Air drag drives the cloth toward the local wind velocity.
			air := (wind_velocity - particle.velocity) * 0.5
			for axis in 0 ..< 3 {
				a := clamp(acceleration[axis] + air[axis], -10000, 10000)
				v := clamp(particle.velocity[axis] + kick[axis], -500, 500)
				particle.position[axis] += (v * drag + a * dt) * dt
			}
		}
		kick = {}
		if pin_count == 2 {
			cloth.width = classes.Cloth_Width(cloth, cloth.particles[pins[1]].position - cloth.particles[pins[0]].position)
		}
		physics_solve_cloth_links(cloth, cloth.width)
		for &particle, i in cloth.particles {
			if classes.Cloth_Pinned(cloth.pin_count, i) {continue}
			particle.velocity = (particle.position - previous[i]) / dt
			if sphere != nil {
				hit := physics_collide_cloth_particle(
					service,
					sphere,
					candidates,
					previous[i],
					&particle,
					dt,
				)
				if hit != kineffi.JPH_BODY_ID_INVALID {
					physics_report_deformable_contact(service, &cloth.object, hit)
				}
			}
		}
	}
	cloth.pose_source = .Simulation
	cloth.pose_anchors = anchors
	cloth.revision += 1
}

physics_solve_cloth_links :: proc(cloth: ^classes.Cloth, width: f32) {
	n :: classes.CLOTH_SEGMENTS
	stride :: classes.CLOTH_STRIDE
	dx, dy := width / n, cloth.size.Y / n
	diagonal := math.sqrt(dx * dx + dy * dy)
	for _ in 0 ..< CLOTH_SOLVER_ITERATIONS {
		for row in 0 ..= n {
			for column in 0 ..= n {
				i := row * stride + column
				if column < n {physics_cloth_link(cloth, i, i + 1, dx, 1)}
				if row < n {physics_cloth_link(cloth, i, i + stride, dy, 1)}
				if row < n && column < n {
					physics_cloth_link(cloth, i, i + stride + 1, diagonal, 1)
					physics_cloth_link(cloth, i + 1, i + stride, diagonal, 1)
				}
				if column + 2 <= n {physics_cloth_link(cloth, i, i + 2, dx * 2, 0.15)}
				if row + 2 <= n {physics_cloth_link(cloth, i, i + stride * 2, dy * 2, 0.15)}
			}
		}
	}
}

physics_cloth_link :: proc(cloth: ^classes.Cloth, a, b: int, rest_length, stiffness: f32) {
	delta := cloth.particles[b].position - cloth.particles[a].position
	length := linalg.length(delta)
	if length < 0.000001 {return}
	weight_a := classes.Cloth_Pinned(cloth.pin_count, a) ? f32(0) : 1
	weight_b := classes.Cloth_Pinned(cloth.pin_count, b) ? f32(0) : 1
	correction := delta * ((1 - rest_length / length) * stiffness / (weight_a + weight_b))
	cloth.particles[a].position += correction * weight_a
	cloth.particles[b].position -= correction * weight_b
}

physics_collide_cloth_particle :: proc(
	service: ^Physics,
	sphere: kineffi.JPH_ShapeRef,
	candidates: []kineffi.JPH_BodyID,
	previous: [3]f32,
	particle: ^classes.Cloth_Particle,
	dt: f32,
) -> kineffi.JPH_BodyID {
	displacement := particle.position - previous
	penetration_depth: f32
	hit, collided := jolt.System_Cast_Shape(
		&service.system,
		{f64(previous.x), f64(previous.y), f64(previous.z)},
		{displacement.x, displacement.y, displacement.z},
		sphere,
		candidates,
		.Include,
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
	offset := particle.position - [3]f32{f32(center.x), f32(center.y), f32(center.z)}
	surface_velocity :=
		[3]f32{linear.x, linear.y, linear.z} +
		linalg.cross([3]f32{angular.x, angular.y, angular.z}, offset)
	relative := particle.velocity - surface_velocity
	speed := linalg.dot(relative, normal)
	tangent := relative - normal * speed
	particle.velocity = surface_velocity + normal * max(speed, 0) + tangent * math.exp(-10 * dt)
	return hit.bodyID
}
