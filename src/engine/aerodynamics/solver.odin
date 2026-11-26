package aerodynamics

import jolt "../bindings"
import "core:math"


Vec3 :: [3]f32
PI :: 3.14159265358979323846

Mode :: enum {
	Auto,
	Drag_Only,
	Wing,
	Disabled,
}
Normal_Axis :: enum {
	Auto,
	X,
	Y,
	Z,
}

Settings :: struct {
	wind:                 Vec3,
	atmosphere:           Atmosphere_Model,
	wind_shear:           Vec3,
	gust:                 Vec3,
	gust_frequency:       f32,
	gust_wavelength:      f32,
	time_seconds:         f64,
	density:              f32,
	meters_per_unit:      f32,
	density_scale_height: f32,
	reference_height:     f64,
	min_speed:            f32,
	max_speed:            f32,
	max_force_newtons:    f32,
	max_torque_nm:        f32,
	thin_ratio:           f32,
	min_dimension:        f32,
	shape_ref_owned:      bool,
}

DEFAULT_SETTINGS :: Settings {
	density         = 1.225,
	meters_per_unit = 1,
	min_speed       = 0.05,
	max_speed       = 0,
	thin_ratio      = 0.25,
	min_dimension   = 0.001,
}

Body_Options :: struct {
	mode:             Mode,
	normal_axis:      Normal_Axis,
	drag_coefficient: f32,
	profile_drag:     f32,
	lift_multiplier:  f32,
	stall_angle_deg:  f32,
	efficiency:       f32,
	max_lift:         f32,
	area_multiplier:  f32,
	pressure_offset:  Vec3,
	incidence_deg:    f32,
	wake_sleeping:    bool,
	directional_drag: Vec3,
	wave_drag:        f32,
	sound_speed:      f32,
}

DEFAULT_BODY_OPTIONS :: Body_Options {
	mode             = .Auto,
	normal_axis      = .Auto,
	drag_coefficient = 1.05,
	profile_drag     = 0.025,
	lift_multiplier  = 1,
	stall_angle_deg  = 15,
	efficiency       = 0.8,
	max_lift         = 1.35,
	area_multiplier  = 1,
	wake_sleeping    = true,
	wave_drag        = 0.15,
}

Geometry :: struct {
	size:   Vec3,
	center: Vec3,
}


Load :: struct {
	force:       Vec3,
	torque:      Vec3,
	sample_load: f32,
	wing:        bool,
	samples:     int,
}

Body :: struct {
	id:      jolt.JPH_BodyID,
	options: Body_Options,
}

Stats :: struct {
	processed, wings, bluff, skipped: int,
}

finite :: proc(v: f32) -> bool {return abs(v) <= 3.402823466e38}
finite3 :: proc(v: Vec3) -> bool {return finite(v[0]) && finite(v[1]) && finite(v[2])}
dot :: proc(a, b: Vec3) -> f32 {return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]}
cross :: proc(a, b: Vec3) -> Vec3 {
	return Vec3{a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]}
}
length3 :: proc(v: Vec3) -> f32 {return math.sqrt(dot(v, v))}
from_jolt :: proc(v: jolt.JPH_Vec3) -> Vec3 {return Vec3{v.x, v.y, v.z}}
to_jolt :: proc(v: Vec3) -> jolt.JPH_Vec3 {return jolt.JPH_Vec3{v[0], v[1], v[2]}}

rotate :: proc(q: jolt.JPH_Quat, v: Vec3) -> Vec3 {
	u := Vec3{q.x, q.y, q.z}
	t := cross(u, v) * 2
	return v + t * q.w + cross(u, t)
}

valid_settings :: proc(s: Settings) -> bool {
	return(
		finite3(s.wind) &&
		finite3(s.wind_shear) &&
		finite3(s.gust) &&
		finite(s.gust_frequency) &&
		s.gust_frequency >= 0 &&
		finite(s.gust_wavelength) &&
		s.gust_wavelength >= 0 &&
		abs(s.time_seconds) <= 1.7976931348623157e308 &&
		finite(s.density) &&
		s.density >= 0 &&
		finite(s.meters_per_unit) &&
		s.meters_per_unit > 0 &&
		finite(s.density_scale_height) &&
		s.density_scale_height >= 0 &&
		abs(s.reference_height) <= 1.7976931348623157e308 &&
		finite(s.min_speed) &&
		s.min_speed >= 0 &&
		finite(s.max_speed) &&
		s.max_speed >= 0 &&
		finite(s.max_force_newtons) &&
		s.max_force_newtons >= 0 &&
		finite(s.max_torque_nm) &&
		s.max_torque_nm >= 0 &&
		finite(s.thin_ratio) &&
		s.thin_ratio > 0 &&
		finite(s.min_dimension) &&
		s.min_dimension > 0 \
	)
}

valid_options :: proc(o: Body_Options) -> bool {
	return(
		finite(o.drag_coefficient) &&
		o.drag_coefficient >= 0 &&
		finite(o.profile_drag) &&
		o.profile_drag >= 0 &&
		finite(o.lift_multiplier) &&
		o.lift_multiplier >= 0 &&
		finite(o.stall_angle_deg) &&
		o.stall_angle_deg > 0 &&
		o.stall_angle_deg < 90 &&
		finite(o.efficiency) &&
		o.efficiency > 0 &&
		finite(o.max_lift) &&
		o.max_lift >= 0 &&
		finite(o.area_multiplier) &&
		o.area_multiplier >= 0 &&
		finite3(o.pressure_offset) &&
		finite(o.incidence_deg) &&
		finite3(o.directional_drag) &&
		o.directional_drag[0] >= 0 &&
		o.directional_drag[1] >= 0 &&
		o.directional_drag[2] >= 0 &&
		finite(o.wave_drag) &&
		o.wave_drag >= 0 &&
		finite(o.sound_speed) &&
		o.sound_speed >= 0 \
	)
}


wing_axis :: proc(g: Geometry, o: Body_Options) -> int {
	switch o.normal_axis {
	case .X:
		return 0
	case .Y:
		return 1
	case .Z:
		return 2
	case .Auto:
		axis := 1
		if g.size[0] < g.size[axis] {axis = 0}
		if g.size[2] < g.size[axis] {axis = 2}
		return axis
	}
	return 1
}


wing_coefficients :: proc(alpha, aspect: f32, o: Body_Options, mach: f32 = 0) -> (cl, cd: f32) {
	a := clamp(alpha + o.incidence_deg * f32(PI / 180), -f32(PI / 2), f32(PI / 2))
	slope := f32(2 * PI) * aspect / (aspect + 2) * compressibility_lift(mach)
	attached := clamp(slope * a, -o.max_lift, o.max_lift)
	stall := o.stall_angle_deg * f32(PI / 180)
	blend := clamp((abs(a) - stall) / f32(20 * PI / 180), 0, 1)
	blend = blend * blend * (3 - 2 * blend)
	if blend == 0 {
		cl = attached * o.lift_multiplier
		cd = o.profile_drag + cl * cl / (f32(PI) * o.efficiency * aspect)
		return
	}
	sine := math.sin(a)
	separated := f32(2.2) * sine * math.cos(a)
	cl = (attached * (1 - blend) + separated * blend) * o.lift_multiplier
	induced := (1 - blend) * cl * cl / (f32(PI) * o.efficiency * aspect)
	cd = o.profile_drag + induced + 1.8 * sine * sine * blend
	return
}

sample_force :: proc(
	g: Geometry,
	v: Vec3,
	density: f32,
	axis: int,
	wing: bool,
	s: Settings,
	o: Body_Options,
	weight: f32,
) -> Vec3 {
	speed2 := dot(v, v)
	if !finite(speed2) || speed2 <= 1e-12 {return Vec3{}}
	speed := math.sqrt(speed2)
	m := s.meters_per_unit
	physical_speed := speed * m
	if physical_speed < s.min_speed {return Vec3{}}
	dir := v / speed
	if s.max_speed > 0 {physical_speed = min(physical_speed, s.max_speed)}
	q := 0.5 * density * physical_speed * physical_speed * m * weight * o.area_multiplier
	mach := mach_at(physical_speed, o)
	wave := wave_coefficient_mach(mach, o.wave_drag)
	if !wing {
		d := o.directional_drag
		if dot(d, d) == 0 {d = {1, 1, 1}}
		projected :=
			abs(dir[0]) * g.size[1] * g.size[2] * d[0] +
			abs(dir[1]) * g.size[0] * g.size[2] * d[1] +
			abs(dir[2]) * g.size[0] * g.size[1] * d[2]
		return -dir * (q * projected * (o.drag_coefficient + wave))
	}

	a := (axis + 1) % 3
	b := (axis + 2) % 3
	normal: Vec3
	normal[axis] = 1
	normal_dot := clamp(dir[axis], -1, 1)
	alpha := -math.asin(normal_dot)
	plane_speed := math.sqrt(max(0, 1 - normal_dot * normal_dot))
	area := g.size[a] * g.size[b]
	aspect: f32 = 1
	if plane_speed > 1e-5 {


		span_a := g.size[a] * dir[b] / plane_speed
		span_b := g.size[b] * dir[a] / plane_speed
		aspect = clamp((span_a * span_a + span_b * span_b) / area, 0.25, 20)
	}
	cl, cd := wing_coefficients(alpha, aspect, o, mach)
	edge_area := g.size[axis] * (g.size[a] * abs(dir[b]) + g.size[b] * abs(dir[a]))
	force := -dir * (q * (area * (cd + wave) + edge_area * o.drag_coefficient))


	if plane_speed > 1e-5 {
		lift_dir := (normal - dir * normal_dot) / plane_speed
		force += lift_dir * (q * area * cl)
	}
	return force
}

accumulate :: proc(
	out: ^Load,
	g: Geometry,
	point, relative_v, angular_v: Vec3,
	density: f32,
	axis: int,
	s: Settings,
	o: Body_Options,
	weight: f32,
) {
	velocity := relative_v + cross(angular_v, point)
	force := sample_force(g, velocity, density, axis, out.wing, s, o, weight)
	if !finite3(force) {return}
	out.force += force
	out.torque += cross(point, force)
	out.sample_load += length3(force)
	out.samples += 1
}


Evaluate :: proc(
	g: Geometry,
	relative_v, angular_v: Vec3,
	density: f32,
	settings := DEFAULT_SETTINGS,
	options := DEFAULT_BODY_OPTIONS,
) -> (
	out: Load,
) {
	if !valid_settings(settings) ||
	   !valid_options(options) ||
	   options.mode == .Disabled ||
	   !finite3(g.size) ||
	   !finite3(g.center) ||
	   !finite3(relative_v) ||
	   !finite3(angular_v) ||
	   !finite(density) ||
	   density <= 0 {return}
	for d in g.size {if d < settings.min_dimension {return}}
	axis := wing_axis(g, options)
	a := (axis + 1) % 3
	b := (axis + 2) % 3
	out.wing =
		options.mode == .Wing ||
		(options.mode == .Auto && g.size[axis] <= settings.thin_ratio * min(g.size[a], g.size[b]))
	center := g.center + options.pressure_offset


	if angular_v == (Vec3{}) {
		accumulate(&out, g, center, relative_v, angular_v, density, axis, settings, options, 1)
		if out.samples != 0 {out.samples = out.wing ? 4 : 8}
		return limit_load(out, settings)
	}
	if out.wing {

		for i in 0 ..< 4 {
			p := center
			p[a] += (i % 2 == 0 ? -0.25 : 0.25) * g.size[a]
			p[b] += (i / 2 == 0 ? -0.25 : 0.25) * g.size[b]
			accumulate(&out, g, p, relative_v, angular_v, density, axis, settings, options, 0.25)
		}
	} else {

		for i in 0 ..< 8 {
			p := center
			for k in 0 ..< 3 {
				p[k] += ((i & (1 << uint(k))) == 0 ? -0.25 : 0.25) * g.size[k]
			}
			accumulate(&out, g, p, relative_v, angular_v, density, axis, settings, options, 0.125)
		}
	}
	return limit_load(out, settings)
}

limit_load :: proc(input: Load, settings: Settings) -> (out: Load) {
	out = input
	if !finite3(out.force) || !finite3(out.torque) || !finite(out.sample_load) {return Load{}}
	scale: f32 = 1
	if settings.max_force_newtons > 0 && out.sample_load > 0 {
		scale = min(
			scale,
			settings.max_force_newtons / (settings.meters_per_unit * out.sample_load),
		)
	}
	if settings.max_torque_nm > 0 {
		torque_length := length3(out.torque)
		if !finite(torque_length) {return Load{}}
		if torque_length > 0 {
			scale = min(
				scale,
				settings.max_torque_nm /
				(settings.meters_per_unit * settings.meters_per_unit * torque_length),
			)
		}
	}
	out.force *= scale
	out.torque *= scale
	out.sample_load *= scale
	return
}

Density_At :: proc(settings: Settings, height: f64) -> f32 {
	if settings.atmosphere == .Standard {
		return Atmosphere_At(settings, height).density
	}
	if settings.density_scale_height <= 0 {return settings.density}
	altitude := (height - settings.reference_height) * f64(settings.meters_per_unit)

	exponent := clamp(-altitude / f64(settings.density_scale_height), -50.0, 2.0)
	return settings.density * f32(math.exp(exponent))
}


stabilize_translation :: proc(load: Load, v, center: Vec3, dt, inverse_mass: f32) -> (out: Load) {
	out = load
	if dt <= 0 || inverse_mass <= 0 || !finite(dt) || !finite(inverse_mass) {return}
	speed2 := dot(v, v)
	if speed2 <= 1e-12 || !finite(speed2) {return}
	parallel := dot(load.force, v) / speed2
	if parallel >= 0 || !finite(parallel) {return}
	x := -parallel * dt * inverse_mass
	if !finite(x) {return}
	drag := v * parallel
	out.force = (load.force - drag) + drag / (1 + x)
	correction := out.force - load.force
	out.torque += cross(center, correction)
	out.sample_load = min(load.sample_load, length3(out.force))
	return
}
