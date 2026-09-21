package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	ok, err := vm.RunInternal(&script_vm, `
local playtest = game:GetService("PlaytestService")
assert(playtest ~= nil)
assert(playtest.IsRunning == false)
assert(playtest.ProcessId == 0, "pid=" .. tostring(playtest.ProcessId))
assert(playtest.LastError == "", "error=" .. tostring(playtest.LastError))
local started, message = pcall(function()
    playtest:Start("not-a-map.txt")
end)
assert(started == false)
assert(string.find(message, ".kine file path", 1, true) ~= nil)
`, "playtest_service_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("playtest service smoke failed")
	}

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)
	fmt.println("PLAYTEST_SERVICE_SMOKE_PASSED")
}
