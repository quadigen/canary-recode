package main

import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"
import "core:fmt"
import "core:os"

main :: proc() {
	path := "autosave.kine"
	if len(os.args) > 1 {path = os.args[1]}
	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		fmt.eprintln("read failed:", read_err)
		os.exit(1)
	}
	defer delete(data)
	fmt.printf("read %d bytes from %s\n", len(data), path)

	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)
	fmt.println("environment initialized")

	ok := services.Restore_Map(
		&environment.services,
		script_vm.L,
		data,
		path,
		clear_assets = false,
	)
	fmt.println("restore ok =", ok)
	if !ok {os.exit(2)}
}
