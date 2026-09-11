package datatypes

Vector3int16 :: struct {
	X: i16,
	Y: i16,
	Z: i16,
}

Vector3int16_Zero :: Vector3int16{0, 0, 0}

Vector3int16_New :: proc(x, y, z: i16) -> Vector3int16 {
	return Vector3int16{x, y, z}
}

Vector3int16_Add :: proc(a, b: Vector3int16) -> Vector3int16 {
	return Vector3int16{
		i16(i32(a.X) + i32(b.X)),
		i16(i32(a.Y) + i32(b.Y)),
		i16(i32(a.Z) + i32(b.Z)),
	}
}

Vector3int16_Subtract :: proc(a, b: Vector3int16) -> Vector3int16 {
	return Vector3int16{
		i16(i32(a.X) - i32(b.X)),
		i16(i32(a.Y) - i32(b.Y)),
		i16(i32(a.Z) - i32(b.Z)),
	}
}
