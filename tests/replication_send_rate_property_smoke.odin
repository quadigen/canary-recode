package main

import "core:fmt"
import "core:time"

import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("ReplicatorService.SendRate property integration smoke failed")
	}
}

main :: proc() {
	server_vm := vm.New()
	server: engine_runtime.Environment
	engine_runtime.Environment_Init(&server, &server_vm)

	run_script(
		&server_vm,
		`
local r = game:GetService("ReplicatorService")
assert(r.SendRate == 4 * 1024 * 1024, "SendRate default must be 4 MiB/s")
r.SendRate = 2 * 1024 * 1024
assert(r.SendRate == 2 * 1024 * 1024)
assert(not pcall(function() r.SendRate = 0 end))
assert(not pcall(function() r.SendRate = 65535.5 end))
assert(not pcall(function() r.SendRate = "unlimited" end))
assert(not pcall(function() r.SendRate = 64 * 1024 * 1024 + 1 end))
assert(r.SendRate == 2 * 1024 * 1024, "invalid writes must preserve prior rate")
assert(r:StartServer("127.0.0.1", 39861))
assert(r.SendRate == 2 * 1024 * 1024)
r.SendRate = 4 * 1024 * 1024
assert(r.SendRate == 4 * 1024 * 1024)
`,
		"server_send_rate",
	)

	server_rep := cast(^services.ReplicatorService)services.Find_Service(&server.services, "ReplicatorService").object
	assert(server_rep != nil && server_rep.host != nil)
	assert(services.replication_get_send_rate(server_rep) == 4 * 1024 * 1024)

	client_vm := vm.New()
	client: engine_runtime.Environment
	engine_runtime.Environment_Init(&client, &client_vm)

	run_script(
		&client_vm,
		`
local r = game:GetService("ReplicatorService")
r.SendRate = 1024 * 1024
assert(r:ConnectClient("127.0.0.1", 39861))
assert(r.SendRate == 1024 * 1024)
`,
		"client_send_rate",
	)

	client_rep := cast(^services.ReplicatorService)services.Find_Service(&client.services, "ReplicatorService").object
	assert(client_rep != nil && client_rep.host != nil)

	start := time.tick_now()
	for time.tick_since(start) < 5 * time.Second && !client_rep.handshake_complete {
		engine_runtime.Environment_Render_Step(&server, &server_vm, 1.0 / 60.0)
		engine_runtime.Environment_Render_Step(&client, &client_vm, 1.0 / 60.0)
		time.sleep(3 * time.Millisecond)
	}
	assert(
		client_rep.handshake_complete,
		"client must connect after custom send-rate configuration",
	)

	run_script(
		&client_vm,
		`
local r = game:GetService("ReplicatorService")
r.SendRate = 8 * 1024 * 1024
assert(r.SendRate == 8 * 1024 * 1024)
r:Stop()
assert(r.SendRate == 8 * 1024 * 1024, "send rate should persist across Stop")
`,
		"live_client_send_rate",
	)

	run_script(
		&server_vm,
		`
local r = game:GetService("ReplicatorService")
r:Stop()
assert(r.SendRate == 4 * 1024 * 1024)
`,
		"server_stop_send_rate",
	)

	fmt.println("REPLICATION_SEND_RATE_PROPERTY_SMOKE_PASSED")
}
