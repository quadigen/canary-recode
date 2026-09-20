package main

import "core:fmt"
import engine_runtime "../src/engine/runtime"
import sandbox "../src/sandboxed"
import target "../src/engine/target"
import vm "../src/engine/vm"

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	sandbox.init_runtime(&script_vm, &environment, nil)
	ok, err := vm.Run(&script_vm, `
assert(BuildTarget == Engine.Target)
assert(IsEditor == (BuildTarget == "editor"))
assert(IsClient == (BuildTarget == "client"))
assert(IsServer == (BuildTarget == "server"))
`, "build_target_smoke")
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("build target globals failed")
	}
	vm.Close(&script_vm)
	sandbox.shutdown()
	fmt.println("BUILD_TARGET_SMOKE_PASSED ", target.NAME)
}
