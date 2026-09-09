package datatypes

Rect :: struct {
	Min: Vector2,
	Max: Vector2,
}

Rect_Width :: proc(rect: Rect) -> f32 {
	return rect.Max.X - rect.Min.X
}

Rect_Height :: proc(rect: Rect) -> f32 {
	return rect.Max.Y - rect.Min.Y
}
