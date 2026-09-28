package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

main :: proc() {
	// A playtest client must reach the network. The server owns the map and any
	// characters, so a client that skips replication never receives them. This
	// asserts the startup wiring that makes that connection, which is easy to
	// regress because the failure only shows up as a silently empty client.
	playtest_options := startup_options_for(
		[]string{"--client", "--playtest-host", "--address", "127.0.0.1", "--port", "1234"},
	)
	assert(playtest_options.playtest, "the playtest client was not marked as a playtest")
	assert(playtest_options.standalone == false, "a networked client must not be standalone")
	assert(playtest_options.address == "127.0.0.1")
	assert(playtest_options.port == 1234)

	// A plain client is a shipping target: no playtest flag, still networked.
	plain_options := startup_options_for(
		[]string{"--client", "--address", "127.0.0.1", "--port", "1234"},
	)
	assert(plain_options.playtest == false, "a hand-launched client must not be a playtest")
	assert(plain_options.standalone == false)

	// Standalone is the one genuinely network-free client mode.
	standalone_options := startup_options_for([]string{"--client"})
	assert(standalone_options.playtest == false)

	// --playtest still carries its own map path for a directly launched playtest.
	direct_options := startup_options_for(
		[]string{"--client", "--playtest", "world.kine", "--address", "127.0.0.1"},
	)
	assert(direct_options.playtest, "--playtest must set the playtest flag")
	assert(direct_options.map_path == "world.kine")

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
