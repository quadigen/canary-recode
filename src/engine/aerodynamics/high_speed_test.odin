#+build !js
package aerodynamics

import "core:testing"

@(test)
high_speed_pressure_and_cap :: proc(t: ^testing.T) {
	o := DEFAULT_BODY_OPTIONS
	o.wave_drag = 0
	g := Geometry {
		size = {2, 2, 2},
	}
	a := Evaluate(g, {0, 0, 200}, {}, 1.225, DEFAULT_SETTINGS, o)
	b := Evaluate(g, {0, 0, 600}, {}, 1.225, DEFAULT_SETTINGS, o)
	testing.expect(t, near(b.force.z, 9 * a.force.z, 1))
	s := DEFAULT_SETTINGS
	s.max_speed = 200
	c := Evaluate(g, {0, 0, 600}, {}, 1.225, s, o)
	testing.expect(t, near(c.force.z, a.force.z, 0.1))
}

@(test)
mach_continuity_and_passivity :: proc(t: ^testing.T) {
	surface := DEFAULT_SURFACE
	surface.span = 8
	surface.deflection_deg = 5
	previous: f32
	for i in 1 ..= 300 {
		speed := f32(i) * 3.403
		v := Vec3{0, 0, -speed}
		r := Evaluate_Surface(surface, v, {}, 1.225)
		testing.expect(t, finite3(r.load.force) && finite(r.cl) && r.cd >= 0)
		testing.expect(t, dot(r.load.force, v) <= 0)
		if i > 1 {testing.expect(t, abs(r.cl - previous) < 0.03)}
		previous = r.cl
	}
	a := Evaluate_Surface(surface, {0, 0, -340.3}, {}, 1.225)
	testing.expect(t, near(a.mach, 1, 0.001) && a.cd > surface.options.profile_drag)
}

@(test)
uniform_fast_path_equivalence :: proc(t: ^testing.T) {
	g := Geometry {
		size   = {8, 0.15, 2},
		center = {2, 1, -3},
	}
	o := DEFAULT_BODY_OPTIONS
	v := Vec3{10, -30, 400}
	for mode in ([2]Mode{.Wing, .Drag_Only}) {
		o.mode = mode
		fast := Evaluate(g, v, {}, 1.225, DEFAULT_SETTINGS, o)
		reference := Load {
			wing = mode == .Wing,
		}
		count := reference.wing ? 4 : 8
		for i in 0 ..< count {
			p := g.center
			if reference.wing {
				p[2] += (i % 2 == 0 ? -0.25 : 0.25) * g.size[2]
				p[0] += (i / 2 == 0 ? -0.25 : 0.25) * g.size[0]
			} else {
				for k in 0 ..< 3 {p[k] += ((i & (1 << uint(k))) == 0 ? -0.25 : 0.25) * g.size[k]}
			}
			accumulate(&reference, g, p, v, {}, 1.225, 1, DEFAULT_SETTINGS, o, 1 / f32(count))
		}
		testing.expect(t, length3(fast.force - reference.force) <= 1e-5 * length3(reference.force))
		testing.expect(
			t,
			length3(fast.torque - reference.torque) <= 1e-5 * length3(reference.torque),
		)
		testing.expect(t, fast.samples == reference.samples)
	}
}

@(test)
stiff_drag_step :: proc(t: ^testing.T) {
	v := Vec3{1000, 0, 0}
	center := Vec3{0, 2, 0}
	f := Vec3{-1000000, 400, 0}
	input := Load {
		force       = f,
		torque      = cross(center, f),
		sample_load = length3(f),
		samples     = 8,
	}
	dt: f32 = 0.1
	result := stabilize_translation(input, v, center, dt, 1)
	final := v + result.force * dt
	testing.expect(t, final.x > 0 && final.x < v.x)
	testing.expect(t, near(final.x, v.x / 101, 0.02))
	testing.expect(t, result.force.y == f.y)
	testing.expect(t, length3(result.torque - cross(center, result.force)) < 0.1)
}

@(test)
high_advance_propeller_wake :: proc(t: ^testing.T) {
	p := DEFAULT_PROPULSOR
	p.max_thrust = 1
	p.throttle = 1
	p.disk_radius = 1
	result := Evaluate_Propulsor(p, {0, 0, -10000}, {}, 1.225)
	testing.expect(t, result.induced_speed > 0 && finite(result.induced_speed))
}

@(test)
surface_speed_cap_combined_sideslip :: proc(t: ^testing.T) {
	surface := DEFAULT_SURFACE
	s := DEFAULT_SETTINGS
	s.max_speed = 100
	a := Evaluate_Surface(surface, {80, 0, -60}, {}, 1.225, s)
	b := Evaluate_Surface(surface, {800, 0, -600}, {}, 1.225, s)
	testing.expect(t, length3(a.load.force - b.load.force) < 0.01)
	testing.expect(t, near(a.dynamic_pressure, b.dynamic_pressure, 0.01))
}
