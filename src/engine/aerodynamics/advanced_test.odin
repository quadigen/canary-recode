#+build !js

package aerodynamics

import jolt "../bindings"
import "core:testing"

@(test)
standard_atmosphere :: proc(t: ^testing.T) {
	s := DEFAULT_SETTINGS
	s.atmosphere = .Standard
	sea := Atmosphere_At(s, 0)
	high := Atmosphere_At(s, 11000)
	upper := Atmosphere_At(s, 20000)
	testing.expect(t, near(sea.density, 1.225, 0.001))
	testing.expect(t, near(sea.pressure, 101325, 1))
	testing.expect(t, near(high.temperature, 216.65, 0.01))
	testing.expect(t, near(high.density, 0.3639, 0.001))
	testing.expect(t, upper.density < high.density && near(high.temperature, upper.temperature))
}

@(test)
wind_field :: proc(t: ^testing.T) {
	s := DEFAULT_SETTINGS
	s.wind = {2, 0, 0}
	s.wind_shear = {0.01, 0, 0}
	p := jolt.JPH_RVec3{0, 100, 0}
	testing.expect(t, near(Wind_At(s, p)[0], 3))
	s.gust = {2, 1, 0}
	s.gust_frequency = 1
	a := Wind_At(s, p)
	b := Wind_At(s, p)
	testing.expect(t, a == b)
	s.time_seconds = 0.25
	testing.expect(t, length3(Wind_At(s, p) - a) > 0.01)
}

@(test)
control_surface :: proc(t: ^testing.T) {
	surface := DEFAULT_SURFACE
	surface.span = 4
	surface.chord = 1
	surface.center = {0, 0, 3}
	a := Evaluate_Surface(surface, Vec3{0, 0, -30}, Vec3{}, 1.225)
	surface.deflection_deg = 10
	b := Evaluate_Surface(surface, Vec3{0, 0, -30}, Vec3{}, 1.225)
	testing.expect(t, near(a.load.force[1], 0))
	testing.expect(t, b.load.force[1] > 0 && b.load.torque[0] < 0)
	testing.expect(t, near(b.alpha_deg, 10, 0.01))
	testing.expect(t, dot(b.load.force, Vec3{0, 0, -30}) <= 0)
	surface.deflection_deg = -10
	c := Evaluate_Surface(surface, Vec3{0, 0, -30}, Vec3{}, 1.225)
	testing.expect(t, c.load.force[1] < 0 && c.load.torque[0] > 0)
}

@(test)
polar_interpolation :: proc(t: ^testing.T) {
	points := [?]Polar_Point{{-10, -0.8, 0.08, 0}, {0, 0, 0.02, -0.04}, {10, 1, 0.1, -0.08}}
	p, ok := Sample_Polar(points[:], 5)
	testing.expect(t, ok && near(p.cl, 0.5) && near(p.cd, 0.06) && near(p.cm, -0.06))
	_, outside := Sample_Polar(points[:], 30)
	testing.expect(t, !outside)
	surface := DEFAULT_SURFACE
	surface.polar = points[:]
	surface.deflection_deg = 5
	r := Evaluate_Surface(surface, Vec3{0, 0, -30}, Vec3{}, 1.225)
	testing.expect(t, near(r.cl, 0.5, 0.001))
}

@(test)
ground_effect :: proc(t: ^testing.T) {
	surface := DEFAULT_SURFACE
	surface.span = 8
	surface.deflection_deg = 8
	far := Evaluate_Surface(surface, Vec3{0, 0, -25}, Vec3{}, 1.225)
	surface.clearance = 0.25
	close := Evaluate_Surface(surface, Vec3{0, 0, -25}, Vec3{}, 1.225)
	testing.expect(t, close.cd < far.cd && near(close.cl, far.cl))
	testing.expect(t, close.load.force[2] < far.load.force[2])
}

@(test)
propulsion_and_wake :: proc(t: ^testing.T) {
	p := DEFAULT_PROPULSOR
	p.max_thrust = 1000
	p.throttle = 0.5
	p.disk_radius = 1
	p.advance_speed = 100
	p.center = {1, 0, 0}
	r := Evaluate_Propulsor(p, Vec3{}, Vec3{}, 1.225)
	testing.expect(t, near(r.thrust_newtons, 250) && near(r.load.force[2], -250))
	testing.expect(t, near(r.load.torque[1], 250) && r.induced_speed > 0)
	testing.expect(t, Prop_Wash_At(p, r, Vec3{1, 0, 2})[2] > 0)
	testing.expect(t, length3(Prop_Wash_At(p, r, Vec3{1, 0, -2})) == 0)
	fast := Evaluate_Propulsor(p, Vec3{0, 0, -100}, Vec3{}, 1.225)
	testing.expect(t, near(fast.thrust_newtons, 0))
	p.mode = .Thruster
	testing.expect(t, near(Evaluate_Propulsor(p, Vec3{}, Vec3{}, 0).thrust_newtons, 500))
}

@(test)
flight_aggregate_limit_and_wash :: proc(t: ^testing.T) {
	p := DEFAULT_PROPULSOR
	p.max_thrust = 1000
	p.throttle = 1
	p.disk_radius = 1
	props := [?]Propulsor{p}
	surface := DEFAULT_SURFACE
	surface.center = {0, 0, 2}
	surface.deflection_deg = 10
	surfaces := [?]Surface{surface}
	b := DEFAULT_FLIGHT_BODY
	b.automatic_options.mode = .Disabled
	b.surfaces = surfaces[:]
	b.propulsors = props[:]
	air := Atmosphere_State {
		density     = 1.225,
		sound_speed = 340.3,
	}
	b.prop_wash = false
	no_wash := Evaluate_Flight(b, Geometry{}, Vec3{}, Vec3{}, air)
	b.prop_wash = true
	wash := Evaluate_Flight(b, Geometry{}, Vec3{}, Vec3{}, air)
	testing.expect(t, no_wash.surfaces == 1 && no_wash.propulsors == 1)
	testing.expect(t, near(no_wash.load.force[1], 0) && wash.load.force[1] > 0)
	s := DEFAULT_SETTINGS
	s.max_force_newtons = 100
	limited := Evaluate_Flight(b, Geometry{}, Vec3{}, Vec3{}, air, s)
	testing.expect(t, near(limited.load.sample_load, 100, 0.01))
}

@(test)
axis_drag_and_wave_drag :: proc(t: ^testing.T) {
	g := Geometry {
		size = {1, 1, 1},
	}
	o := DEFAULT_BODY_OPTIONS
	o.directional_drag = {2, 1, 1}
	a := Evaluate(g, Vec3{10, 0, 0}, Vec3{}, 1.225, DEFAULT_SETTINGS, o)
	b := Evaluate(g, Vec3{0, 0, 10}, Vec3{}, 1.225, DEFAULT_SETTINGS, o)
	testing.expect(t, near(a.force[0], 2 * b.force[2]))
	s := DEFAULT_SETTINGS
	s.max_speed = 0
	a = Evaluate(g, Vec3{0, 0, 350}, Vec3{}, 1.225, s, o)
	o.wave_drag = 0.5
	b = Evaluate(g, Vec3{0, 0, 350}, Vec3{}, 1.225, s, o)
	testing.expect(t, b.force[2] < a.force[2])
}
