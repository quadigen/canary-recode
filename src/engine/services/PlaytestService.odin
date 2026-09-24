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
	server_process: os.Process,
	client_process: os.Process,
	running:        bool,
	last_exit_code: int,
	last_error:     string,
	map_path:       string,
	temp_map_dir:   string,
}

PLAYTEST_ADDRESS :: "127.0.0.1"
PLAYTEST_PORT    :: "1234"

playtest_set_error :: proc(service: ^PlaytestService, value: string) {
	delete(service.last_error)
	service.last_error = strings.clone(value)
}

playtest_cleanup_temp_map :: proc(service: ^PlaytestService) {
	if service == nil || len(service.temp_map_dir) == 0 {return}
	if err := os.remove_all(service.temp_map_dir); err != nil {
		_ = err
	}
	delete(service.temp_map_dir)
	service.temp_map_dir = ""
}

playtest_refresh :: proc(service: ^PlaytestService) {
	if service == nil || !service.running {return}
	server_state, server_err := os.process_wait(service.server_process, timeout = 0)
	client_state, client_err := os.process_wait(service.client_process, timeout = 0)
	if (server_err == nil && server_state.exited) ||
	   (client_err == nil && client_state.exited) {
		service.last_exit_code =
			client_err == nil && client_state.exited ? client_state.exit_code : server_state.exit_code
		if server_err != nil || !server_state.exited {
			_ = os.process_kill(service.server_process)
			_, _ = os.process_wait(service.server_process)
		}
		if client_err != nil || !client_state.exited {
			_ = os.process_kill(service.client_process)
			_, _ = os.process_wait(service.client_process)
		}
		service.server_process = {}
		service.client_process = {}
		service.running = false
		playtest_cleanup_temp_map(service)
	}
}

playtest_stop :: proc(service: ^PlaytestService) -> bool {
	playtest_refresh(service)
	if service == nil || !service.running {return false}
	server_kill_err := os.process_kill(service.server_process)
	client_kill_err := os.process_kill(service.client_process)
	server_state, server_wait_err := os.process_wait(service.server_process)
	client_state, client_wait_err := os.process_wait(service.client_process)
	service.running = false
	service.server_process = {}
	service.client_process = {}
	if server_kill_err != nil || client_kill_err != nil ||
	   server_wait_err != nil || client_wait_err != nil {
		playtest_set_error(service, "failed to stop the playtest server and client")
		return false
	}
	service.last_exit_code = client_state.exit_code != 0 ? client_state.exit_code : server_state.exit_code
	playtest_cleanup_temp_map(service)
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
	playtest_cleanup_temp_map(service)
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
		vm.PushNumber(L, service.running ? f64(service.client_process.pid) : 0)
	case "ServerProcessId":
		vm.PushNumber(L, service.running ? f64(service.server_process.pid) : 0)
	case "ClientProcessId":
		vm.PushNumber(L, service.running ? f64(service.client_process.pid) : 0)
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
		path := ""
		if vm.StackTop(L) >= 2 && !vm.IsNoneOrNil(L, 2) {
			path = vm.ArgString(L, 2)
		}
		if path != "" &&
		   (!strings.has_suffix(path, ".kine") && !strings.has_suffix(path, ".KINE")) {
			return vm.RaiseError(L, "PlaytestService:Start expects a .kine file path"), true
		}
		if path != "" && !os.exists(path) {
			return vm.RaiseError(L, "PlaytestService:Start could not find the .kine file"), true
		}

		playtest_refresh(service)
		if service.running {_ = playtest_stop(service)}

		map_owned := false
		if path == "" {
			export_service := cast(^ExportService)Service_Get_Service(&service.service, "ExportService")
			if export_service == nil {
				return vm.RaiseError(L, "PlaytestService:Start could not access ExportService"), true
			}
			temp_dir, temp_err := os.make_directory_temp("", "kinemium-playtest-*", context.allocator)
			if temp_err != nil {
				playtest_set_error(service, os.error_string(temp_err))
				vm.PushBoolean(L, false)
				return 1, true
			}
			file_path, join_err := os.join_path({temp_dir, "map.kine"}, context.allocator)
			if join_err != nil {
				_ = os.remove_all(temp_dir)
				delete(temp_dir)
				playtest_set_error(service, os.error_string(join_err))
				vm.PushBoolean(L, false)
				return 1, true
			}
			if !export_datamodel_to_file(export_service, L, file_path) {
				_ = os.remove_all(temp_dir)
				delete(temp_dir)
				delete(file_path)
				playtest_set_error(service, "failed to export the DataModel to a .kine file")
				vm.PushBoolean(L, false)
				return 1, true
			}
			playtest_cleanup_temp_map(service)
			service.temp_map_dir = strings.clone(temp_dir)
			delete(temp_dir)
			path = file_path
			map_owned = true
		}

		executable, executable_err := os.get_executable_path(context.temp_allocator)

		if executable_err != nil {
			if map_owned {
				delete(path)
				playtest_cleanup_temp_map(service)
			}
			playtest_set_error(service, os.error_string(executable_err))
			vm.PushBoolean(L, false)
			return 1, true
		}

		server_command := []string{
			executable,
			"--server",
			"--window",
			"--map",
			path,
			"--address",
			PLAYTEST_ADDRESS,
			"--port",
			PLAYTEST_PORT,
		}
		server_process, server_start_err := os.process_start(
			os.Process_Desc {
				command = server_command,
				stdin = os.stdin,
				stdout = os.stdout,
				stderr = os.stderr,
			},
		)
		if server_start_err != nil {
			if map_owned {
				delete(path)
				playtest_cleanup_temp_map(service)
			}
			playtest_set_error(service, os.error_string(server_start_err))
			vm.PushBoolean(L, false)
			return 1, true
		}
		client_command := []string{
			executable,
			"--client",
			"--address",
			PLAYTEST_ADDRESS,
			"--port",
			PLAYTEST_PORT,
		}
		client_process, client_start_err := os.process_start(
			os.Process_Desc {
				command = client_command,
				stdin = os.stdin,
				stdout = os.stdout,
				stderr = os.stderr,
			},
		)
		if client_start_err != nil {
			_ = os.process_kill(server_process)
			_, _ = os.process_wait(server_process)
			if map_owned {
				delete(path)
				playtest_cleanup_temp_map(service)
			}
			playtest_set_error(service, os.error_string(client_start_err))
			vm.PushBoolean(L, false)
			return 1, true
		}
		delete(service.map_path)
		service.map_path = strings.clone(path)
		if map_owned {delete(path)}
		service.server_process = server_process
		service.client_process = client_process
		service.running = true
		service.last_exit_code = 0
		playtest_set_error(service, "")
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
