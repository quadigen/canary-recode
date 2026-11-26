package main

import sdl3 "../src/engine/platform"
import renderer "../src/engine/renderer"
import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"
import "core:fmt"

run_script :: proc(state: ^vm.VM, source: string, internal := false) {
	ok, err := false, ""
	if internal {
		ok, err = vm.RunInternal(state, source, "terminal_service_smoke")
	} else {
		ok, err = vm.Run(state, source, "terminal_service_smoke")
	}
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("TerminalService smoke failed")
	}
}

main :: proc() {
	state := vm.New()
	view: renderer.RendererObject
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &state, &view, .Editor)
	defer {
		vm.Close(&state)
		engine_runtime.Environment_Destroy(&environment)
	}
	run_script(
		&state,
		`
local ok, service = pcall(function() return game:GetService("TerminalService") end)
assert(not ok or service == nil)
assert(not pcall(function() return Instance.new("TerminalService") end))
`,
	)
	run_script(
		&state,
		`
terminal = game:GetService("TerminalService")
assert(not terminal.Archivable and not terminal.CanReplicate)
session = terminal:CreateTerminal("/tmp")
other = terminal:CreateTerminal("/tmp")
assert(session ~= other)
assert(terminal:Execute(session, "test -t 0 && printf '%s%s\\n' 'PTY_' 'OK'"))
assert(terminal:Execute(session, "cd /"))
assert(terminal:Execute(session, "pwd"))
assert(#terminal:GetHistory(session) == 3)
assert(#terminal:GetHistory(other) == 0)
output = ""
`,
		true,
	)
	run_script(
		&state,
		`
assert(not pcall(function() terminal:Execute(session, "echo forbidden") end))
assert(not pcall(function() terminal:GetHistory(session) end))
`,
	)
	for _ in 0 ..< 100 {
		sdl3.Delay(10)
		run_script(&state, `output ..= terminal:ReadOutput(session)`, true)
	}
	run_script(
		&state,
		`
assert(output:find("PTY_OK", 1, true), output)
assert(output:find(string.char(10) .. "/" .. string.char(13), 1, true), output)
assert(terminal:GetHistory(session)[2] == "cd /")
terminal:ClearHistory(other)
assert(#terminal:GetHistory(other) == 0)
terminal:CloseTerminal(other)
assert(not pcall(function() terminal:GetHistory(other) end))
assert(terminal:Execute(session, "exit 7"))
`,
		true,
	)
	for _ in 0 ..< 100 {
		sdl3.Delay(10)
		run_script(&state, `output ..= terminal:ReadOutput(session)`, true)
	}
	run_script(
		&state,
		`
assert(not terminal:IsRunning(session))
assert(terminal:GetExitCode(session) == 7, tostring(terminal:GetExitCode(session)))
terminal:CloseTerminal(session)
`,
		true,
	)
	fmt.println("TERMINAL_SERVICE_SMOKE_PASSED")
}
