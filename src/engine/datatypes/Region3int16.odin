package datatypes

Region3int16 :: struct {
	Min: Vector3int16,
	Max: Vector3int16,
}

Region3int16_New :: proc(a, b: Vector3int16) -> Region3int16 {
	return Region3int16{
		Min = Vector3int16{
			min(a.X, b.X),
			min(a.Y, b.Y),
			min(a.Z, b.Z),
		},
		Max = Vector3int16{
			max(a.X, b.X),
			max(a.Y, b.Y),
			max(a.Z, b.Z),
		},
	}
}

Region3int16_Size :: proc(region: Region3int16) -> Vector3int16 {
	return Vector3int16{
		i16(i32(region.Max.X)-i32(region.Min.X)),
		i16(i32(region.Max.Y)-i32(region.Min.Y)),
		i16(i32(region.Max.Z)-i32(region.Min.Z)),
	}
}
