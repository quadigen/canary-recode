package datatypes

import "core:math"
import "core:time"

DateTime :: struct {
	UnixTimestampMillis: f64,
}

DateTime_Now :: proc() -> DateTime {
	nanos := time.to_unix_nanoseconds(time.now())
	return DateTime{math.floor(f64(nanos) / 1_000_000)}
}

DateTime_FromUnixTimestamp :: proc(seconds: f64) -> DateTime {
	return DateTime{math.floor(seconds) * 1_000}
}

DateTime_FromUnixTimestampMillis :: proc(milliseconds: f64) -> DateTime {
	return DateTime{math.floor(milliseconds)}
}

DateTime_UnixTimestamp :: proc(value: DateTime) -> f64 {
	return math.floor(value.UnixTimestampMillis / 1_000)
}
