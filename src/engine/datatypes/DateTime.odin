package datatypes

import "core:time"

DateTime :: struct {
	UnixTimestampMillis: i64,
}

DateTime_Now :: proc() -> DateTime {
	return DateTime{time.to_unix_nanoseconds(time.now()) / 1_000_000}
}

DateTime_FromUnixTimestamp :: proc(seconds: i64) -> DateTime {
	return DateTime{seconds * 1_000}
}

DateTime_FromUnixTimestampMillis :: proc(milliseconds: i64) -> DateTime {
	return DateTime{milliseconds}
}

DateTime_UnixTimestamp :: proc(value: DateTime) -> i64 {
	return value.UnixTimestampMillis / 1_000
}
