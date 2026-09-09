package datatypes

NumberRange :: struct {
	Min: f32,
	Max: f32,
}

NumberRange_New :: proc(value: f32) -> NumberRange {
	return NumberRange{value, value}
}

NumberRange_New2 :: proc(minimum, maximum: f32) -> (NumberRange, bool) {
	if minimum != minimum || maximum != maximum || minimum > maximum {
		return {}, false
	}
	return NumberRange{minimum, maximum}, true
}
