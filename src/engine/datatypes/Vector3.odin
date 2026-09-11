package datatypes

import "core:math"

Vector3 :: struct {
	x, y, z: f32,
}

Vector3_Zero  :: Vector3{0, 0, 0}
Vector3_One   :: Vector3{1, 1, 1}
Vector3_XAxis :: Vector3{1, 0, 0}
Vector3_YAxis :: Vector3{0, 1, 0}
Vector3_ZAxis :: Vector3{0, 0, 1}

Vec3_New :: proc(x, y, z: f32) -> Vector3 {
	return Vector3{x, y, z}
}

Vec3_Add :: proc(a, b: Vector3) -> Vector3 {
	return Vector3{
		a.x + b.x,
		a.y + b.y,
		a.z + b.z,
	}
}

Vec3_Subtract :: proc(a, b: Vector3) -> Vector3 {
	return Vector3{
		a.x - b.x,
		a.y - b.y,
		a.z - b.z,
	}
}

Vec3_Multiply :: proc(v: Vector3, scalar: f32) -> Vector3 {
	return Vector3{
		v.x * scalar,
		v.y * scalar,
		v.z * scalar,
	}
}

Vec3_Multiply_Vector :: proc(a, b: Vector3) -> Vector3 {
	return Vector3{
		a.x * b.x,
		a.y * b.y,
		a.z * b.z,
	}
}

Vec3_Divide :: proc(v: Vector3, scalar: f32) -> Vector3 {
	return Vector3{
		v.x / scalar,
		v.y / scalar,
		v.z / scalar,
	}
}

Vec3_Divide_Vector :: proc(a, b: Vector3) -> Vector3 {
	return Vector3{
		a.x / b.x,
		a.y / b.y,
		a.z / b.z,
	}
}

Vec3_Negate :: proc(v: Vector3) -> Vector3 {
	return Vector3{-v.x, -v.y, -v.z}
}

Vec3_Magnitude_Squared :: proc(v: Vector3) -> f32 {
	return v.x*v.x + v.y*v.y + v.z*v.z
}

Vec3_Magnitude :: proc(v: Vector3) -> f32 {
	return math.sqrt(Vec3_Magnitude_Squared(v))
}

Vec3_Unit :: proc(v: Vector3) -> Vector3 {
	magnitude := Vec3_Magnitude(v)

	// Roblox returns NaN components for Vector3.zero.Unit.
	if magnitude == 0 {
		nan := math.nan_f32()
		return Vector3{nan, nan, nan}
	}

	return Vec3_Multiply(v, 1.0 / magnitude)
}

Vec3_Abs :: proc(v: Vector3) -> Vector3 {
	return Vector3{
		math.abs(v.x),
		math.abs(v.y),
		math.abs(v.z),
	}
}

Vec3_Ceil :: proc(v: Vector3) -> Vector3 {
	return Vector3{
		math.ceil(v.x),
		math.ceil(v.y),
		math.ceil(v.z),
	}
}

Vec3_Floor :: proc(v: Vector3) -> Vector3 {
	return Vector3{
		math.floor(v.x),
		math.floor(v.y),
		math.floor(v.z),
	}
}

vec3_sign_component :: proc(value: f32) -> f32 {
	if value > 0 {
		return 1
	}
	if value < 0 {
		return -1
	}
	return 0
}

Vec3_Sign :: proc(v: Vector3) -> Vector3 {
	return Vector3{
		vec3_sign_component(v.x),
		vec3_sign_component(v.y),
		vec3_sign_component(v.z),
	}
}

Vec3_Dot :: proc(a, b: Vector3) -> f32 {
	return a.x*b.x + a.y*b.y + a.z*b.z
}

Vec3_Cross :: proc(a, b: Vector3) -> Vector3 {
	return Vector3{
		a.y*b.z - a.z*b.y,
		a.z*b.x - a.x*b.z,
		a.x*b.y - a.y*b.x,
	}
}

// Returns the unsigned angle when axis == nil.
// When axis is provided, the sign follows the right-hand rule around axis.
Vec3_Angle :: proc(a, b: Vector3, axis: ^Vector3 = nil) -> f32 {
	cross := Vec3_Cross(a, b)
	angle := math.atan2(Vec3_Magnitude(cross), Vec3_Dot(a, b))

	if axis != nil && Vec3_Dot(cross, axis^) < 0 {
		angle = -angle
	}

	return angle
}

vec3_fuzzy_component :: proc(a, b, epsilon: f32) -> bool {
	// Matches Roblox's long-standing relative component comparison behavior.
	return a == b || math.abs(a-b) <= (math.abs(a)+1.0)*epsilon
}

Vec3_FuzzyEq :: proc(a, b: Vector3, epsilon: f32 = 1.0e-5) -> bool {
	return vec3_fuzzy_component(a.x, b.x, epsilon) &&
	       vec3_fuzzy_component(a.y, b.y, epsilon) &&
	       vec3_fuzzy_component(a.z, b.z, epsilon)
}

Vec3_Lerp :: proc(a, goal: Vector3, alpha: f32) -> Vector3 {
	return Vector3{
		a.x + (goal.x-a.x)*alpha,
		a.y + (goal.y-a.y)*alpha,
		a.z + (goal.z-a.z)*alpha,
	}
}

Vec3_Max :: proc(a, b: Vector3) -> Vector3 {
	return Vector3{
		a.x > b.x ? a.x : b.x,
		a.y > b.y ? a.y : b.y,
		a.z > b.z ? a.z : b.z,
	}
}

Vec3_Min :: proc(a, b: Vector3) -> Vector3 {
	return Vector3{
		a.x < b.x ? a.x : b.x,
		a.y < b.y ? a.y : b.y,
		a.z < b.z ? a.z : b.z,
	}
}

Vec3_Equal :: proc(a, b: Vector3) -> bool {
	return a.x == b.x && a.y == b.y && a.z == b.z
}

// String-based helpers avoid a datatypes -> enum package dependency.
// LuaVector3 converts Enum.Axis / Enum.NormalId into their item names.
Vec3_From_Axis_Name :: proc(name: string) -> (Vector3, bool) {
	switch name {
	case "X":
		return Vector3_XAxis, true
	case "Y":
		return Vector3_YAxis, true
	case "Z":
		return Vector3_ZAxis, true
	}
	return Vector3_Zero, false
}

Vec3_From_Normal_Id_Name :: proc(name: string) -> (Vector3, bool) {
	switch name {
	case "Right":
		return Vector3{1, 0, 0}, true
	case "Left":
		return Vector3{-1, 0, 0}, true
	case "Top":
		return Vector3{0, 1, 0}, true
	case "Bottom":
		return Vector3{0, -1, 0}, true
	case "Back":
		return Vector3{0, 0, 1}, true
	case "Front":
		return Vector3{0, 0, -1}, true
	}
	return Vector3_Zero, false
}
