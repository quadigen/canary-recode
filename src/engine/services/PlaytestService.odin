#+build !js
package services

// wire:service global="PlaytestService"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:os"
import "core:strings"

PlaytestService_Class := classes.Class_Info {
	name   = "PlaytestService",
	parent = &Service_Class,
}

PlaytestService :: struct {
	using service:  Service,
	process:        os.Process,
	running:        bool,
	last_exit_code: int,
	last_error:     string,
	map_path:       string,
}

playtest_set_error :: proc(service: ^PlaytestService, value: string) {
	delete(service.last_error)
	service.last_error = strings.clone(value)
}

playtest_refresh :: proc(service: ^PlaytestService) {
	if service == nil || !service.running {return}
	state, err := os.process_wait(service.process, timeout = 0)
	if err == nil && state.exited {
		service.running = false
		service.last_exit_code = state.exit_code
	}
}

playtest_stop :: proc(service: ^PlaytestService) -> bool {
	playtest_refresh(service)
	if service == nil || !service.running {return false}
	if kill_err := os.process_kill(service.process); kill_err != nil {
		playtest_set_error(service, os.error_string(kill_err))
		return false
	}
	state, wait_err := os.process_wait(service.process)
	service.running = false
	if wait_err != nil {
		playtest_set_error(service, os.error_string(wait_err))
		return false
	}
	service.last_exit_code = state.exit_code
	return true
}

playtest_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(PlaytestService)
	service.service = Service_Init(&PlaytestService_Class, "PlaytestService", data_model)
	return &service.object
}

playtest_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^PlaytestService)object
	_ = playtest_stop(service)
	delete(service.last_error)
	delete(service.map_path)
	classes.Object_Destroy(object)
	free(service)
}

playtest_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^PlaytestService)object
	playtest_refresh(service)
	switch key {
	case "IsRunning":
		vm.PushBoolean(L, service.running)
	case "ProcessId":
		vm.PushNumber(L, service.running ? f64(service.process.pid) : 0)
	case "LastExitCode":
		vm.PushNumber(L, f64(service.last_exit_code))
	case "LastError":
		vm.PushString(L, service.last_error)
	case "MapPath":
		vm.PushString(L, service.map_path)
	case "Start", "Stop":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}

playtest_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^PlaytestService)object
	switch method {
	case "Start":
		path := vm.ArgString(L, 2)
		if path == "" ||
		   (!strings.has_suffix(path, ".kine") && !strings.has_suffix(path, ".KINE")) {
			return vm.RaiseError(L, "PlaytestService:Start expects a .kine file path"), true
		}
		if !os.exists(
			path,
		) {return vm.RaiseError(L, "PlaytestService:Start could not find the .kine file"), true}
		playtest_refresh(service)
		if service.running {_ = playtest_stop(service)}
		executable, path_err := os.get_executable_path(context.temp_allocator)
		if path_err != nil {
			playtest_set_error(service, os.error_string(path_err))
			vm.PushBoolean(L, false)
			return 1, true
		}
		command := []string{executable, path}
		process, start_err := os.process_start(
			os.Process_Desc {
				command = command,
				stdin = os.stdin,
				stdout = os.stdout,
				stderr = os.stderr,
			},
		)
		if start_err != nil {
			playtest_set_error(service, os.error_string(start_err))
			vm.PushBoolean(L, false)
			return 1, true
		}
		service.process = process
		service.running = true
		service.last_exit_code = 0
		playtest_set_error(service, "")
		delete(service.map_path)
		service.map_path = strings.clone(path)
		vm.PushBoolean(L, true)
		return 1, true
	case "Stop":
		vm.PushBoolean(L, playtest_stop(service))
		return 1, true
	}
	return 0, false
}

Register_PlaytestService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&PlaytestService_Class,
		playtest_construct,
		playtest_destroy,
		creatable = false,
		get = playtest_get,
		namecall = playtest_namecall,
	)
}
