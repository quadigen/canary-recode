#+build !js
package datatypes

import "core:c/libc"
import "core:fmt"
import "core:math"
import "core:strings"
import vm "../vm"

date_time_namecall :: proc(L: ^vm.State, value, ctx: rawptr, method: string) -> (i32, bool) {
	if method != "FormatLocalTime" {return 0, false}

	format := vm.ArgString(L, 2)
	locale := vm.ArgString(L, 3)
	if format != "LTS" || !strings.equal_fold(locale, "en-us") {
		return vm.RaiseError(L, "FormatLocalTime currently supports LTS with en-US"), true
	}

	seconds := DateTime_UnixTimestamp((cast(^DateTime)value)^)
	if math.is_nan(seconds) || seconds < -62135596800 || seconds > 253402300799 {
		return vm.RaiseError(L, "DateTime timestamp out of range"), true
	}
	timestamp := libc.time_t(seconds)
	local_time := libc.localtime(&timestamp)
	if local_time == nil {return vm.RaiseError(L, "could not convert DateTime to local time"), true}

	hour := int(local_time.tm_hour)
	period := "AM" if hour < 12 else "PM"
	display_hour := (hour + 11) % 12 + 1
	vm.PushString(
		L,
		fmt.tprintf("%d:%02d:%02d %s", display_hour, local_time.tm_min, local_time.tm_sec, period),
	)
	return 1, true
}
