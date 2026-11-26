package aerodynamics

import jolt "../bindings"


Flight_Body :: struct {
	id:                jolt.JPH_BodyID,
	automatic_options: Body_Options,
	surfaces:          []Surface,
	propulsors:        []Propulsor,
	prop_wash:         bool,
	wake_sleeping:     bool,
}
DEFAULT_FLIGHT_BODY :: Flight_Body {
	id                = jolt.JPH_BODY_ID_INVALID,
	automatic_options = DEFAULT_BODY_OPTIONS,
	prop_wash         = true,
	wake_sleeping     = true,
}

Flight_Result :: struct {
	load:                 Load,
	atmospheric:          Atmosphere_State,
	air_velocity:         Vec3,
	airspeed_mps:         f32,
	thrust_newtons:       f32,
	surfaces, propulsors: int,
}
Flight_Stats :: struct {
	processed, skipped, wings, bluff, surfaces, propulsors: int,
}

merge_load :: proc(out: ^Load, load: Load) {
	out.force += load.force
	out.torque += load.torque
	out.sample_load += load.sample_load
	out.wing = out.wing || load.wing
	out.samples += load.samples
}


Evaluate_Flight :: proc(
	body: Flight_Body,
	geometry: Geometry,
	relative_v, angular_v: Vec3,
	air_state: Atmosphere_State,
	settings := DEFAULT_SETTINGS,
) -> (
	result: Flight_Result,
) {
	if !valid_settings(settings) ||
	   !finite3(relative_v) ||
	   !finite3(angular_v) ||
	   !finite(air_state.density) ||
	   air_state.density < 0 {return}
	s := settings
	s.max_force_newtons = 0
	s.max_torque_nm = 0
	result.atmospheric = air_state
	result.airspeed_mps = length3(relative_v) * s.meters_per_unit
	if body.automatic_options.mode != .Disabled && air_state.density > 0 {
		o := body.automatic_options
		if o.sound_speed <= 0 {o.sound_speed = air_state.sound_speed}
		merge_load(
			&result.load,
			Evaluate(geometry, relative_v, angular_v, air_state.density, s, o),
		)
	}


	stack_results: [16]Propulsion_Result
	prop_results: []Propulsion_Result
	if body.prop_wash && len(body.surfaces) > 0 {
		if len(body.propulsors) <= len(stack_results) {
			prop_results = stack_results[:len(body.propulsors)]
		} else {
			prop_results = make([]Propulsion_Result, len(body.propulsors))
		}
	}
	defer {if len(prop_results) > len(stack_results) {delete(prop_results)}}
	for prop, i in body.propulsors {
		p := Evaluate_Propulsor(prop, relative_v, angular_v, air_state.density, s)
		if len(prop_results) > 0 {prop_results[i] = p}
		if p.load.samples == 0 {continue}
		result.propulsors += 1
		result.thrust_newtons += p.thrust_newtons
		merge_load(&result.load, p.load)
	}


	for value in body.surfaces {
		surface := value
		if surface.options.sound_speed <= 0 {surface.options.sound_speed = air_state.sound_speed}
		if body.prop_wash {
			for prop, i in body.propulsors {
				p := prop_results[i]
				surface.extra_wind += Prop_Wash_At(
					prop,
					p,
					surface.center + surface.options.pressure_offset,
				)
			}
		}
		load := Evaluate_Surface(surface, relative_v, angular_v, air_state.density, s).load
		if load.samples == 0 {continue}
		result.surfaces += 1
		merge_load(&result.load, load)
	}
	result.load = limit_load(result.load, settings)
	if result.load.samples == 0 {return Flight_Result{}}
	return
}

Apply_Flight_Body :: proc(
	system: jolt.JPH_PhysicsSystemRef,
	body: Flight_Body,
	settings := DEFAULT_SETTINGS,
) -> (
	Flight_Result,
	bool,
) {
	if system == nil {return Flight_Result{}, false}
	return apply_flight_body(
		system,
		jolt.JPH_PhysicsSystem_GetBodyInterface(system),
		body,
		settings,
	)
}

apply_flight_body :: proc(
	system: jolt.JPH_PhysicsSystemRef,
	bi: jolt.JPH_BodyInterfaceRef,
	body: Flight_Body,
	settings: Settings,
) -> (
	result: Flight_Result,
	ok: bool,
) {
	if !valid_settings(settings) {return}
	state, valid := read_body(system, bi, body.id, body.wake_sleeping)
	if !valid {return}
	geometry: Geometry
	if body.automatic_options.mode != .Disabled {
		geometry, _ = read_geometry(bi, body.id, settings)
	}
	air := sample_atmosphere(settings, state.position.y)
	wind := Wind_At(settings, state.position)
	relative := rotate(state.inverse, state.linear - wind)
	angular := rotate(state.inverse, state.angular)
	result = Evaluate_Flight(body, geometry, relative, angular, air, settings)
	result.air_velocity = wind
	result.load, ok = apply_load(bi, body.id, state, result.load)
	return
}

Step_Flight :: proc(
	system: jolt.JPH_PhysicsSystemRef,
	bodies: []Flight_Body,
	settings := DEFAULT_SETTINGS,
) -> (
	stats: Flight_Stats,
) {
	if system == nil || !valid_settings(settings) {stats.skipped = len(bodies); return}
	bi := jolt.JPH_PhysicsSystem_GetBodyInterface(system)
	for body in bodies {
		result, ok := apply_flight_body(system, bi, body, settings)
		if !ok {stats.skipped += 1; continue}
		stats.processed += 1
		stats.surfaces += result.surfaces
		stats.propulsors += result.propulsors
		if result.load.wing {stats.wings += 1} else {stats.bluff += 1}
	}
	return
}
