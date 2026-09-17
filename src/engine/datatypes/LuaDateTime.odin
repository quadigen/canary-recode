package datatypes

import "base:runtime"
import "core:fmt"
import vm "../vm"

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
	context = runtime.default_context()
	push_date_time(L, binding_from_upvalue(L), DateTime_Now())
	return 1
}

date_time_from_unix_timestamp :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_date_time(L, binding_from_upvalue(L), DateTime_FromUnixTimestamp(vm.ArgInteger(L, 1)))
	return 1
}

date_time_from_unix_timestamp_millis :: proc "c" (L: ^vm.State) -> i32 {
	context = runtime.default_context()
	push_date_time(L, binding_from_upvalue(L), DateTime_FromUnixTimestampMillis(vm.ArgInteger(L, 1)))
	return 1
}

date_time_get :: proc(L: ^vm.State, value, ctx: rawptr, key: string) -> bool {
	date_time := cast(^DateTime)value
	switch key {
	case "UnixTimestamp":
		vm.PushInteger(L, DateTime_UnixTimestamp(date_time^))
	case "UnixTimestampMillis":
		vm.PushInteger(L, date_time.UnixTimestampMillis)
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
	return vm.Userdata_Binding{
		name    = "DateTime",
		get     = date_time_get,
		string  = date_time_string,
		destroy = date_time_destroy,
		equal   = date_time_equal,
	}
}

DateTime_Install_Fields :: proc(L: ^vm.State, binding: ^vm.Userdata_Binding) {
	add_library_function(L, binding, "now", date_time_now)
	add_library_function(L, binding, "fromUnixTimestamp", date_time_from_unix_timestamp)
	add_library_function(L, binding, "fromUnixTimestampMillis", date_time_from_unix_timestamp_millis)
}
