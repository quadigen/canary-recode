package sandboxed

import vm "../engine/vm"
import runtime "base:runtime"
import "core:fmt"
import engine_runtime "../engine/runtime"
import renderer "../engine/renderer"

Runtime_Render_Context :: struct {
	environment: ^engine_runtime.Environment,
	vm_state:    ^vm.VM,
}

script_vm:  vm.VM
environment: engine_runtime.Environment
initialized: bool = false

init_runtime :: proc(renderer_object: ^renderer.RendererObject) {
	if initialized {
		return
	}

	script_vm = vm.New()

	engine_runtime.Environment_Init(
		&environment,
		&script_vm,
		renderer_object,
	)

	// 64bit vectors :money:
	vm.SetVectorPrecision(&script_vm, true)

	vm.AddStruct(
		&script_vm,
		"Engine",

		vm.Field("Name", "Kinemium"),
		vm.Field("Version", "1.0"),
		vm.Field("Debug", false),
	)

	initialized = true
}

run_code :: proc(source: string, name: string) {
	success, error := vm.RunWithSecurityCapabilities(
		&script_vm,
		source,
		vm.THREAD_SECURITY_ALL,
		name,
	)

	if !success {
		fmt.eprintf(
			"Luau startup failed in %s: %s\n",
			name,
			error,
		)
		delete(error)
	}
}

run_dir :: proc(
	loaded: []runtime.Load_Directory_File,
	renderer_object: ^renderer.RendererObject,
) {
	if !initialized {
		init_runtime(renderer_object)
	}

	for file in loaded {
		run_code(string(file.data), file.name)
	}
}

init :: proc(renderer: ^renderer.RendererObject) {
    run_dir(#load_directory("./internal"), renderer)
}

shutdown :: proc() {
	if !initialized {
		return
	}

	engine_runtime.Environment_Destroy(&environment)

	initialized = false
}