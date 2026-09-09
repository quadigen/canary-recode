package datatypes

import "core:math"

UDim2 :: struct {
	X_Scale, X_Offset: f32,
	Y_Scale, Y_Offset: f32,
}

UDim2_Zero :: UDim2{}

UDim2_New :: proc(x_scale, x_offset, y_scale, y_offset: f32) -> UDim2 {
	return UDim2{x_scale, x_offset, y_scale, y_offset}
}

UDim2_FromScale :: proc(x_scale, y_scale: f32) -> UDim2 {
	return UDim2{x_scale, 0, y_scale, 0}
}

UDim2_FromOffset :: proc(x_offset, y_offset: f32) -> UDim2 {
	return UDim2{0, x_offset, 0, y_offset}
}

UDim2_Add :: proc(a, b: UDim2) -> UDim2 {
	return UDim2{
		a.X_Scale+b.X_Scale,
		a.X_Offset+b.X_Offset,
		a.Y_Scale+b.Y_Scale,
		a.Y_Offset+b.Y_Offset,
	}
}

UDim2_Subtract :: proc(a, b: UDim2) -> UDim2 {
	return UDim2{
		a.X_Scale-b.X_Scale,
		a.X_Offset-b.X_Offset,
		a.Y_Scale-b.Y_Scale,
		a.Y_Offset-b.Y_Offset,
	}
}

UDim2_Lerp :: proc(value, goal: UDim2, alpha: f32) -> UDim2 {
	return UDim2{
		value.X_Scale+(goal.X_Scale-value.X_Scale)*alpha,
		value.X_Offset+(goal.X_Offset-value.X_Offset)*alpha,
		value.Y_Scale+(goal.Y_Scale-value.Y_Scale)*alpha,
		value.Y_Offset+(goal.Y_Offset-value.Y_Offset)*alpha,
	}
}

UDim2_FuzzyEq :: proc(a, b: UDim2, epsilon: f32 = 1.0e-5) -> bool {
	return math.abs(a.X_Scale-b.X_Scale) <= epsilon &&
	       math.abs(a.X_Offset-b.X_Offset) <= epsilon &&
	       math.abs(a.Y_Scale-b.Y_Scale) <= epsilon &&
	       math.abs(a.Y_Offset-b.Y_Offset) <= epsilon
}
