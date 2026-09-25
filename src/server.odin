#+build !js
package main

import sandbox "./sandboxed"
import "core:fmt"
import "core:time"
import engine_runtime "engine/runtime"
import services "engine/services"
import vm "engine/vm"
import classes "engine/classes"

run_server :: proc(options: Startup_Options) {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	sandbox.init_runtime(&script_vm, &environment, nil)
	defer sandbox.shutdown()
	defer vm.Close(&script_vm)
	if !load_game_map(&environment, &script_vm, options) {return}

	server_script_service := cast(^services.ServerScriptService)(
		services.Ensure_Service(&environment.services, "ServerScriptService")
	)

	datamodel := environment.services.data_model

	fmt.println("Running scripts")
	services.ServerScriptService_RunScripts(
		environment.renderer,
		datamodel,
		server_script_service,
	)
	fmt.println("Finished running scripts")

	object := services.Ensure_Service(&environment.services, "ReplicatorService")
	if object == nil ||
	   !services.replication_start(
			   cast(^services.ReplicatorService)object,
			   options.address,
			   options.port,
			   .Server,
		   ) {
		fmt.eprintf("Could not start the server on %s:%d\n", options.address, options.port)
		return
	}
	fmt.printf("Kinemium server listening on %s:%d\n", options.address, options.port)
	previous := time.now()
	for {
		now := time.now()
		delta_time := f32(time.diff(previous, now)) / f32(time.Second)
		previous = now
		engine_runtime.Environment_Update_Step(&environment, &script_vm, min(delta_time, 0.1))
		time.sleep(16 * time.Millisecond)
	}
}
