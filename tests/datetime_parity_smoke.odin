package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)
	source := `
local a = DateTime.fromUniversalTime(2024, 2, 29, 23, 59, 58, 125)
local components = a:ToUniversalTime()
assert(components.Year == 2024 and components.Month == 2 and components.Day == 29)
assert(components.Hour == 23 and components.Minute == 59)
assert(components.Second == 58 and components.Millisecond == 125)
assert(a:ToIsoDate() == "2024-02-29T23:59:58.125Z")
assert(DateTime.fromIsoDate(a:ToIsoDate()) == a)
assert(a:FormatUniversalTime("YYYY-MM-DD", "en-us") == "2024-02-29")
assert(a:FormatUniversalTime("YYYY-MM-DD HH:mm:ss", "en-us") == "2024-02-29 23:59:58")
assert(a:FormatUniversalTime("LTS", "en-US") == "11:59:58 PM")
assert(not pcall(function() DateTime.fromUniversalTime(2023, 2, 29) end))
assert(not pcall(function() DateTime.fromUniversalTime(2024, 13, 1) end))
assert(DateTime.fromIsoDate("invalid-date") == nil)
assert(DateTime.fromUniversalTime(2024, 1, 1, 0, 90):ToIsoDate() == "2024-01-01T01:30:00Z")

local ancient = DateTime.fromUniversalTime(1400, 1, 1)
assert(ancient:ToIsoDate() == "1400-01-01T00:00:00Z")
assert(DateTime.fromIsoDate(ancient:ToIsoDate()) == ancient)
local future = DateTime.fromUniversalTime(9999, 12, 31, 23, 59, 59, 999)
assert(future:ToIsoDate() == "9999-12-31T23:59:59.999Z")
assert(DateTime.fromIsoDate(future:ToIsoDate()) == future)
assert(DateTime.fromIsoDate("2400-01-01T00:00:00Z"):ToUniversalTime().Year == 2400)

local epoch = DateTime.fromUnixTimestamp(1.25)
assert(epoch.UnixTimestampMillis == 1250)
assert(DateTime.fromUnixTimestampMillis(-1):ToIsoDate() == "1969-12-31T23:59:59.999Z")
local localTime = DateTime.fromLocalTime(2024, 3, 1, 12, 0, 0, 750)
local localComponents = localTime:ToLocalTime()
assert(localComponents.Year == 2024 and localComponents.Month == 3 and localComponents.Day == 1)
assert(localComponents.Hour == 12 and localComponents.Minute == 0 and localComponents.Millisecond == 750)
assert(localTime:FormatLocalTime("LTS", "en-us") == "12:00:00 PM")
`
	ok, err := vm.Run(&script_vm, source, "datetime_parity_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("DateTime parity smoke failed")
	}
	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("DATETIME_PARITY_SMOKE_PASSED")
}
