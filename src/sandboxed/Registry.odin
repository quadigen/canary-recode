package sandboxed

import "core:fmt"
import "core:strings"
import engine_runtime "../engine/runtime"
import packages "../engine/packages"
import renderer "../engine/renderer"
import services "../engine/services"
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

run_modules :: proc(loaded: []packages.Internal_Module) {
	assert(initialized)

	for module in loaded {
		if module.name == "editor_ui" {
			run_internal_module(module.name)
			break
		}
	}
	for module in loaded {
		if module.name == "editor_ui" { continue }
		run_internal_module(module.name)
	}
}

run_internal_module :: proc(module_name: string) {
	source := strings.concatenate({
		"require(\"@internal/",
		module_name,
		"\")",
	})
	run_code(source, module_name)
}

init :: proc(
	vm_state: ^vm.VM,
	environment_state: ^engine_runtime.Environment,
	renderer_object: ^renderer.RendererObject,
) {
	init_runtime(vm_state, environment_state, renderer_object)
	when target.IS_EDITOR && ODIN_OS != .JS {
		editor_object := services.Ensure_Service(
			&environment.services,
			"EditorService",
		)
		if editor_object == nil {
			fmt.eprintln("[EditorStartup] EditorService is unavailable; editor UI cannot start")
		} else {
			fetch := services.EditorService_Get_Editor(
				cast(^services.EditorService)editor_object,
			)
			if fetch.warning != "" {
				fmt.eprintf("[EditorStartup] %s\n", fetch.warning)
			}
			if fetch.error_message != "" {
				fmt.eprintf("[EditorStartup] %s; editor UI cannot start\n", fetch.error_message)
			} else {
				if packages.Load_Internal_Modules_From_Blob(
					&environment.packages,
					fetch.path,
				) {
					if fetch.downloaded {
						fmt.printf("[EditorStartup] downloaded editor update to %s\n", fetch.path)
					} else {
						fmt.printf("[EditorStartup] loaded cached editor from %s\n", fetch.path)
					}
				} else {
					fmt.eprintf("[EditorStartup] editor archive at %s could not be loaded; editor UI cannot start\n", fetch.path)
				}
				delete(fetch.path)
			}
		}
		init_scripts()
	}
	when target.IS_EDITOR && ODIN_OS == .JS {
		fmt.eprintln("[EditorStartup] remote editor archives are unavailable on Web; starting embedded modules")
		init_scripts()
	}
}

init_scripts :: proc() {
	fmt.eprintf("[EditorStartup] starting %d internal editor modules\n", len(environment.packages.internal_modules))
	run_modules(environment.packages.internal_modules[:])
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
