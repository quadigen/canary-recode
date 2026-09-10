package datatypes

import "core:math"

UDim :: struct {
	Scale:  f32,
	Offset: f32,
}

UDim_Zero :: UDim{}

UDim_New :: proc(scale, offset: f32) -> UDim {
	return UDim{Scale = scale, Offset = offset}
}

UDim_Add :: proc(a, b: UDim) -> UDim {
	return UDim{Scale = a.Scale+b.Scale, Offset = a.Offset+b.Offset}
}

UDim_Subtract :: proc(a, b: UDim) -> UDim {
	return UDim{Scale = a.Scale-b.Scale, Offset = a.Offset-b.Offset}
}

UDim_Lerp :: proc(value, goal: UDim, alpha: f32) -> UDim {
	return UDim{
		Scale = value.Scale+(goal.Scale-value.Scale)*alpha,
		Offset = value.Offset+(goal.Offset-value.Offset)*alpha,
	}
}

UDim_FuzzyEq :: proc(a, b: UDim, epsilon: f32 = 1.0e-5) -> bool {
	return math.abs(a.Scale-b.Scale) <= epsilon && math.abs(a.Offset-b.Offset) <= epsilon
}

