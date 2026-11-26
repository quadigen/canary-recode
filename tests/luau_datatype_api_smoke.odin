package main

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	source := `
local leapDay = DateTime.fromIsoDate("2024-02-29T15:04:05.125Z")
assert(typeof(leapDay) == "DateTime")
assert(leapDay:ToIsoDate() == "2024-02-29T15:04:05.125Z")

local offset = DateTime.fromIsoDate("2024-02-29T17:04:05.125+02:00")
assert(offset == leapDay)
assert(offset:ToIsoDate() == leapDay:ToIsoDate())

local epoch = DateTime.fromIsoDate("1970-01-01T00:00:00Z")
assert(epoch:ToIsoDate() == "1970-01-01T00:00:00Z")
local beforeEpoch = DateTime.fromIsoDate("1969-12-31T23:59:59.5Z")
assert(beforeEpoch:ToIsoDate() == "1969-12-31T23:59:59.5Z")

local current = DateTime.now()
assert(type(current:ToIsoDate()) == "string")
assert(string.sub(current:ToIsoDate(), -1) == "Z")
`

	ok, err := vm.Run(&script_vm, source, "luau_datatype_api_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("Luau datatype API smoke test failed")
	}

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("LUAU_DATATYPE_API_SMOKE_PASSED")
}
