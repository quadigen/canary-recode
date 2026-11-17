package datatypes

import tracy "../util/odin-tracy"
import vm "../vm"
import "core:fmt"
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

date_time_from_iso_date :: proc "c" (L: ^vm.State) -> i32 {
	context = tracy.DefaultContext()

	binding := binding_from_upvalue(L)
	iso := vm.ArgString(L, 1)

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

date_time_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	date_time := cast(^DateTime)value

	switch key {
	case "UnixTimestamp":
		vm.PushNumber(L, DateTime_UnixTimestamp(date_time^))

	case "UnixTimestampMillis":
		vm.PushNumber(L, date_time.UnixTimestampMillis)

	case "FormatLocalTime":
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
		name = "DateTime",
		get = date_time_get,
		string = date_time_string,
		destroy = date_time_destroy,
		equal = date_time_equal,
	}
	when ODIN_OS != .JS {
		binding.namecall = date_time_namecall
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
}
