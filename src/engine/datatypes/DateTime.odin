package datatypes

import "core:time"

DateTime :: struct {
	UnixTimestampMillis: f64,
}

DateTime_Now :: proc() -> DateTime {
	return DateTime{f64(time.to_unix_nanoseconds(time.now())) / 1_000_000}
}

DateTime_FromUnixTimestamp :: proc(seconds: f64) -> DateTime {
	return DateTime{seconds * 1_000}
}

DateTime_FromUnixTimestampMillis :: proc(milliseconds: f64) -> DateTime {
	return DateTime{milliseconds}
}

DateTime_UnixTimestamp :: proc(value: DateTime) -> f64 {
	return value.UnixTimestampMillis / 1_000
}
