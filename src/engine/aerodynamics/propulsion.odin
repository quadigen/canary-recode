package aerodynamics

import "core:math"

Propulsion_Mode :: enum {
	Thruster,
	Propeller,
	Jet,
	Rotor,
}

Propulsor :: struct {
	mode:              Propulsion_Mode,
	center, direction: Vec3,
	throttle:          f32,
	max_thrust:        f32,
	reference_density: f32,
	advance_speed:     f32,
	density_exponent:  f32,
	reaction_torque:   f32,
	reversible:        bool,
	disk_radius:       f32,
}

DEFAULT_PROPULSOR :: Propulsor {
	mode              = .Propeller,
	direction         = {0, 0, -1},
	reference_density = 1.225,
	density_exponent  = 0.7,
}

Propulsion_Result :: struct {
	load:              Load,
	thrust_newtons:    f32,
	induced_speed:     f32,
	exhaust_direction: Vec3,
}

Evaluate_Propulsor :: proc(
	prop: Propulsor,
	relative_v, angular_v: Vec3,
	density: f32,
	settings := DEFAULT_SETTINGS,
) -> (
	result: Propulsion_Result,
) {
	if !valid_settings(settings) ||
	   !finite3(prop.center) ||
	   !finite3(prop.direction) ||
	   !finite3(relative_v) ||
	   !finite3(angular_v) ||
	   !finite(prop.throttle) ||
	   !finite(prop.max_thrust) ||
	   prop.max_thrust < 0 ||
	   !finite(prop.reference_density) ||
	   prop.reference_density <= 0 ||
	   !finite(prop.advance_speed) ||
	   prop.advance_speed < 0 ||
	   !finite(prop.density_exponent) ||
	   prop.density_exponent < 0 ||
	   !finite(prop.reaction_torque) ||
	   !finite(prop.disk_radius) ||
	   prop.disk_radius < 0 ||
	   !finite(density) ||
	   density < 0 {return}
	dir := unit(prop.direction)
	if dot(dir, dir) < 0.9 {return}
	throttle := clamp(prop.throttle, prop.reversible ? -1.0 : 0.0, 1.0)
	magnitude := abs(throttle)
	sign: f32 = throttle < 0 ? -1 : 1
	m := settings.meters_per_unit
	axial := dot(relative_v + cross(angular_v, prop.center), dir) * sign * m
	thrust := prop.max_thrust * magnitude
	reaction := prop.reaction_torque * magnitude * sign
	switch prop.mode {
	case .Thruster:
	case .Jet:
		lapse: f32 = 0
		if density > 0 {lapse = math.pow(density / prop.reference_density, prop.density_exponent)}
		thrust *= lapse
		reaction *= lapse
	case .Propeller, .Rotor:
		factor := magnitude * density / prop.reference_density
		if prop.advance_speed > 0 {factor *= clamp(1 - max(axial, 0) / prop.advance_speed, 0, 1)}
		thrust *= factor
		reaction *= factor
	}
	result.thrust_newtons = thrust
	result.exhaust_direction = -dir * sign
	force := dir * (thrust * sign / m)
	result.load = Load {
		force       = force,
		torque      = cross(prop.center, force) + dir * (reaction / (m * m)),
		sample_load = length3(force),
		samples     = 1,
	}
	if (prop.mode == .Propeller || prop.mode == .Rotor) &&
	   prop.disk_radius > 0 &&
	   density > 1e-6 &&
	   thrust > 0 {
		area := f32(PI) * prop.disk_radius * prop.disk_radius * m * m

		u := max(axial, 0)

		load_speed2 := 2 * thrust / (density * area)
		result.induced_speed = load_speed2 / (2 * m * (math.sqrt(u * u + load_speed2) + u))
	}
	if !finite(result.induced_speed) ||
	   !finite(thrust) ||
	   !finite3(result.load.force) ||
	   !finite3(result.load.torque) {
		return Propulsion_Result{}
	}
	result.load = limit_load(result.load, settings)
	if result.load.samples == 0 {return Propulsion_Result{}}

	if thrust > 0 {
		result.thrust_newtons = length3(result.load.force) * m
		if result.thrust_newtons <
		   thrust {result.induced_speed *= math.sqrt(result.thrust_newtons / thrust)}
	}
	return
}


Prop_Wash_At :: proc(prop: Propulsor, result: Propulsion_Result, point: Vec3) -> Vec3 {
	if prop.disk_radius <= 0 || result.induced_speed <= 0 {return Vec3{}}
	delta := point - prop.center
	axial := dot(delta, result.exhaust_direction)
	if axial < 0 || axial > 12 * prop.disk_radius {return Vec3{}}
	radial_vector := delta - result.exhaust_direction * axial
	radial2 := dot(radial_vector, radial_vector)
	radius := prop.disk_radius + 0.12 * axial
	radius2 := radius * radius
	if radial2 >= radius2 {return Vec3{}}
	radial_fade := 1 - radial2 / radius2
	axial_fade := 1 / (1 + 0.15 * axial / prop.disk_radius)
	return result.exhaust_direction * (2 * result.induced_speed * radial_fade * axial_fade)
}
