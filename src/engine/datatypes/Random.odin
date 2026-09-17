package datatypes

import "core:math"

Random :: struct {
	State: u64,
}

Random_New :: proc(seed: u64) -> Random {
	return Random{
		State = seed,
	}
}

Random_Clone :: proc(random: Random) -> Random {
	return random
}

Random_Next_U64 :: proc(random: ^Random) -> u64 {
	random.State += 0x9E3779B97F4A7C15

	z := random.State

	z = (z ~ (z >> 30)) * 0xBF58476D1CE4E5B9
	z = (z ~ (z >> 27)) * 0x94D049BB133111EB
	z = z ~ (z >> 31)

	return z
}

Random_Next_Unit :: proc(random: ^Random) -> f64 {
	value := Random_Next_U64(random) >> 11

	return f64(value) / 9007199254740991.0
}

Random_Next_Bounded :: proc(
	random: ^Random,
	bound: u64,
) -> u64 {
	if bound == 0 {
		return 0
	}

	threshold := (u64(0) - bound) % bound

	for {
		value := Random_Next_U64(random)

		if value >= threshold {
			return value % bound
		}
	}
}

Random_Next_Integer :: proc(
	random: ^Random,
	minimum,
	maximum: i64,
) -> i64 {
	if minimum == maximum {
		return minimum
	}

	span := u64(maximum - minimum) + 1

	return minimum + i64(
		Random_Next_Bounded(random, span),
	)
}

Random_Next_Number :: proc(
	random: ^Random,
	minimum: f64 = 0,
	maximum: f64 = 1,
) -> f64 {
	if minimum == maximum {
		return minimum
	}

	return minimum +
	       (maximum - minimum) *
	       Random_Next_Unit(random)
}

Random_Next_Unit_Vector :: proc(
	random: ^Random,
) -> Vector3 {
	z := Random_Next_Number(random, -1, 1)
	theta := Random_Next_Number(random, 0, math.TAU)

	radius := math.sqrt(max(0.0, 1.0-z*z))

	return Vector3{
		f32(radius * math.cos(theta)),
		f32(radius * math.sin(theta)),
		f32(z),
	}
}