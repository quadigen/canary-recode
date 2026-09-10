package datatypes

import "core:math"

Vector2 :: struct {
	X, Y: f32,
}

Vector2_Zero  :: Vector2{0, 0}
Vector2_One   :: Vector2{1, 1}
Vector2_XAxis :: Vector2{1, 0}
Vector2_YAxis :: Vector2{0, 1}

Vec2_New :: proc(x, y: f32) -> Vector2 {
	return Vector2{x, y}
}

Vec2_Add :: proc(a, b: Vector2) -> Vector2 {
	return Vector2{a.X+b.X, a.Y+b.Y}
}

Vec2_Subtract :: proc(a, b: Vector2) -> Vector2 {
	return Vector2{a.X-b.X, a.Y-b.Y}
}

Vec2_Multiply :: proc(a, b: Vector2) -> Vector2 {
	return Vector2{a.X*b.X, a.Y*b.Y}
}

Vec2_Multiply_Scalar :: proc(value: Vector2, scalar: f32) -> Vector2 {
	return Vector2{value.X*scalar, value.Y*scalar}
}

Vec2_Divide :: proc(a, b: Vector2) -> Vector2 {
	return Vector2{a.X/b.X, a.Y/b.Y}
}

Vec2_Divide_Scalar :: proc(value: Vector2, scalar: f32) -> Vector2 {
	return Vector2{value.X/scalar, value.Y/scalar}
}

Vec2_Negate :: proc(value: Vector2) -> Vector2 {
	return Vector2{-value.X, -value.Y}
}

Vec2_Dot :: proc(a, b: Vector2) -> f32 {
	return a.X*b.X+a.Y*b.Y
}

Vec2_Cross :: proc(a, b: Vector2) -> f32 {
	return a.X*b.Y-a.Y*b.X
}

Vec2_Magnitude :: proc(value: Vector2) -> f32 {
	return math.sqrt(Vec2_Dot(value, value))
}

Vec2_Unit :: proc(value: Vector2) -> Vector2 {
	magnitude := Vec2_Magnitude(value)
	if magnitude == 0 {
		return Vector2_Zero
	}
	return Vec2_Divide_Scalar(value, magnitude)
}

Vec2_Lerp :: proc(value, goal: Vector2, alpha: f32) -> Vector2 {
	return Vector2{
		value.X+(goal.X-value.X)*alpha,
		value.Y+(goal.Y-value.Y)*alpha,
	}
}

Vec2_FuzzyEq :: proc(a, b: Vector2, epsilon: f32 = 1.0e-5) -> bool {
	return math.abs(a.X-b.X) <= epsilon && math.abs(a.Y-b.Y) <= epsilon
}

