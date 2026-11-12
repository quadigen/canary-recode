package main

import "core:fmt"
import "core:os"
import "core:time"
import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm, nil, .Editor)
	defer engine_runtime.Environment_Destroy(&environment)
	defer vm.Close(&script_vm)

	service := cast(^services.PlaytestService)services.Ensure_Service(&environment.services, "PlaytestService")
	reader, writer, pipe_error := os.pipe()
	assert(pipe_error == nil)
	defer os.close(writer)
	service.server_output.read = reader
	client_reader, client_writer, client_pipe_error := os.pipe()
	assert(client_pipe_error == nil)
	defer os.close(client_writer)
	service.client_output.read = client_reader
	service.running = true
	output: string = `[LOG] first playtest line
[LOG] second playtest line
[WARN] particle warning
[WARN] debugger warning
[WARN] particle warning
[WARN] debugger warning
[LOG] second playtest line
`
	written, write_error := os.write(writer, transmute([]u8)output)
	assert(write_error == nil && written == len(output))
	client_output: string = "[WARN] particle warning\n"
	_, write_error = os.write(client_writer, transmute([]u8)client_output)
	assert(write_error == nil)

	ok, err := vm.RunInternal(&script_vm, `
local playtest = game:GetService("PlaytestService")
received = {}
game:GetService("LogService").MessageOut:Connect(function(message)
    table.insert(received, message)
    if #received == 1 then
        assert(playtest.IsRunning)
    end
end)
assert(playtest.IsRunning)
assert(playtest.IsRunning)
assert(#received == 6)
assert(received[1] == "[Playtest server] first playtest line")
assert(received[2] == "[Playtest server] second playtest line")
assert(received[3] == "[Playtest server] particle warning")
assert(received[4] == "[Playtest server] debugger warning")
assert(received[5] == received[2])
assert(received[6] == "[Playtest client] particle warning")
`, "playtest_output_smoke")
	assert(ok, err)

	warning := service.server_output.warnings["particle warning"]
	warning.last_emitted = time.tick_add(time.tick_now(), -services.PLAYTEST_WARNING_INTERVAL)
	service.server_output.warnings["particle warning"] = warning
	_, write_error = os.write(writer, transmute([]u8)client_output)
	assert(write_error == nil)
	ok, err = vm.RunInternal(&script_vm, `
assert(game:GetService("PlaytestService").IsRunning)
assert(#received == 7)
assert(received[7] == "[Playtest server] particle warning (1 repeats suppressed)")
`, "playtest_output_warning_interval")
	assert(ok, err)
	fmt.println("PLAYTEST_OUTPUT_SMOKE_PASSED")
}
