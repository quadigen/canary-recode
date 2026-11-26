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
	return DateTime{math.floor(seconds * 1_000)}
}

DateTime_FromUnixTimestampMillis :: proc(milliseconds: f64) -> DateTime {
	return DateTime{math.floor(milliseconds)}
}

DateTime_UnixTimestamp :: proc(value: DateTime) -> f64 {
	return math.floor(value.UnixTimestampMillis / 1_000)
}


DateTime_Parts :: struct {
	Year, Month, Day:                  i64,
	Hour, Minute, Second, Millisecond: i64,
}

DateTime_Div_Floor :: proc(a, b: i64) -> i64 {
	q := a / b
	if a % b < 0 {q -= 1}
	return q
}

DateTime_Days_In_Month :: proc(year, month: i64) -> i64 {
	if month < 1 || month > 12 {return 0}
	switch month {
	case 2:
		leap := year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
		return 29 if leap else 28
	case 4, 6, 9, 11:
		return 30
	case:
		return 31
	}
}

DateTime_Days_From_Civil :: proc(year, month, day: i64) -> i64 {
	y := year - (1 if month <= 2 else 0)
	era := DateTime_Div_Floor(y, 400)
	yoe := y - era * 400
	adjusted_month := month + (-3 if month > 2 else 9)
	doy := (153 * adjusted_month + 2) / 5 + day - 1
	doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468
}

DateTime_Civil_From_Days :: proc(days: i64) -> (year, month, day: i64) {
	z := days + 719468
	era := DateTime_Div_Floor(z, 146097)
	doe := z - era * 146097
	yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
	year = yoe + era * 400
	doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
	mp := (5 * doy + 2) / 153
	day = doy - (153 * mp + 2) / 5 + 1
	month = mp + (3 if mp < 10 else -9)
	year += (1 if month <= 2 else 0)
	return
}

DateTime_From_Universal_Parts :: proc(parts: DateTime_Parts) -> (DateTime, bool) {
	if parts.Year < 1400 ||
	   parts.Year > 9999 ||
	   parts.Month < 1 ||
	   parts.Month > 12 ||
	   parts.Day < 1 ||
	   parts.Day > DateTime_Days_In_Month(parts.Year, parts.Month) {
		return {}, false
	}


	if parts.Hour < -1_000_000_000 ||
	   parts.Hour > 1_000_000_000 ||
	   parts.Minute < -1_000_000_000 ||
	   parts.Minute > 1_000_000_000 ||
	   parts.Second < -1_000_000_000 ||
	   parts.Second > 1_000_000_000 ||
	   parts.Millisecond < -1_000_000_000 ||
	   parts.Millisecond > 1_000_000_000 {
		return {}, false
	}
	millis :=
		DateTime_Days_From_Civil(parts.Year, parts.Month, parts.Day) * 86_400_000 +
		parts.Hour * 3_600_000 +
		parts.Minute * 60_000 +
		parts.Second * 1_000 +
		parts.Millisecond
	if millis < -17_987_443_200_000 || millis > 253_402_300_799_999 {
		return {}, false
	}
	return DateTime{UnixTimestampMillis = f64(millis)}, true
}

DateTime_To_Universal_Parts :: proc(value: DateTime) -> (DateTime_Parts, bool) {
	millis := value.UnixTimestampMillis
	if !(millis >= -17_987_443_200_000 && millis <= 253_402_300_799_999) {
		return {}, false
	}
	timestamp := i64(math.floor(millis))
	days := DateTime_Div_Floor(timestamp, 86_400_000)
	remainder := timestamp - days * 86_400_000
	year, month, day := DateTime_Civil_From_Days(days)
	return DateTime_Parts {
			Year = year,
			Month = month,
			Day = day,
			Hour = remainder / 3_600_000,
			Minute = (remainder / 60_000) % 60,
			Second = (remainder / 1_000) % 60,
			Millisecond = remainder % 1_000,
		},
		true
}
