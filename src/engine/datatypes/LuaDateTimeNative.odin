#+build !js
package datatypes

import tracy "../util/odin-tracy"
import vm "../vm"
import "core:c/libc"
import "core:fmt"
import "core:strings"

date_time_from_local_time :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	parts, ok := date_time_read_parts(L)
	if !ok {return vm.RaiseError(L, "DateTime.fromLocalTime expects finite date components")}
	if parts.Year < 1400 ||
	   parts.Year > 9999 ||
	   parts.Month < 1 ||
	   parts.Month > 12 ||
	   parts.Day < 1 ||
	   parts.Day > DateTime_Days_In_Month(parts.Year, parts.Month) {
		return vm.RaiseError(L, "invalid DateTime.fromLocalTime date")
	}

	local := libc.tm {
		tm_year  = i32(parts.Year - 1900),
		tm_mon   = i32(parts.Month - 1),
		tm_mday  = i32(parts.Day),
		tm_hour  = i32(parts.Hour),
		tm_min   = i32(parts.Minute),
		tm_sec   = i32(parts.Second),
		tm_isdst = -1,
	}
	seconds := libc.mktime(&local)
	millis := f64(seconds) * 1000 + f64(parts.Millisecond)
	if !(millis >= -17_987_443_200_000 && millis <= 253_402_300_799_999) {
		return vm.RaiseError(L, "DateTime.fromLocalTime timestamp is outside the supported range")
	}
	push_date_time(L, binding_from_upvalue(L), DateTime_FromUnixTimestampMillis(millis))
	return 1
}

date_time_local_parts :: proc(value: ^DateTime) -> (DateTime_Parts, bool) {
	utc, valid := DateTime_To_Universal_Parts(value^)
	if !valid {return {}, false}
	seconds := DateTime_UnixTimestamp(value^)
	timestamp := libc.time_t(seconds)
	local := libc.localtime(&timestamp)
	if local == nil {return {}, false}
	return DateTime_Parts {
			Year = i64(local.tm_year) + 1900,
			Month = i64(local.tm_mon) + 1,
			Day = i64(local.tm_mday),
			Hour = i64(local.tm_hour),
			Minute = i64(local.tm_min),
			Second = i64(local.tm_sec),
			Millisecond = utc.Millisecond,
		},
		true
}

date_time_format_local :: proc(L: ^vm.State, value: ^DateTime) -> i32 {
	format := vm.ArgString(L, 2)
	locale := vm.ArgString(L, 3)
	if !strings.equal_fold(locale, "en-us") {
		return vm.RaiseError(L, "FormatLocalTime currently supports en-us")
	}
	parts, ok := date_time_local_parts(value)
	if !ok {return vm.RaiseError(L, "could not convert DateTime to local time")}
	switch format {
	case "YYYY-MM-DD":
		vm.PushString(L, fmt.tprintf("%04d-%02d-%02d", parts.Year, parts.Month, parts.Day))
	case "YYYY-MM-DD HH:mm:ss":
		vm.PushString(
			L,
			fmt.tprintf(
				"%04d-%02d-%02d %02d:%02d:%02d",
				parts.Year,
				parts.Month,
				parts.Day,
				parts.Hour,
				parts.Minute,
				parts.Second,
			),
		)
	case "HH:mm:ss":
		vm.PushString(L, fmt.tprintf("%02d:%02d:%02d", parts.Hour, parts.Minute, parts.Second))
	case "LTS":
		period := "AM" if parts.Hour < 12 else "PM"
		hour := (parts.Hour + 11) % 12 + 1
		vm.PushString(L, fmt.tprintf("%d:%02d:%02d %s", hour, parts.Minute, parts.Second, period))
	case:
		return vm.RaiseError(L, "unsupported DateTime format token for en-us")
	}
	return 1
}

date_time_namecall :: proc(L: ^vm.State, value, ctx: rawptr, method: string) -> (i32, bool) {
	date_time := cast(^DateTime)value
	switch method {
	case "ToIsoDate":
		return date_time_to_iso_date(L, date_time), true
	case "ToUniversalTime":
		return date_time_to_universal_time(L, date_time), true
	case "FormatUniversalTime":
		return date_time_format_universal_time(L, date_time), true
	case "ToLocalTime":
		parts, ok := date_time_local_parts(date_time)
		if !ok {return vm.RaiseError(L, "could not convert DateTime to local time"), true}
		date_time_push_parts(L, parts)
		return 1, true
	case "FormatLocalTime":
		return date_time_format_local(L, date_time), true
	}
	return 0, false
}
