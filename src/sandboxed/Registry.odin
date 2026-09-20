package sandboxed

import runtime "base:runtime"
import "core:fmt"
import "core:strings"
import engine_runtime "../engine/runtime"
import renderer "../engine/renderer"
import vm "../engine/vm"
import target "../engine/target"

script_vm:   ^vm.VM
environment: ^engine_runtime.Environment
initialized: bool = false

init_runtime :: proc(
	vm_state: ^vm.VM,
	environment_state: ^engine_runtime.Environment,
	renderer_object: ^renderer.RendererObject,
) {
	if initialized {
		return
	}
	assert(vm_state != nil && vm_state.L != nil)
	assert(environment_state != nil)

	script_vm = vm_state
	environment = environment_state

	vm.SetVectorPrecision(script_vm, true)

	engine_runtime.Environment_Init(
		environment,
		script_vm,
		renderer_object,
	)

	vm.AddStruct(
		script_vm,
		"Engine",
		vm.Field("Name", "Kinemium"),
		vm.Field("Version", "1.0"),
		vm.Field("Debug", false),
		vm.Field("Target", target.NAME),
	)

	initialized = true
}

run_code :: proc(source: string, name: string) {
	assert(initialized && script_vm != nil)
	success, error := vm.RunInternal(
		script_vm,
		source,
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

run_dir :: proc(loaded: []runtime.Load_Directory_File) {
	assert(initialized)

	for file in loaded {
		if file.name == "editor_ui.luau" {
			run_internal_module(file.name)
			break
		}
	}
	for file in loaded {
		if file.name == "editor_ui.luau" { continue }
		run_internal_module(file.name)
	}
}

run_internal_module :: proc(file_name: string) {
	if !strings.has_suffix(file_name, ".luau") {
		return
	}
	module_name := file_name[:len(file_name)-len(".luau")]
	source := strings.concatenate({
		"require(\"@internal/",
		module_name,
		"\")",
	})
	run_code(source, file_name)
}

init :: proc(
	vm_state: ^vm.VM,
	environment_state: ^engine_runtime.Environment,
	renderer_object: ^renderer.RendererObject,
) {
	init_runtime(vm_state, environment_state, renderer_object)
	when target.IS_EDITOR {init_scripts()}
}

init_scripts :: proc() {
	run_dir(#load_directory("./internal"))
}

shutdown :: proc() {
	if !initialized {
		return
	}

	engine_runtime.Environment_Destroy(environment)
	script_vm = nil
	environment = nil
	initialized = false
}
