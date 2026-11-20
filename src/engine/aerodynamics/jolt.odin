package aerodynamics

import jolt "../bindings"
import "core:math"


Body_State :: struct {
	position:          jolt.JPH_RVec3,
	rotation, inverse: jolt.JPH_Quat,
	linear, angular:   Vec3,
	active:            bool,
}

read_body :: proc(
	system: jolt.JPH_PhysicsSystemRef,
	bi: jolt.JPH_BodyInterfaceRef,
	id: jolt.JPH_BodyID,
	wake_sleeping: bool,
) -> (
	state: Body_State,
	ok: bool,
) {
	if system == nil || bi == nil || id == jolt.JPH_BODY_ID_INVALID {return}
	if jolt.JPH_BodyInterface_IsAdded(bi, id) == 0 {return}
	if jolt.JPH_BodyInterface_GetMotionType(bi, id) != .Dynamic {return}
	if jolt.JPH_PhysicsSystem_IsBodySensor(system, id) != 0 {return}
	state.active = jolt.JPH_BodyInterface_IsActive(bi, id) != 0
	if !state.active && !wake_sleeping {return}
	jolt.JPH_BodyInterface_GetCenterOfMassPosition(bi, id, &state.position)
	jolt.JPH_BodyInterface_GetRotation(bi, id, &state.rotation)
	linear, angular: jolt.JPH_Vec3
	jolt.JPH_BodyInterface_GetLinearVelocity(bi, id, &linear)
	jolt.JPH_BodyInterface_GetAngularVelocity(bi, id, &angular)
	state.linear, state.angular = from_jolt(linear), from_jolt(angular)
	if !finite3(state.linear) ||
	   !finite3(state.angular) ||
	   !(abs(state.position.x) <= 1.7976931348623157e308) ||
	   !(abs(state.position.y) <= 1.7976931348623157e308) ||
	   !(abs(state.position.z) <= 1.7976931348623157e308) {return}
	q := state.rotation
	norm := math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
	if !finite(norm) || norm < 1e-6 {return}
	state.rotation = jolt.JPH_Quat{q.x / norm, q.y / norm, q.z / norm, q.w / norm}
	q = state.rotation
	state.inverse = jolt.JPH_Quat{-q.x, -q.y, -q.z, q.w}
	ok = true
	return
}

read_geometry :: proc(
	bi: jolt.JPH_BodyInterfaceRef,
	id: jolt.JPH_BodyID,
	settings: Settings,
) -> (
	geometry: Geometry,
	ok: bool,
) {
	shape := jolt.JPH_BodyInterface_GetShape(bi, id)
	if shape == nil {return}
	defer {if settings.shape_ref_owned {jolt.JPH_Shape_Destroy(shape)}}
	lo, hi: jolt.JPH_Vec3
	jolt.JPH_Shape_GetLocalBounds(shape, &lo, &hi)
	lower, upper := from_jolt(lo), from_jolt(hi)
	geometry = Geometry {
		size   = upper - lower,
		center = lower + (upper - lower) * 0.5,
	}
	ok = finite3(geometry.size) && finite3(geometry.center)
	return
}

sample_atmosphere :: proc(settings: Settings, height: f64) -> (air: Atmosphere_State) {
	if settings.atmosphere == .Standard {return Atmosphere_At(settings, height)}
	air = Atmosphere_State {
		density     = Density_At(settings, height),
		temperature = 288.15,
		sound_speed = 340.3,
	}
	air.pressure = air.density * 287.05287 * air.temperature
	return
}

apply_load :: proc(
	bi: jolt.JPH_BodyInterfaceRef,
	id: jolt.JPH_BodyID,
	state: Body_State,
	local: Load,
) -> (
	load: Load,
	ok: bool,
) {
	if local.samples == 0 {return}
	load = local
	load.force = rotate(state.rotation, load.force)
	load.torque = rotate(state.rotation, load.torque)
	if !finite3(load.force) || !finite3(load.torque) {return Load{}, false}
	f2, t2 := dot(load.force, load.force), dot(load.torque, load.torque)
	if f2 > 1e-12 || t2 > 1e-12 {
		if !state.active {jolt.JPH_BodyInterface_ActivateBody(bi, id)}
		if f2 > 1e-12 {f := to_jolt(load.force); jolt.JPH_BodyInterface_AddForce(bi, id, &f)}
		if t2 > 1e-12 {t := to_jolt(load.torque); jolt.JPH_BodyInterface_AddTorque(bi, id, &t)}
	}
	return load, true
}

apply_body :: proc(
	system: jolt.JPH_PhysicsSystemRef,
	bi: jolt.JPH_BodyInterfaceRef,
	id: jolt.JPH_BodyID,
	settings: Settings,
	options: Body_Options,
) -> (
	Load,
	bool,
) {
	if options.mode == .Disabled ||
	   !valid_settings(settings) ||
	   !valid_options(options) {return Load{}, false}
	state, ok := read_body(system, bi, id, options.wake_sleeping)
	if !ok {return Load{}, false}
	geometry, valid := read_geometry(bi, id, settings)
	if !valid {return Load{}, false}
	air := sample_atmosphere(settings, state.position.y)
	o := options
	if o.sound_speed <= 0 {o.sound_speed = air.sound_speed}
	local_linear := rotate(state.inverse, state.linear - Wind_At(settings, state.position))
	local_angular := rotate(state.inverse, state.angular)
	load := Evaluate(geometry, local_linear, local_angular, air.density, settings, o)
	return apply_load(bi, id, state, load)
}


Apply_Body :: proc(
	system: jolt.JPH_PhysicsSystemRef,
	id: jolt.JPH_BodyID,
	settings := DEFAULT_SETTINGS,
	options := DEFAULT_BODY_OPTIONS,
) -> (
	Load,
	bool,
) {
	if system == nil {return Load{}, false}
	return apply_body(
		system,
		jolt.JPH_PhysicsSystem_GetBodyInterface(system),
		id,
		settings,
		options,
	)
}


Step :: proc(
	system: jolt.JPH_PhysicsSystemRef,
	ids: []jolt.JPH_BodyID,
	settings := DEFAULT_SETTINGS,
	options := DEFAULT_BODY_OPTIONS,
) -> (
	stats: Stats,
) {
	if system == nil || !valid_settings(settings) || !valid_options(options) {
		stats.skipped = len(ids)
		return
	}
	bi := jolt.JPH_PhysicsSystem_GetBodyInterface(system)
	for id in ids {
		load, ok := apply_body(system, bi, id, settings, options)
		if !ok {stats.skipped += 1; continue}
		stats.processed += 1
		if load.wing {stats.wings += 1} else {stats.bluff += 1}
	}
	return
}


Step_Configured :: proc(
	system: jolt.JPH_PhysicsSystemRef,
	bodies: []Body,
	settings := DEFAULT_SETTINGS,
) -> (
	stats: Stats,
) {
	if system == nil || !valid_settings(settings) {
		stats.skipped = len(bodies)
		return
	}
	bi := jolt.JPH_PhysicsSystem_GetBodyInterface(system)
	for body in bodies {
		load, ok := apply_body(system, bi, body.id, settings, body.options)
		if !ok {stats.skipped += 1; continue}
		stats.processed += 1
		if load.wing {stats.wings += 1} else {stats.bluff += 1}
	}
	return
}
