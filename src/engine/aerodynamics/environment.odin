package aerodynamics

import jolt "../bindings"
import "core:math"

Atmosphere_Model :: enum {
	Legacy,
	Standard,
}

Atmosphere_State :: struct {
	density:     f32,
	pressure:    f32,
	temperature: f32,
	sound_speed: f32,
}

Atmosphere_At :: proc(s: Settings, height: f64) -> (air: Atmosphere_State) {
	h := clamp((height - s.reference_height) * f64(s.meters_per_unit), -1000.0, 20000.0)
	t := 288.15 - 0.0065 * min(h, 11000.0)
	p := 101325.0 * math.pow(t / 288.15, 5.2558797)
	if h > 11000 {p *= math.exp(-9.80665 * (h - 11000) / (287.05287 * t))}
	p *= f64(s.density) / 1.225
	air = Atmosphere_State {
		density     = f32(p / (287.05287 * t)),
		pressure    = f32(p),
		temperature = f32(t),
		sound_speed = f32(math.sqrt(1.4 * 287.05287 * t)),
	}
	return
}


Wind_At :: proc(s: Settings, p: jolt.JPH_RVec3) -> (wind: Vec3) {
	h := clamp((p.y - s.reference_height) * f64(s.meters_per_unit), -1000.0, 20000.0)
	wind = s.wind + s.wind_shear * f32(h)
	if dot(s.gust, s.gust) == 0 {return}
	phase := s.time_seconds * f64(2 * PI) * f64(s.gust_frequency)
	spatial: f64
	if s.gust_wavelength > 0 {
		spatial = f64(2 * PI) * f64(s.meters_per_unit) / f64(s.gust_wavelength)
	}
	coords := [3]f64{p.x, p.y - s.reference_height, p.z}
	for i in 0 ..< 3 {
		a := phase + spatial * (coords[i] + 0.37 * coords[(i + 1) % 3]) + f64(i) * 2.094395102
		wind[i] += s.gust[i] * f32(0.7 * math.sin(a) + 0.3 * math.sin(1.73 * a + 0.7))
	}
	return
}

wave_coefficient :: proc(speed: f32, o: Body_Options) -> f32 {
	if o.wave_drag == 0 {return 0}
	sound := o.sound_speed
	if sound <= 0 {sound = 340.3}
	mach := speed / sound
	x := clamp((mach - 0.75) / 0.4, 0, 1)
	return o.wave_drag * x * x * (3 - 2 * x)
}
