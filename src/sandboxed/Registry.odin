package sandboxed

import packages "../engine/packages"
import renderer "../engine/renderer"
import engine_runtime "../engine/runtime"
import services "../engine/services"
import target "../engine/target"
import vm "../engine/vm"
import "core:fmt"
import "core:strings"

script_vm: ^vm.VM
environment: ^engine_runtime.Environment
initialized: bool = false


CONFIG_LUAU_STARTUP :: #config(LUAU_STARTUP, "")
CONFIG_NOEDITOR :: #config(NOEDITOR, false)
HAS_LUAU_STARTUP :: CONFIG_LUAU_STARTUP != ""

when HAS_LUAU_STARTUP {
	LUAU_STARTUP_FILES := #load_directory(CONFIG_LUAU_STARTUP)
}


CONFIG_EDITOR_MODULES :: #config(EDITOR_MODULES, "")
CONFIG_EDITOR_COMPONENTS :: #config(EDITOR_COMPONENTS, "")
HAS_EDITOR_MODULES :: CONFIG_EDITOR_MODULES != ""
HAS_EDITOR_COMPONENTS :: CONFIG_EDITOR_COMPONENTS != ""

when HAS_EDITOR_MODULES {
	EDITOR_MODULE_FILES := #load_directory(CONFIG_EDITOR_MODULES)
}

when HAS_EDITOR_COMPONENTS {
	EDITOR_COMPONENT_FILES := #load_directory(CONFIG_EDITOR_COMPONENTS)
}

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

	engine_runtime.Environment_Init(environment, script_vm, renderer_object)

	vm.AddStruct(
		script_vm,
		"Engine",
		vm.Field("Name", "Kinemium"),
		vm.Field("Version", "1.0"),
		vm.Field("Debug", false),
		vm.Field("Target", target.name()),
	)

	when HAS_LUAU_STARTUP {
		vm.AddGlobal_Boolean(script_vm, "IsCustomStartup", true)
	}

	initialized = true
	run_custom_startup()
}

run_code :: proc(source: string, name: string) {
	assert(initialized && script_vm != nil)
	success, error := vm.RunInternal(script_vm, source, name)

	if !success {
		fmt.eprintf("Luau startup failed in %s: %s\n", name, error)
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
		if module.name == "editor_ui" {continue}
		run_internal_module(module.name)
	}
}

run_internal_module :: proc(module_name: string) {
	source := strings.concatenate({"require(\"@internal/", module_name, "\")"})
	run_code(source, module_name)
}

run_startup_module :: proc(module_name: string) {
	source := strings.concatenate({"require(\"@startup/", module_name, "\")"})
	run_code(source, module_name)
}


run_custom_startup :: proc() -> int {
	when !HAS_LUAU_STARTUP {
		return 0
	} else {
		loaded := 0
		for file in LUAU_STARTUP_FILES {
			if !strings.has_suffix(file.name, ".luau") {
				continue
			}
			name := file.name[:len(file.name) - len(".luau")]
			packages.Register_Startup_Module(&environment.packages, name, string(file.data))
			loaded += 1
		}
		if loaded == 0 {
			fmt.eprintln("[CustomStartup] LUAU_STARTUP directory has no .luau modules")
			return 0
		}
		fmt.eprintf("[CustomStartup] running %d module(s) from LUAU_STARTUP\n", loaded)
		for module in environment.packages.startup_modules {
			run_startup_module(module.name)
		}
		return loaded
	}
}


register_embedded_editor_modules :: proc() {
	when HAS_EDITOR_MODULES {
		if len(environment.packages.internal_modules) > 0 {
			return
		}
		loaded := 0
		for file in EDITOR_MODULE_FILES {
			if !strings.has_suffix(file.name, ".luau") {
				continue
			}
			name := file.name[:len(file.name) - len(".luau")]
			packages.Register_Internal_Module(&environment.packages, name, string(file.data))
			loaded += 1
		}
		when HAS_EDITOR_COMPONENTS {
			for file in EDITOR_COMPONENT_FILES {
				if !strings.has_suffix(file.name, ".luau") {
					continue
				}
				name := strings.concatenate(
					{"Components/", file.name[:len(file.name) - len(".luau")]},
					context.temp_allocator,
				)
				packages.Register_Internal_Module(&environment.packages, name, string(file.data))
				loaded += 1
			}
		}
		fmt.eprintf("[EditorStartup] embedded %d editor modules\n", loaded)
	}
}

editor_available :: proc() -> bool {
	when CONFIG_NOEDITOR {
		return false
	}

	if ODIN_OS == .JS {


		return target.is_editor()
	}

	if target.is_editor() {
		return true
	}


	return target.is_playtest()
}

init :: proc(
	vm_state: ^vm.VM,
	environment_state: ^engine_runtime.Environment,
	renderer_object: ^renderer.RendererObject,
) {
	init_runtime(vm_state, environment_state, renderer_object)

	when HAS_EDITOR_MODULES {
		if editor_available() {
			init_scripts()
			return
		}
	}

	when ODIN_OS != .JS {
		if editor_available() {
			editor_object := services.Ensure_Service(&environment.services, "EditorService")
			if editor_object == nil {
				fmt.eprintln(
					"[EditorStartup] EditorService is unavailable; editor UI cannot start",
				)
			} else {
				fetch := services.EditorService_Get_Editor(
					cast(^services.EditorService)editor_object,
					check_remote = !target.is_playtest(),
				)
				if fetch.warning != "" {
					fmt.eprintf("[EditorStartup] %s\n", fetch.warning)
				}
				if fetch.error_message != "" {
					fmt.eprintf(
						"[EditorStartup] %s; editor UI cannot start\n",
						fetch.error_message,
					)
				} else {
					if packages.Load_Internal_Modules_From_Blob(
						&environment.packages,
						fetch.path,
					) {
						if fetch.downloaded {
							fmt.printf(
								"[EditorStartup] downloaded editor update to %s\n",
								fetch.path,
							)
						} else {
							fmt.printf(
								"[EditorStartup] loaded cached editor from %s\n",
								fetch.path,
							)
						}
					} else {
						fmt.eprintf(
							"[EditorStartup] editor archive at %s could not be loaded; editor UI cannot start\n",
							fetch.path,
						)
					}
					delete(fetch.path)
				}
			}
			init_scripts()
		}
	}

	if target.is_editor() && ODIN_OS == .JS {
		fmt.eprintln(
			"[EditorStartup] remote editor archives are unavailable on Web; starting embedded modules",
		)
		init_scripts()
	}
}

init_scripts :: proc() {
	register_embedded_editor_modules()
	fmt.eprintf(
		"[EditorStartup] starting %d internal editor modules\n",
		len(environment.packages.internal_modules),
	)
	run_modules(environment.packages.internal_modules[:])

	when ODIN_OS != .JS {
		if packages_object := services.Ensure_Service(&environment.services, "Packages");
		   packages_object != nil {
			services.Packages_Run_Downloaded_Plugins(cast(^services.Packages)packages_object)
		}
	}
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
