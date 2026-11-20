#+build !js

package aerodynamics

import "core:testing"

near :: proc(a, b: f32, tolerance: f32 = 0.001) -> bool {return abs(a - b) <= tolerance}

@(test)
calm_air :: proc(t: ^testing.T) {
	load := Evaluate(Geometry{size = {8, 0.15, 2}}, Vec3{}, Vec3{}, 1.225)
	testing.expect(t, load.wing)
	testing.expect(t, length3(load.force) == 0 && length3(load.torque) == 0)
}

@(test)
symmetric_plate :: proc(t: ^testing.T) {
	g := Geometry {
		size = {8, 0.15, 2},
	}
	flat := Evaluate(g, Vec3{0, 0, 30}, Vec3{}, 1.225)
	rising := Evaluate(g, Vec3{0, 4, 30}, Vec3{}, 1.225)
	falling := Evaluate(g, Vec3{0, -4, 30}, Vec3{}, 1.225)
	testing.expect(t, near(flat.force[1], 0) && flat.force[2] < 0)
	testing.expect(t, falling.force[1] > 0 && rising.force[1] < 0)
	testing.expect(t, near(falling.force[1], -rising.force[1]))
	testing.expect(t, dot(falling.force, Vec3{0, -4, 30}) <= 0)
	testing.expect(t, length3(falling.torque) < 0.01)
}

@(test)
bluff_body_drag :: proc(t: ^testing.T) {
	g := Geometry {
		size = {2, 2, 2},
	}
	l := Evaluate(g, Vec3{0, 0, 10}, Vec3{}, 1.225)
	h := Evaluate(g, Vec3{0, 0, 20}, Vec3{}, 1.225)
	testing.expect(t, !l.wing && l.samples == 8)
	testing.expect(t, near(l.force[2], -257.25, 0.01))
	testing.expect(t, near(h.force[2], 4 * l.force[2], 0.01))
}

@(test)
rotational_damping :: proc(t: ^testing.T) {
	spin := Vec3{0, 0, 3}
	load := Evaluate(Geometry{size = {8, 0.15, 2}}, Vec3{}, spin, 1.225)
	testing.expect(t, dot(load.torque, spin) < 0)
	testing.expect(t, length3(load.force) < 0.01)
}

@(test)
vertical_plate_and_broadside :: proc(t: ^testing.T) {
	load := Evaluate(Geometry{size = {0.1, 3, 5}}, Vec3{-4, 0, 25}, Vec3{}, 1.225)
	testing.expect(t, load.wing && load.force[0] > 0)
	broadside := Evaluate(Geometry{size = {8, 0.15, 2}}, Vec3{0, -20, 0}, Vec3{}, 1.225)
	testing.expect(t, finite3(broadside.force) && broadside.force[1] > 0)
	testing.expect(t, near(broadside.force[0], 0) && near(broadside.force[2], 0))
}

@(test)
unit_scale_and_force_limit :: proc(t: ^testing.T) {
	g := Geometry {
		size   = {2, 2, 2},
		center = {1, 0, 0},
	}
	s := DEFAULT_SETTINGS
	a := Evaluate(g, Vec3{0, 0, 10}, Vec3{}, 1.225, s)
	s.meters_per_unit = 2
	b := Evaluate(g, Vec3{0, 0, 10}, Vec3{}, 1.225, s)
	testing.expect(t, near(b.force[2], 8 * a.force[2], 0.01))
	testing.expect(t, near(b.torque[1], 8 * a.torque[1], 0.01))
	s.max_force_newtons = 100
	c := Evaluate(g, Vec3{0, 0, 10}, Vec3{}, 1.225, s)
	testing.expect(t, near(c.sample_load * s.meters_per_unit, 100, 0.01))
}

@(test)
classification_override :: proc(t: ^testing.T) {
	g := Geometry {
		size = {8, 0.15, 2},
	}
	o := DEFAULT_BODY_OPTIONS
	o.mode = .Drag_Only
	testing.expect(t, !Evaluate(g, Vec3{0, 0, 10}, Vec3{}, 1.225, DEFAULT_SETTINGS, o).wing)
	o.mode = .Disabled
	testing.expect(t, Evaluate(g, Vec3{0, 0, 10}, Vec3{}, 1.225, DEFAULT_SETTINGS, o).samples == 0)
}
