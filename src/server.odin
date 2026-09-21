#+build !js
package main

import sandbox "./sandboxed"
import "core:fmt"
import "core:time"
import engine_runtime "engine/runtime"
import services "engine/services"
import vm "engine/vm"

run_server :: proc() {
	options, ok := startup_options("0.0.0.0")
	if !ok {return}
	script_vm := vm.New()
	environment: engine_runtime.Environment
	sandbox.init_runtime(&script_vm, &environment, nil)
	defer sandbox.shutdown()
	defer vm.Close(&script_vm)
	if options.map_path != "" && !engine_runtime.Load_Map(&environment, &script_vm, options.map_path) {return}
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
		delta_time := f32(time.diff(now, previous)) / f32(time.Second)
		previous = now
		engine_runtime.Environment_Update_Step(&environment, &script_vm, min(delta_time, 0.1))
		time.sleep(16 * time.Millisecond)
	}
}
