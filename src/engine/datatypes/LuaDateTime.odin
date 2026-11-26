package datatypes

import tracy "../util/odin-tracy"
import vm "../vm"
import "core:fmt"
import "core:math"
import "core:strings"
import "core:time"

push_date_time :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding, value: DateTime) {
	push_value(L, binding, value)
}

Push_DateTime :: proc(L: ^vm.State, registry: ^Registry, value: DateTime) {
	push_date_time(L, &registry.date_time, value)
}

Arg_DateTime :: proc(L: ^vm.State, index: int, registry: ^Registry) -> DateTime {
	if !vm.IsUserdataType(L, index, &registry.date_time) {
		_ = vm.RaiseError(L, "expected DateTime")
		return {}
	}
	return (cast(^DateTime)vm.UserdataValue(L, index))^
}

date_time_now :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	push_date_time(L, binding_from_upvalue(L), DateTime_Now())
	return 1
}

date_time_from_unix_timestamp :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	push_date_time(L, binding_from_upvalue(L), DateTime_FromUnixTimestamp(vm.ArgNumber(L, 1)))
	return 1
}

date_time_from_unix_timestamp_millis :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	push_date_time(
		L,
		binding_from_upvalue(L),
		DateTime_FromUnixTimestampMillis(vm.ArgNumber(L, 1)),
	)
	return 1
}


date_time_iso_digits :: proc(iso: string, start, count: int) -> (i64, bool) {
	if start < 0 || start + count > len(iso) {return 0, false}
	value: i64 = 0
	for i in start ..< start + count {
		ch := iso[i]
		if ch < '0' || ch > '9' {return 0, false}
		value = value * 10 + i64(ch - '0')
	}
	return value, true
}

date_time_parse_iso_utc :: proc(iso: string) -> (DateTime, bool) {
	if len(iso) < 20 ||
	   iso[4] != '-' ||
	   iso[7] != '-' ||
	   iso[10] != 'T' ||
	   iso[13] != ':' ||
	   iso[16] != ':' ||
	   iso[len(iso) - 1] != 'Z' {
		return {}, false
	}
	year, ok_year := date_time_iso_digits(iso, 0, 4)
	month, ok_month := date_time_iso_digits(iso, 5, 2)
	day, ok_day := date_time_iso_digits(iso, 8, 2)
	hour, ok_hour := date_time_iso_digits(iso, 11, 2)
	minute, ok_minute := date_time_iso_digits(iso, 14, 2)
	second, ok_second := date_time_iso_digits(iso, 17, 2)
	if !(ok_year && ok_month && ok_day && ok_hour && ok_minute && ok_second) {
		return {}, false
	}
	millisecond: i64 = 0
	if len(iso) > 20 {
		if iso[19] != '.' || len(iso) < 22 || len(iso) > 30 {
			return {}, false
		}
		digits := len(iso) - 21
		for i in 0 ..< digits {
			digit := iso[20 + i]
			if digit < '0' || digit > '9' {return {}, false}
			if i < 3 {millisecond = millisecond * 10 + i64(digit - '0')}
		}
		for i in min(digits, 3) ..< 3 {millisecond *= 10}
	} else if iso[19] != 'Z' {
		return {}, false
	}
	return DateTime_From_Universal_Parts(
		DateTime_Parts {
			Year = year,
			Month = month,
			Day = day,
			Hour = hour,
			Minute = minute,
			Second = second,
			Millisecond = millisecond,
		},
	)
}

date_time_from_iso_date :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()

	binding := binding_from_upvalue(L)
	iso := vm.ArgString(L, 1)
	if parsed_utc, ok := date_time_parse_iso_utc(iso); ok {
		push_date_time(L, binding, parsed_utc)
		return 1
	}

	parsed, consumed := time.iso8601_to_time_utc(iso)

	if consumed == 0 || consumed != len(iso) {
		vm.PushNil(L)
		return 1
	}

	nanos := time.to_unix_nanoseconds(parsed)
	millis := nanos / 1_000_000

	if nanos < 0 && nanos % 1_000_000 != 0 {
		millis -= 1
	}

	push_date_time(L, binding, DateTime_FromUnixTimestampMillis(f64(millis)))

	return 1
}

date_time_read_component :: proc(L: ^vm.State, index: int, fallback: f64) -> (i64, bool) {
	number := math.floor(vm.ArgOptionalNumber(L, index, fallback))
	if !(number >= -1_000_000_000 && number <= 1_000_000_000) {
		return 0, false
	}
	return i64(number), true
}

date_time_read_parts :: proc(L: ^vm.State) -> (DateTime_Parts, bool) {
	year, ok_year := date_time_read_component(L, 1, 1970)
	month, ok_month := date_time_read_component(L, 2, 1)
	day, ok_day := date_time_read_component(L, 3, 1)
	hour, ok_hour := date_time_read_component(L, 4, 0)
	minute, ok_minute := date_time_read_component(L, 5, 0)
	second, ok_second := date_time_read_component(L, 6, 0)
	millisecond, ok_millisecond := date_time_read_component(L, 7, 0)
	if !(ok_year && ok_month && ok_day && ok_hour && ok_minute && ok_second && ok_millisecond) {
		return {}, false
	}
	return DateTime_Parts {
			Year = year,
			Month = month,
			Day = day,
			Hour = hour,
			Minute = minute,
			Second = second,
			Millisecond = millisecond,
		},
		true
}

date_time_from_universal_time :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()
	parts, ok := date_time_read_parts(L)
	if !ok {return vm.RaiseError(L, "DateTime.fromUniversalTime expects finite date components")}
	date_time, valid := DateTime_From_Universal_Parts(parts)
	if !valid {return vm.RaiseError(L, "invalid DateTime.fromUniversalTime date")}
	push_date_time(L, binding_from_upvalue(L), date_time)
	return 1
}

date_time_push_parts :: proc(L: ^vm.State, parts: DateTime_Parts) {
	vm.NewTable(L, 0, 7)
	vm.PushNumber(L, f64(parts.Year)); vm.SetField(L, -2, "Year")
	vm.PushNumber(L, f64(parts.Month)); vm.SetField(L, -2, "Month")
	vm.PushNumber(L, f64(parts.Day)); vm.SetField(L, -2, "Day")
	vm.PushNumber(L, f64(parts.Hour)); vm.SetField(L, -2, "Hour")
	vm.PushNumber(L, f64(parts.Minute)); vm.SetField(L, -2, "Minute")
	vm.PushNumber(L, f64(parts.Second)); vm.SetField(L, -2, "Second")
	vm.PushNumber(L, f64(parts.Millisecond)); vm.SetField(L, -2, "Millisecond")
}

date_time_to_universal_time :: proc(L: ^vm.State, value: ^DateTime) -> i32 {
	parts, ok := DateTime_To_Universal_Parts(value^)
	if !ok {return vm.RaiseError(L, "DateTime timestamp is outside the supported range")}
	date_time_push_parts(L, parts)
	return 1
}

date_time_format_universal_time :: proc(L: ^vm.State, value: ^DateTime) -> i32 {
	format := vm.ArgString(L, 2)
	locale := vm.ArgString(L, 3)
	if !strings.equal_fold(locale, "en-us") {
		return vm.RaiseError(L, "FormatUniversalTime currently supports en-us")
	}
	parts, ok := DateTime_To_Universal_Parts(value^)
	if !ok {return vm.RaiseError(L, "DateTime timestamp is outside the supported range")}
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


date_time_to_iso_date :: proc(L: ^vm.State, value: ^DateTime) -> i32 {
	parts, ok := DateTime_To_Universal_Parts(value^)
	if !ok {
		return vm.RaiseError(L, "DateTime:ToIsoDate timestamp is outside the supported range")
	}
	if parts.Millisecond == 0 {
		vm.PushString(
			L,
			fmt.tprintf(
				"%04d-%02d-%02dT%02d:%02d:%02dZ",
				parts.Year,
				parts.Month,
				parts.Day,
				parts.Hour,
				parts.Minute,
				parts.Second,
			),
		)
	} else {
		vm.PushString(
			L,
			fmt.tprintf(
				"%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
				parts.Year,
				parts.Month,
				parts.Day,
				parts.Hour,
				parts.Minute,
				parts.Second,
				parts.Millisecond,
			),
		)
	}
	return 1
}

date_time_namecall_web :: proc(L: ^vm.State, value, ctx: rawptr, method: string) -> (i32, bool) {
	switch method {
	case "ToIsoDate":
		return date_time_to_iso_date(L, cast(^DateTime)value), true
	case "ToUniversalTime":
		return date_time_to_universal_time(L, cast(^DateTime)value), true
	case "FormatUniversalTime":
		return date_time_format_universal_time(L, cast(^DateTime)value), true
	}
	return 0, false
}

date_time_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	date_time := cast(^DateTime)value

	switch key {
	case "UnixTimestamp":
		vm.PushNumber(L, DateTime_UnixTimestamp(date_time^))

	case "UnixTimestampMillis":
		vm.PushNumber(L, date_time.UnixTimestampMillis)

	case "ToIsoDate", "ToUniversalTime", "FormatUniversalTime":
		vm.PushUserdataMethod(L, key)

	case "ToLocalTime", "FormatLocalTime":
		when ODIN_OS != .JS {
			vm.PushUserdataMethod(L, key)
		} else {
			return false
		}

	case:
		return false
	}

	return true
}

date_time_equal :: proc(value, other, ctx: rawptr) -> bool {
	return (cast(^DateTime)value)^ == (cast(^DateTime)other)^
}

date_time_string :: proc(value, ctx: rawptr) -> string {
	date_time := cast(^DateTime)value
	return fmt.tprintf("%d", date_time.UnixTimestampMillis)
}

date_time_destroy :: proc(value, ctx: rawptr) {
	free(cast(^DateTime)value)
}

DateTime_Luau_Binding :: proc() -> vm.Userdata_Binding {
	binding := vm.Userdata_Binding {
		name    = "DateTime",
		get     = date_time_get,
		string  = date_time_string,
		destroy = date_time_destroy,
		equal   = date_time_equal,
	}
	when ODIN_OS != .JS {
		binding.namecall = date_time_namecall
	} else {
		binding.namecall = date_time_namecall_web
	}
	return binding
}

DateTime_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "now", date_time_now)
	add_library_function(L, binding, "fromUnixTimestamp", date_time_from_unix_timestamp)
	add_library_function(
		L,
		binding,
		"fromUnixTimestampMillis",
		date_time_from_unix_timestamp_millis,
	)
	add_library_function(L, binding, "fromIsoDate", date_time_from_iso_date)
	add_library_function(L, binding, "fromUniversalTime", date_time_from_universal_time)
	when ODIN_OS != .JS {
		add_library_function(L, binding, "fromLocalTime", date_time_from_local_time)
	}
}
