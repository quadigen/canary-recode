#+build !js
// wire:service
package services

import tracy "../util/odin-tracy"


import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import serializer "../serializer"
import vm "../vm"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

PlaytestService_Class := classes.Class_Info {
	name   = "PlaytestService",
	parent = &Service_Class,
}

Playtest_Output :: struct {
	read:    ^os.File,
	pending: [dynamic]u8,
	warnings: map[string]Playtest_Warning,
}

Playtest_Warning :: struct {
	last_emitted: time.Tick,
	suppressed: int,
}

PlaytestService :: struct {
	using service:   Service,
	server_process:  os.Process,
	client_process:  os.Process,
	server_output:   Playtest_Output,
	client_output:   Playtest_Output,
	forwarding_output: bool,
	running:         bool,
	singleplayer:    bool,
	android_session: bool,
	last_exit_code:  int,
	last_error:      string,
	map_path:        string,
	temp_map_dir:    string,
}

PLAYTEST_ADDRESS :: "127.0.0.1"
PLAYTEST_PORT :: u16(1234)
PLAYTEST_STDERR_CHUNK :: 4096
PLAYTEST_WARNING_INTERVAL :: 5 * time.Second
PLAYTEST_WARNING_LIMIT :: 128

playtest_process_active :: proc(process: os.Process) -> bool {
	return process.pid != 0
}

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

playtest_close_output :: proc(output: ^Playtest_Output) {
	if output == nil {return}
	if output.read != nil {
		_ = os.close(output.read)
		output.read = nil
	}
	if output.pending != nil {
		delete(output.pending)
		output.pending = nil
	}
	for message in output.warnings {delete(message)}
	delete(output.warnings)
	output.warnings = nil
}

playtest_log_line :: proc(service: ^PlaytestService, source, message, kind: string) {
	if service == nil || service.service.data_model == nil {return}
	registry := service.service.data_model.registry
	if registry == nil {return}
	descriptor := Find_Service(registry, "LogService")
	if descriptor == nil || descriptor.object == nil {return}
	log_service := cast(^LogService)descriptor.object
	full_message := strings.concatenate({"[Playtest ", source, "] ", message})
	defer delete(full_message)
	log_service_write(log_service, full_message, kind)
}

playtest_after_tag :: proc(line, tag: string) -> string {
	message := line[len(tag):]


	if len(message) > 0 && message[0] == ' ' {
		message = message[1:]
	}
	return message
}

playtest_forward_warning :: proc(service: ^PlaytestService, source: string, output: ^Playtest_Output, message: string) {
	now := time.tick_now()
	if warning, seen := output.warnings[message]; seen {
		if time.tick_diff(warning.last_emitted, now) < PLAYTEST_WARNING_INTERVAL {
			warning.suppressed += 1
			output.warnings[message] = warning
			return
		}
		output.warnings[message] = {last_emitted = now}
		if warning.suppressed > 0 {
			message := fmt.tprintf("%s (%d repeats suppressed)", message, warning.suppressed)
			playtest_log_line(service, source, message, "Warn")
			return
		}
	} else if len(message) <= PLAYTEST_STDERR_CHUNK {
		if len(output.warnings) == PLAYTEST_WARNING_LIMIT {
			for tracked, warning in output.warnings {
				if time.tick_diff(warning.last_emitted, now) < PLAYTEST_WARNING_INTERVAL {continue}
				delete_key(&output.warnings, tracked)
				delete(tracked)
				break
			}
		}
		if len(output.warnings) < PLAYTEST_WARNING_LIMIT {
			output.warnings[strings.clone(message)] = {last_emitted = now}
		}
	}
	playtest_log_line(service, source, message, "Warn")
}

playtest_forward_line :: proc(service: ^PlaytestService, source: string, output: ^Playtest_Output, raw_line: string) {
	line := strings.trim_space(raw_line)
	if line == "" {return}

	kind := ""
	message := line

	switch {
	case strings.has_prefix(line, "[ERROR]"):
		message = playtest_after_tag(line, "[ERROR]")
		kind = "Error"
	case strings.has_prefix(line, "[WARN]"):
		playtest_forward_warning(service, source, output, playtest_after_tag(line, "[WARN]"))
		return
	case strings.has_prefix(line, "[INFO]"):
		message = playtest_after_tag(line, "[INFO]")
		kind = "Info"
	case strings.has_prefix(line, "[LOG]"):
		message = playtest_after_tag(line, "[LOG]")
		kind = "Log"
	case:
		return
	}

	playtest_log_line(service, source, message, kind)
}


playtest_pump_output :: proc(service: ^PlaytestService, source: string, output: ^Playtest_Output) {
	if service == nil || output == nil || output.read == nil {return}

	for {
		has_data, has_error := os.pipe_has_data(output.read)
		if has_error != nil || !has_data {break}

		chunk: [PLAYTEST_STDERR_CHUNK]u8
		count, read_error := os.read(output.read, chunk[:])
		if read_error != nil || count <= 0 {break}
		append(&output.pending, ..chunk[:count])
	}

	line_start := 0
	for index in 0 ..< len(output.pending) {
		if output.pending[index] != '\n' {continue}
		playtest_forward_line(service, source, output, string(output.pending[line_start:index]))
		line_start = index + 1
	}

	if line_start > 0 {
		remove_range(&output.pending, 0, line_start)
	}
}

playtest_pump_outputs :: proc(service: ^PlaytestService) {
	if service == nil || service.forwarding_output || vm.Is_Closing() {return}
	// LogService listeners run synchronously and may query or control the playtest.
	service.forwarding_output = true
	defer service.forwarding_output = false
	playtest_pump_output(service, "server", &service.server_output)
	playtest_pump_output(service, "client", &service.client_output)
}


Playtest_Reap :: struct {
	exit_code: int,
	ok:        bool,
}

playtest_reap :: proc(process: os.Process) -> Playtest_Reap {
	result: Playtest_Reap
	if !playtest_process_active(process) {
		result.ok = true
		return result
	}
	kill_err := os.process_kill(process)
	state, wait_err := os.process_wait(process)
	result.exit_code = state.exit_code
	result.ok = kill_err == nil && wait_err == nil
	return result
}

playtest_refresh :: proc(service: ^PlaytestService) {
	if service == nil || !service.running || service.forwarding_output {return}

	playtest_pump_outputs(service)

	server_started := playtest_process_active(service.server_process)
	client_started := playtest_process_active(service.client_process)
	server_alive := false
	client_alive := false
	server_exit := 0
	client_exit := 0

	if server_started {
		server_state, server_err := os.process_wait(service.server_process, timeout = 0)
		server_alive = server_err != nil || !server_state.exited
		if server_err == nil && server_state.exited {
			server_exit = server_state.exit_code
		}
	}
	if client_started {
		client_state, client_err := os.process_wait(service.client_process, timeout = 0)
		client_alive = client_err != nil || !client_state.exited
		if client_err == nil && client_state.exited {
			client_exit = client_state.exit_code
		}
	}

	if (server_alive || !server_started) && (client_alive || !client_started) {
		return
	}

	if playtest_process_active(service.server_process) && server_alive {
		_ = playtest_reap(service.server_process)
	}
	if playtest_process_active(service.client_process) && client_alive {
		_ = playtest_reap(service.client_process)
	}

	playtest_pump_outputs(service)

	service.last_exit_code = client_exit != 0 ? client_exit : server_exit
	if service.last_exit_code != 0 {
		source := "client" if client_exit != 0 else "server"
		playtest_set_error(service, fmt.tprintf("Playtest %s exited with status %d", source, service.last_exit_code))
	}
	service.server_process = {}
	service.client_process = {}
	playtest_close_output(&service.server_output)
	playtest_close_output(&service.client_output)
	service.running = false
	service.singleplayer = false
	playtest_cleanup_temp_map(service)
}

playtest_stop :: proc(service: ^PlaytestService) -> bool {
	if service == nil || service.forwarding_output {return false}
	playtest_refresh(service)
	if !service.running {return false}


	when #config(KINE_ANDROID, false) {
		if service.android_session {
			stopped := android_playtest_stop()
			service.running = false
			service.android_session = false
			service.singleplayer = false
			service.server_process = {}
			service.client_process = {}
			if !stopped {
				playtest_set_error(service, "failed to close the Android playtest window")
				return false
			}
			playtest_cleanup_temp_map(service)
			return true
		}
	}

	server_ok := true
	client_ok := true
	server_exit := 0
	client_exit := 0

	if playtest_process_active(service.server_process) {
		server_reap := playtest_reap(service.server_process)
		server_ok = server_reap.ok
		server_exit = server_reap.exit_code
	}
	if playtest_process_active(service.client_process) {
		client_reap := playtest_reap(service.client_process)
		client_ok = client_reap.ok
		client_exit = client_reap.exit_code
	}

	playtest_pump_outputs(service)

	service.running = false
	service.singleplayer = false
	service.server_process = {}
	service.client_process = {}
	playtest_close_output(&service.server_output)
	playtest_close_output(&service.client_output)
	if !server_ok || !client_ok {
		playtest_set_error(service, "failed to stop the playtest processes")
		return false
	}
	service.last_exit_code = client_exit != 0 ? client_exit : server_exit
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
	playtest_close_output(&service.server_output)
	playtest_close_output(&service.client_output)
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
	case "IsSingleplayer":
		vm.PushBoolean(L, service.singleplayer)
	case "ProcessId":
		vm.PushNumber(L, service.running ? f64(service.client_process.pid) : 0)
	case "ServerProcessId":
		server_pid := 0.0
		if service.running && playtest_process_active(service.server_process) {
			server_pid = f64(service.server_process.pid)
		}
		vm.PushNumber(L, server_pid)
	case "ClientProcessId":
		vm.PushNumber(L, service.running ? f64(service.client_process.pid) : 0)
	case "LastExitCode":
		vm.PushNumber(L, f64(service.last_exit_code))
	case "LastError":
		vm.PushString(L, service.last_error)
	case "MapPath":
		vm.PushString(L, service.map_path)
	case "Start", "StartServer", "StartClient", "StartSinglePlayer", "Stop":
		vm.PushUserdataMethod(L, key)
	case:
		return false
	}
	return true
}


Playtest_Session_Mode :: enum {
	Pair,
	Server_Only,
	Client_Only,
	Singleplayer,
}


Playtest_Launch :: struct {
	mode:     Playtest_Session_Mode,
	map_path: string,
	address:  string,
	port:     u16,
	headless: bool,
}

playtest_default_launch :: proc(mode: Playtest_Session_Mode) -> Playtest_Launch {
	return Playtest_Launch {
		mode = mode,
		address = PLAYTEST_ADDRESS,
		port = PLAYTEST_PORT,
		headless = mode == .Server_Only,
	}
}


playtest_owns_map :: proc(mode: Playtest_Session_Mode) -> bool {
	return mode != .Client_Only
}


playtest_check_map_path :: proc(L: ^vm.State, method, path: string) -> bool {
	if path == "" {return true}
	if !strings.has_suffix(path, ".kine") && !strings.has_suffix(path, ".KINE") {
		detail := strings.concatenate({"PlaytestService:", method, " expects a .kine file path"})
		defer delete(detail)
		_ = vm.RaiseError(L, detail)
		return false
	}
	if !os.exists(path) {
		detail := strings.concatenate(
			{"PlaytestService:", method, " could not find the .kine file"},
		)
		defer delete(detail)
		_ = vm.RaiseError(L, detail)
		return false
	}
	return true
}


playtest_abandon_map :: proc(service: ^PlaytestService, path: string, owned: bool) {
	if !owned {return}
	delete(path)
	playtest_cleanup_temp_map(service)
}


playtest_resolve_map :: proc(
	L: ^vm.State,
	service: ^PlaytestService,
	map_path: string,
) -> (
	path: string,
	owned: bool,
	ok: bool,
) {
	if map_path != "" {
		return map_path, false, true
	}
	tracy.ZoneNC("Playtest Map Export", 0xD19A66)

	export_service := cast(^ExportService)Service_Get_Service(&service.service, "ExportService")
	if export_service == nil {
		_ = vm.RaiseError(L, "PlaytestService could not access ExportService")
		return "", false, false
	}

	temp_dir, temp_err := os.make_directory_temp("", "kinemium-playtest-*", context.allocator)
	if temp_err != nil {
		playtest_set_error(service, os.error_string(temp_err))
		return "", false, false
	}

	file_path, join_err := os.join_path({temp_dir, "map.kine"}, context.allocator)
	if join_err != nil {
		_ = os.remove_all(temp_dir)
		delete(temp_dir)
		playtest_set_error(service, os.error_string(join_err))
		return "", false, false
	}

	export_err := export_datamodel_to_file(export_service, L, file_path)
	if !serializer.Error_Is_None(export_err) {


		export_detail := serializer.Error_String(export_err)
		defer delete(export_detail)
		_ = os.remove_all(temp_dir)
		delete(temp_dir)
		delete(file_path)
		playtest_set_error(service, export_detail)
		serializer.Error_Delete(&export_err)
		return "", false, false
	}
	serializer.Error_Delete(&export_err)


	playtest_cleanup_temp_map(service)
	service.temp_map_dir = strings.clone(temp_dir)
	delete(temp_dir)
	return file_path, true, true
}


playtest_spawn :: proc(
	command: []string,
) -> (
	process: os.Process,
	stderr_read: ^os.File,
	failure: string,
	failed: bool,
) {
	read_end, write_end, pipe_error := os.pipe()
	if pipe_error != nil {
		return {}, nil, os.error_string(pipe_error), true
	}

	started, start_error := os.process_start(
		os.Process_Desc {
			command = command,
			stdin = os.stdin,
			stdout = os.stdout,
			stderr = write_end,
		},
	)

	_ = os.close(write_end)

	if start_error != nil {
		_ = os.close(read_end)
		return {}, nil, os.error_string(start_error), true
	}
	return started, read_end, "", false
}


playtest_record :: proc(
	service: ^PlaytestService,
	server_process: os.Process,
	server_stderr: ^os.File,
	client_process: os.Process,
	client_stderr: ^os.File,
	map_path: string,
	mode: Playtest_Session_Mode,
) {
	delete(service.map_path)
	service.map_path = strings.clone(map_path)
	service.server_process = server_process
	service.client_process = client_process
	service.server_output.read = server_stderr
	service.client_output.read = client_stderr
	service.singleplayer = mode == .Singleplayer
	service.running = true
	service.last_exit_code = 0
	playtest_set_error(service, "")
}


playtest_launch :: proc(
	L: ^vm.State,
	service: ^PlaytestService,
	launch: Playtest_Launch,
) -> (
	i32,
	bool,
) {
	if service.forwarding_output {
		vm.PushBoolean(L, false)
		return 1, true
	}
	playtest_refresh(service)
	if service.running {_ = playtest_stop(service)}


	needs_map := playtest_owns_map(launch.mode)
	path := ""
	map_owned := false
	if needs_map {
		resolved, resolved_owned, resolved_ok := playtest_resolve_map(L, service, launch.map_path)
		if !resolved_ok {
			vm.PushBoolean(L, false)
			return 1, true
		}
		path = resolved
		map_owned = resolved_owned
	}


	when #config(KINE_ANDROID, false) {
		return playtest_launch_android(L, service, launch, path, map_owned)
	}

	executable, executable_err := os.get_executable_path(context.temp_allocator)
	if executable_err != nil {
		playtest_abandon_map(service, path, map_owned)
		playtest_set_error(service, os.error_string(executable_err))
		vm.PushBoolean(L, false)
		return 1, true
	}


	port := fmt.tprintf("%d", launch.port)

	switch launch.mode {
	case .Singleplayer:
		process, stderr_pipe, failure, failed := playtest_spawn(
			[]string {
				executable,
				"--singleplayer",
				"--playtest-host",
				"--map",
				path,
				"--username",
				"SinglePlayer",
			},
		)
		if failed {
			playtest_abandon_map(service, path, map_owned)
			playtest_set_error(service, failure)
			vm.PushBoolean(L, false)
			return 1, true
		}
		playtest_record(service, {}, nil, process, stderr_pipe, path, .Singleplayer)

	case .Server_Only:
		command: []string
		if launch.headless {
			command = []string {
				executable,
				"--server",
				"--playtest-host",
				"--map",
				path,
				"--address",
				launch.address,
				"--port",
				port,
			}
		} else {
			command = []string {
				executable,
				"--server",
				"--window",
				"--playtest-host",
				"--map",
				path,
				"--address",
				launch.address,
				"--port",
				port,
			}
		}
		process, stderr_pipe, failure, failed := playtest_spawn(command)
		if failed {
			playtest_abandon_map(service, path, map_owned)
			playtest_set_error(service, failure)
			vm.PushBoolean(L, false)
			return 1, true
		}
		playtest_record(service, process, stderr_pipe, {}, nil, path, .Server_Only)

	case .Client_Only:
		process, stderr_pipe, failure, failed := playtest_spawn(
			[]string {
				executable,
				"--client",
				"--playtest-host",
				"--address",
				launch.address,
				"--port",
				port,
			},
		)
		if failed {
			playtest_abandon_map(service, path, map_owned)
			playtest_set_error(service, failure)
			vm.PushBoolean(L, false)
			return 1, true
		}
		playtest_record(service, {}, nil, process, stderr_pipe, "", .Client_Only)

	case .Pair:
		server_command := []string {
			executable,
			"--server",
			"--window",
			"--playtest-host",
			"--map",
			path,
			"--address",
			launch.address,
			"--port",
			port,
		}
		server_process, server_stderr, server_failure, server_failed := playtest_spawn(
			server_command,
		)
		if server_failed {
			playtest_abandon_map(service, path, map_owned)
			playtest_set_error(service, server_failure)
			vm.PushBoolean(L, false)
			return 1, true
		}


		client_process, client_stderr, client_failure, client_failed := playtest_spawn(
			[]string {
				executable,
				"--client",
				"--playtest-host",
				"--address",
				launch.address,
				"--port",
				port,
			},
		)
		if client_failed {


			_ = playtest_reap(server_process)
			if server_stderr != nil {_ = os.close(server_stderr)}
			playtest_abandon_map(service, path, map_owned)
			playtest_set_error(service, client_failure)
			vm.PushBoolean(L, false)
			return 1, true
		}
		playtest_record(
			service,
			server_process,
			server_stderr,
			client_process,
			client_stderr,
			path,
			.Pair,
		)
	}

	if map_owned {delete(path)}
	vm.PushBoolean(L, true)
	return 1, true
}

when #config(KINE_ANDROID, false) {


	playtest_record_android :: proc(
		service: ^PlaytestService,
		map_path: string,
		mode: Playtest_Session_Mode,
	) {
		delete(service.map_path)
		service.map_path = strings.clone(map_path)
		service.server_process = {}
		service.client_process = {}
		service.singleplayer = mode == .Singleplayer || mode == .Pair
		service.android_session = true
		service.running = true
		service.last_exit_code = 0
		playtest_set_error(service, "")
	}


	playtest_launch_android :: proc(
		L: ^vm.State,
		service: ^PlaytestService,
		launch: Playtest_Launch,
		path: string,
		map_owned: bool,
	) -> (
		i32,
		bool,
	) {
		args: [dynamic]string
		defer delete(args)


		port := fmt.tprintf("%d", launch.port)

		switch launch.mode {
		case .Singleplayer, .Pair:
			append(
				&args,
				"--singleplayer",
				"--playtest-host",
				"--map",
				path,
				"--username",
				"SinglePlayer",
			)
		case .Server_Only:
			append(
				&args,
				"--server",
				"--window",
				"--playtest-host",
				"--map",
				path,
				"--address",
				launch.address,
				"--port",
				port,
			)
		case .Client_Only:
			append(
				&args,
				"--client",
				"--playtest-host",
				"--address",
				launch.address,
				"--port",
				port,
			)
		}

		failure, launched := android_playtest_launch(args[:])
		if !launched {
			playtest_abandon_map(service, path, map_owned)
			playtest_set_error(service, failure)
			vm.PushBoolean(L, false)
			return 1, true
		}

		playtest_record_android(service, path, launch.mode)
		if map_owned {delete(path)}
		vm.PushBoolean(L, true)
		return 1, true
	}
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
		launch := playtest_default_launch(.Pair)
		launch.map_path = vm.ArgOptionalString(L, 2)
		if vm.ArgOptionalBoolean(L, 3, false) {
			launch.mode = .Singleplayer
		}
		if !playtest_check_map_path(L, method, launch.map_path) {return 1, true}
		return playtest_launch(L, service, launch)

	case "StartServer":
		launch := playtest_default_launch(.Server_Only)
		launch.map_path = vm.ArgOptionalString(L, 2)
		launch.headless = vm.ArgOptionalBoolean(L, 3, true)
		if !playtest_check_map_path(L, method, launch.map_path) {return 1, true}
		return playtest_launch(L, service, launch)

	case "StartClient":
		launch := playtest_default_launch(.Client_Only)
		launch.address = vm.ArgOptionalString(L, 2, PLAYTEST_ADDRESS)
		port_number := vm.ArgOptionalNumber(L, 3, f64(PLAYTEST_PORT))
		if port_number < 1 || port_number > 65535 {
			return vm.RaiseError(
					L,
					"PlaytestService:StartClient port must be between 1 and 65535",
				),
				true
		}
		launch.port = u16(i64(port_number))
		return playtest_launch(L, service, launch)

	case "StartSinglePlayer":
		launch := playtest_default_launch(.Singleplayer)
		launch.map_path = vm.ArgOptionalString(L, 2)
		if !playtest_check_map_path(L, method, launch.map_path) {return 1, true}
		return playtest_launch(L, service, launch)

	case "Stop":
		vm.PushBoolean(L, playtest_stop(service))
		return 1, true
	}
	return 0, false
}

playtest_step :: proc(object: ^classes.Object, ctx: ^classes.Class_Step_Context) {
	service := cast(^PlaytestService)object
	if service == nil || !service.running {return}
	playtest_refresh(service)
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
		_step = playtest_step,
		_step_phase = .Update,
	)
}
