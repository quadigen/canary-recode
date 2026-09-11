package datatypes

import "core:math"

Quaternion :: struct {
	X: f32,
	Y: f32,
	Z: f32,
	W: f32,
}

Quaternion_Identity :: Quaternion{0, 0, 0, 1}

Quaternion_New :: proc(x, y, z, w: f32) -> Quaternion {
	return Quaternion{x, y, z, w}
}

Quaternion_Magnitude :: proc(q: Quaternion) -> f32 {
	return math.sqrt(q.X*q.X + q.Y*q.Y + q.Z*q.Z + q.W*q.W)
}

Quaternion_Unit :: proc(q: Quaternion) -> Quaternion {
	magnitude := Quaternion_Magnitude(q)

	if magnitude <= 1.0e-8 {
		return Quaternion_Identity
	}

	inverse := 1.0 / magnitude
	return Quaternion{
		q.X * inverse,
		q.Y * inverse,
		q.Z * inverse,
		q.W * inverse,
	}
}

Quaternion_Conjugate :: proc(q: Quaternion) -> Quaternion {
	return Quaternion{-q.X, -q.Y, -q.Z, q.W}
}

Quaternion_Inverse :: proc(q: Quaternion) -> Quaternion {
	length_squared := q.X*q.X + q.Y*q.Y + q.Z*q.Z + q.W*q.W

	if length_squared <= 1.0e-12 {
		return Quaternion_Identity
	}

	conjugate := Quaternion_Conjugate(q)
	inverse := 1.0 / length_squared

	return Quaternion{
		conjugate.X * inverse,
		conjugate.Y * inverse,
		conjugate.Z * inverse,
		conjugate.W * inverse,
	}
}

Quaternion_Dot :: proc(a, b: Quaternion) -> f32 {
	return a.X*b.X + a.Y*b.Y + a.Z*b.Z + a.W*b.W
}

Quaternion_Multiply :: proc(a, b: Quaternion) -> Quaternion {
	return Quaternion{
		a.W*b.X + a.X*b.W + a.Y*b.Z - a.Z*b.Y,
		a.W*b.Y - a.X*b.Z + a.Y*b.W + a.Z*b.X,
		a.W*b.Z + a.X*b.Y - a.Y*b.X + a.Z*b.W,
		a.W*b.W - a.X*b.X - a.Y*b.Y - a.Z*b.Z,
	}
}

Quaternion_FromAxisAngle :: proc(axis: Vector3, angle: f32) -> Quaternion {
	length := math.sqrt(axis.x*axis.x + axis.y*axis.y + axis.z*axis.z)

	if length <= 1.0e-8 {
		return Quaternion_Identity
	}

	half := angle * 0.5
	s := math.sin(half) / length

	return Quaternion_Unit(Quaternion{
		axis.x * s,
		axis.y * s,
		axis.z * s,
		math.cos(half),
	})
}

Quaternion_Lerp :: proc(a, b: Quaternion, alpha: f32) -> Quaternion {
	t := clamp(alpha, 0, 1)

	return Quaternion_Unit(Quaternion{
		a.X + (b.X-a.X)*t,
		a.Y + (b.Y-a.Y)*t,
		a.Z + (b.Z-a.Z)*t,
		a.W + (b.W-a.W)*t,
	})
}

Quaternion_Slerp :: proc(a, b: Quaternion, alpha: f32) -> Quaternion {
	left := Quaternion_Unit(a)
	right := Quaternion_Unit(b)
	dot := Quaternion_Dot(left, right)

	if dot < 0 {
		right = Quaternion{-right.X, -right.Y, -right.Z, -right.W}
		dot = -dot
	}

	dot = clamp(dot, -1, 1)

	if dot > 0.9995 {
		return Quaternion_Lerp(left, right, alpha)
	}

	theta_0 := math.acos(dot)
	sin_theta_0 := math.sin(theta_0)

	if sin_theta_0 <= 1.0e-8 {
		return left
	}

	t := clamp(alpha, 0, 1)
	theta := theta_0 * t

	s0 := math.sin(theta_0-theta) / sin_theta_0
	s1 := math.sin(theta) / sin_theta_0

	return Quaternion_Unit(Quaternion{
		left.X*s0 + right.X*s1,
		left.Y*s0 + right.Y*s1,
		left.Z*s0 + right.Z*s1,
		left.W*s0 + right.W*s1,
	})
}

Quaternion_ToAxisAngle :: proc(q: Quaternion) -> (axis: Vector3, angle: f32) {
	unit := Quaternion_Unit(q)
	w := clamp(unit.W, -1, 1)
	angle = 2 * math.acos(w)

	scale := math.sqrt(max(1-unit.W*unit.W, 0))

	if scale <= 1.0e-6 {
		return Vector3{1, 0, 0}, 0
	}

	return Vector3{
		unit.X / scale,
		unit.Y / scale,
		unit.Z / scale,
	}, angle
}
