package datatypes

Vector2int16 :: struct {
	X: i16,
	Y: i16,
}

Vector2int16_Zero :: Vector2int16{0, 0}

Vector2int16_New :: proc(x, y: i16) -> Vector2int16 {
	return Vector2int16{x, y}
}

Vector2int16_Add :: proc(a, b: Vector2int16) -> Vector2int16 {
	return Vector2int16{
		i16(i32(a.X) + i32(b.X)),
		i16(i32(a.Y) + i32(b.Y)),
	}
}

Vector2int16_Subtract :: proc(a, b: Vector2int16) -> Vector2int16 {
	return Vector2int16{
		i16(i32(a.X) - i32(b.X)),
		i16(i32(a.Y) - i32(b.Y)),
	}
}
