package aerodynamics

import "core:math"


Polar_Point :: struct {
	alpha_deg, cl, cd, cm: f32,
}

Surface :: struct {
	center, chord_axis, normal: Vec3,
	span, chord, thickness:     f32,
	deflection_deg:             f32,
	options:                    Body_Options,
	polar:                      []Polar_Point,
	moment_coefficient:         f32,
	clearance:                  f32,
	extra_wind:                 Vec3,
}

DEFAULT_SURFACE :: Surface {
	chord_axis = {0, 0, -1},
	normal     = {0, 1, 0},
	span       = 1,
	chord      = 1,
	thickness  = 0.05,
	options    = DEFAULT_BODY_OPTIONS,
}

Surface_Result :: struct {
	load:                                      Load,
	alpha_deg, cl, cd, mach, dynamic_pressure: f32,
}

unit :: proc(v: Vec3) -> Vec3 {
	n := length3(v)
	if !finite(n) || n < 1e-6 {return Vec3{}}
	return v / n
}

valid_polar :: proc(p: []Polar_Point) -> bool {
	for point, i in p {
		if !finite(point.alpha_deg) ||
		   abs(point.alpha_deg) > 180 ||
		   !finite(point.cl) ||
		   !finite(point.cd) ||
		   point.cd < 0 ||
		   !finite(point.cm) {return false}
		if i > 0 && point.alpha_deg <= p[i - 1].alpha_deg {return false}
	}
	return len(p) == 0 || len(p) >= 2
}


Sample_Polar :: proc(p: []Polar_Point, angle: f32) -> (point: Polar_Point, ok: bool) {
	if len(p) < 2 ||
	   !finite(angle) ||
	   angle < p[0].alpha_deg ||
	   angle > p[len(p) - 1].alpha_deg {return}
	lo, hi := 0, len(p) - 1
	for hi - lo > 1 {
		mid := (hi + lo) / 2
		if angle < p[mid].alpha_deg {hi = mid} else {lo = mid}
	}
	a, b := p[lo], p[hi]
	if b.alpha_deg <= a.alpha_deg {return}
	t := (angle - a.alpha_deg) / (b.alpha_deg - a.alpha_deg)
	return Polar_Point {
			angle,
			a.cl + (b.cl - a.cl) * t,
			a.cd + (b.cd - a.cd) * t,
			a.cm + (b.cm - a.cm) * t,
		},
		true
}

surface_axes :: proc(surface: Surface) -> (chord, normal, span: Vec3, ok: bool) {
	chord = unit(surface.chord_axis)
	normal = unit(surface.normal - chord * dot(surface.normal, chord))
	if dot(chord, chord) < 0.9 || dot(normal, normal) < 0.9 {return}
	span = unit(cross(chord, normal))
	angle := surface.deflection_deg * f32(PI / 180)
	c, s := math.cos(angle), math.sin(angle)
	original := chord
	chord = chord * c + normal * s
	normal = normal * c - original * s
	ok = true
	return
}

surface_coefficients :: proc(
	surface: Surface,
	alpha, polar_angle, aspect, mach: f32,
) -> (
	cl, cd, cm: f32,
) {
	o := surface.options
	cm = surface.moment_coefficient
	p, ok := Sample_Polar(surface.polar, polar_angle + o.incidence_deg)
	if ok {
		cl = p.cl * o.lift_multiplier; cd = p.cd; cm = p.cm
	} else {
		cl, cd = wing_coefficients(alpha, aspect, o, mach)
	}


	if surface.clearance > 0 {
		r := 16 * surface.clearance / surface.span
		induced := cl * cl / (f32(PI) * o.efficiency * aspect)
		cd -= min(max(cd - o.profile_drag, 0), induced / (1 + r * r))
	}
	cd += wave_coefficient_mach(mach, o.wave_drag)
	return
}

surface_sample :: proc(
	surface: Surface,
	chord, normal, span, v: Vec3,
	density, weight: f32,
	settings: Settings,
) -> (
	f, moment: Vec3,
	alpha_deg, cl, cd, mach, q: f32,
) {

	side := dot(v, span)
	flow := v - span * side
	speed := length3(flow)
	m := settings.meters_per_unit
	o := surface.options
	if !finite(speed) || !finite(side) {return}

	full_speed := math.sqrt(speed * speed + side * side)
	if !finite(full_speed) || full_speed * m < settings.min_speed {return}
	if settings.max_speed > 0 && full_speed * m > settings.max_speed {
		scale := settings.max_speed / (full_speed * m)
		side *= scale
	}
	if abs(side) * m < settings.min_speed {side = 0}
	side_area := surface.chord * surface.thickness
	f =
		-span *
		(0.5 *
				density *
				side *
				abs(side) *
				m *
				m *
				m *
				side_area *
				o.drag_coefficient *
				weight *
				o.area_multiplier)
	if speed <= 1e-6 || speed * m < settings.min_speed {return}
	dir := flow / speed
	alpha := math.atan2(-dot(dir, normal), dot(dir, chord))
	alpha_deg = alpha * f32(180 / PI)

	analytic_alpha := math.asin(clamp(-dot(dir, normal), -1, 1))
	if settings.max_speed > 0 && full_speed * m > settings.max_speed {
		speed *= settings.max_speed / (full_speed * m)
	}
	mach = mach_at(speed * m, o)
	aspect := clamp(surface.span / surface.chord, 0.25, 20)
	cm: f32
	cl, cd, cm = surface_coefficients(surface, analytic_alpha, alpha_deg, aspect, mach)
	q = 0.5 * density * speed * speed * m * m
	scale := q * surface.span * surface.chord * m * weight * o.area_multiplier
	edge := surface.thickness / surface.chord * abs(dot(dir, chord)) * o.drag_coefficient
	f += -dir * (scale * (cd + edge))


	chord_dot := dot(dir, chord)
	if abs(chord_dot) > 1e-6 {
		lift_dir := (normal * chord_dot - chord * dot(dir, normal)) * (chord_dot < 0 ? -1 : 1)
		f += lift_dir * (scale * cl)
	}
	moment = span * (scale * surface.chord * cm)
	return
}

Evaluate_Surface :: proc(
	surface: Surface,
	relative_v, angular_v: Vec3,
	density: f32,
	settings := DEFAULT_SETTINGS,
) -> (
	result: Surface_Result,
) {
	o := surface.options
	if !valid_settings(settings) ||
	   !valid_options(o) ||
	   o.mode == .Disabled ||
	   !valid_polar(surface.polar) ||
	   !finite3(surface.center) ||
	   !finite3(surface.extra_wind) ||
	   !finite3(relative_v) ||
	   !finite3(angular_v) ||
	   !finite3(surface.normal) ||
	   !finite3(surface.chord_axis) ||
	   !finite(surface.deflection_deg) ||
	   !finite(surface.span) ||
	   surface.span <= 0 ||
	   !finite(surface.chord) ||
	   surface.chord <= 0 ||
	   !finite(surface.thickness) ||
	   surface.thickness < 0 ||
	   !finite(surface.moment_coefficient) ||
	   !finite(surface.clearance) ||
	   !finite(density) ||
	   density < 0 {return}
	chord, normal, span, ok := surface_axes(surface)
	if !ok {return}
	center := surface.center + o.pressure_offset
	v := relative_v - surface.extra_wind

	center_force, center_moment: Vec3
	center_force, center_moment, result.alpha_deg, result.cl, result.cd, result.mach, result.dynamic_pressure =
		surface_sample(
			surface,
			chord,
			normal,
			span,
			v + cross(angular_v, center),
			density,
			1,
			settings,
		)
	result.load.wing = true
	if angular_v == (Vec3{}) {
		if !finite3(center_force) || !finite3(center_moment) {return Surface_Result{}}
		result.load.force = center_force
		result.load.torque = cross(center, center_force) + center_moment
		result.load.sample_load = length3(center_force)
		result.load.samples = 4
		result.load = limit_load(result.load, settings)
		return
	}
	for i in 0 ..< 4 {
		a: f32 = i % 2 == 0 ? -0.25 : 0.25
		b: f32 = i / 2 == 0 ? -0.25 : 0.25
		p := center + span * (a * surface.span) + chord * (b * surface.chord)
		f, m, _, _, _, _, _ := surface_sample(
			surface,
			chord,
			normal,
			span,
			v + cross(angular_v, p),
			density,
			0.25,
			settings,
		)
		if !finite3(f) || !finite3(m) {return Surface_Result{}}
		result.load.force += f
		result.load.torque += cross(p, f) + m
		result.load.sample_load += length3(f)
		result.load.samples += 1
	}
	result.load = limit_load(result.load, settings)
	return
}
