#+build !js
package services

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"
import "core:strings"
import sdl "vendor:sdl3"

TERMINAL_SESSION_LIMIT :: 8
TERMINAL_HISTORY_LIMIT :: 256
TERMINAL_INPUT_LIMIT :: 8192
TERMINAL_READ_LIMIT :: 65536

TerminalService_Class := classes.Class_Info {
	name   = "TerminalService",
	parent = &Service_Class,
}

Terminal_Session :: struct {
	native:        rawptr,
	process:       ^sdl.Process,
	input:         ^sdl.IOStream,
	output:        ^sdl.IOStream,
	history:       [dynamic]string,
	pending:       [TERMINAL_INPUT_LIMIT]u8,
	pending_start: int,
	pending_end:   int,
	running:       bool,
	exit_code:     i32,
}

TerminalService :: struct {
	using service: Service,
	sessions:      map[i64]^Terminal_Session,
	next_id:       i64,
}

TERMINAL_METHODS := [?]string {
	"CreateTerminal",
	"GetShellName",
	"Execute",
	"WriteInput",
	"ReadOutput",
	"GetHistory",
	"ClearHistory",
	"IsRunning",
	"GetExitCode",
	"CloseTerminal",
}

terminal_service_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(TerminalService)
	service.service = Service_Init(&TerminalService_Class, "TerminalService", data_model)
	service.object.archivable = false
	classes.Set_Can_Replicate(&service.object, false)
	service.sessions = make(map[i64]^Terminal_Session)
	return &service.object
}

terminal_session_update :: proc(session: ^Terminal_Session) {
	if !session.running {return}
	exited := false
	when ODIN_OS == .Windows {
		exited = terminal_windows_poll(session)
	} else {
		exited = sdl.WaitProcess(session.process, false, &session.exit_code)
	}
	if exited {
		session.running = false
		session.pending_start = 0
		session.pending_end = 0
		return
	}
	if session.pending_start < session.pending_end {
		data := session.pending[session.pending_start:session.pending_end]
		written := 0
		when ODIN_OS == .Windows {
			written = terminal_windows_write(session, data)
		} else {
			if session.input !=
			   nil {written = int(sdl.WriteIO(session.input, raw_data(data), uint(len(data))))}
		}
		session.pending_start += written
		if session.pending_start == session.pending_end {
			session.pending_start = 0
			session.pending_end = 0
		}
	}
}

terminal_session_clear_history :: proc(session: ^Terminal_Session) {
	for command in session.history {delete(command)}
	clear(&session.history)
}

terminal_session_destroy :: proc(session: ^Terminal_Session) {
	when ODIN_OS == .Windows {
		terminal_windows_destroy(session)
	} else {
		terminal_session_update(session)
		if session.running {
			_ = sdl.KillProcess(session.process, false)
			_ = sdl.WaitProcess(session.process, true, &session.exit_code)
		}
		sdl.DestroyProcess(session.process)
	}
	terminal_session_clear_history(session)
	delete(session.history)
	free(session)
}

terminal_service_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	service := cast(^TerminalService)object
	for _, session in service.sessions {terminal_session_destroy(session)}
	delete(service.sessions)
	classes.Object_Destroy(object)
	free(service)
}

terminal_session_create :: proc(directory: string, styled := false) -> ^Terminal_Session {
	when ODIN_OS == .Windows {
		return terminal_windows_create(directory)
	} else {
		args: [11]cstring
		when ODIN_OS == .Linux {
			args = {
				"/usr/bin/env",
				"TERM=dumb",
				"SHELL=/bin/sh",
				"/usr/bin/script",
				"-q",
				"-f",
				"-e",
				"/dev/null",
				nil,
				nil,
				nil,
			}
		} else when ODIN_OS == .Darwin {
			args = {
				"/usr/bin/env",
				"TERM=dumb",
				"SHELL=/bin/sh",
				"/usr/bin/script",
				"-q",
				"/dev/null",
				"/bin/sh",
				"-i",
				nil,
				nil,
				nil,
			}
		} else {
			return nil
		}
		if styled {
			for i := len(args) - 1; i > 3; i -= 1 {args[i] = args[i - 1]}
			args[3] = `PS1=$(printf "__KINE_PROMPT__%s:%s__KINE_HOME__%s__KINE_END__ " "$?" "$PWD" "$HOME" >&2)$ `
		}
		props := sdl.CreateProperties()
		if props == 0 {return nil}
		defer sdl.DestroyProperties(props)
		if !sdl.SetPointerProperty(props, sdl.PROP_PROCESS_CREATE_ARGS_POINTER, &args[0]) ||
		   !sdl.SetNumberProperty(
				   props,
				   sdl.PROP_PROCESS_CREATE_STDIN_NUMBER,
				   i64(sdl.ProcessIO.STDIO_APP),
			   ) ||
		   !sdl.SetNumberProperty(
				   props,
				   sdl.PROP_PROCESS_CREATE_STDOUT_NUMBER,
				   i64(sdl.ProcessIO.STDIO_APP),
			   ) ||
		   !sdl.SetBooleanProperty(props, sdl.PROP_PROCESS_CREATE_STDERR_TO_STDOUT_BOOLEAN, true) {
			return nil
		}
		if directory != "" {
			path := strings.clone_to_cstring(directory)
			defer delete(path)
			if !sdl.SetStringProperty(
				props,
				sdl.PROP_PROCESS_CREATE_WORKING_DIRECTORY_STRING,
				path,
			) {
				return nil
			}
		}
		process := sdl.CreateProcessWithProperties(props)
		if process == nil {return nil}
		session := new(Terminal_Session)
		session.process = process
		session.input = sdl.GetProcessInput(process)
		session.output = sdl.GetProcessOutput(process)
		session.running = true
		if session.input == nil || session.output == nil {
			terminal_session_destroy(session)
			return nil
		}
		return session
	}
}

terminal_session_queue :: proc(session: ^Terminal_Session, data: string, newline: bool) -> bool {
	terminal_session_update(session)
	extra := 0
	if newline {
		extra = 1
	}
	if !session.running || len(data) > TERMINAL_INPUT_LIMIT - extra || session.pending_end != 0 {
		return false
	}
	copy(session.pending[:], transmute([]u8)data)
	session.pending_end = len(data)
	if newline {
		when ODIN_OS == .Windows {
			session.pending[session.pending_end] = '\r'
		} else {
			session.pending[session.pending_end] = '\n'
		}
		session.pending_end += 1
	}
	terminal_session_update(session)
	return true
}

terminal_service_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	for method in TERMINAL_METHODS {
		if key == method {
			vm.PushUserdataMethod(L, key)
			return true
		}
	}
	return false
}

terminal_service_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	known := false
	for candidate in TERMINAL_METHODS {
		if candidate == method {known = true; break}
	}
	if !known {return 0, false}
	if !vm.ThreadHasSecurityCapability(L, datatypes.SECURITY_CAPABILITY_INTERNAL_TERMINAL) ||
	   vm.ThreadIsParallel(L) {
		return vm.RaiseError(L, "TerminalService requires trusted serial internal execution"), true
	}
	service := cast(^TerminalService)object
	if method == "CreateTerminal" {
		if len(service.sessions) >= TERMINAL_SESSION_LIMIT {
			return vm.RaiseError(L, "TerminalService session limit reached"), true
		}
		directory := ""
		if !vm.IsNoneOrNil(L, 2) {directory = vm.ArgString(L, 2)}
		if strings.contains(directory, "\x00") {
			return vm.RaiseError(L, "Invalid working directory"), true
		}
		styled := !vm.IsNoneOrNil(L, 3) && vm.ArgBoolean(L, 3)
		session := terminal_session_create(directory, styled)
		if session == nil {
			return vm.RaiseError(L, "Unable to start system terminal"), true
		}
		service.next_id += 1
		service.sessions[service.next_id] = session
		vm.PushNumber(L, f64(service.next_id))
		return 1, true
	}
	id_value := vm.ArgNumber(L, 2)
	if !(id_value >= 1 && id_value <= f64(service.next_id)) {
		return vm.RaiseError(L, "Unknown terminal session"), true
	}
	id := i64(id_value)
	if f64(id) != id_value {return vm.RaiseError(L, "Unknown terminal session"), true}
	session, ok := service.sessions[id]
	if !ok {return vm.RaiseError(L, "Unknown terminal session"), true}
	switch method {
	case "GetShellName":
		when ODIN_OS == .Windows {
			vm.PushString(L, "cmd")
		} else {
			vm.PushString(L, "sh")
		}
		return 1, true
	case "Execute":
		command := vm.ArgString(L, 3)
		if command == "" ||
		   strings.contains_any(command, "\r\n\x00") ||
		   len(command) > TERMINAL_INPUT_LIMIT - 2 {
			return vm.RaiseError(L, "Expected a single nonempty terminal command"), true
		}
		accepted := terminal_session_queue(session, command, true)
		if accepted {
			if len(session.history) >= TERMINAL_HISTORY_LIMIT {
				delete(session.history[0])
				ordered_remove(&session.history, 0)
			}
			append(&session.history, strings.clone(command))
		}
		vm.PushBoolean(L, accepted)
		return 1, true
	case "WriteInput":
		vm.PushBoolean(L, terminal_session_queue(session, vm.ArgString(L, 3), false))
		return 1, true
	case "ReadOutput":
		terminal_session_update(session)
		buffer: [TERMINAL_READ_LIMIT]u8
		count := 0
		when ODIN_OS == .Windows {
			count = terminal_windows_read(session, buffer[:])
		} else {
			count = int(sdl.ReadIO(session.output, &buffer[0], len(buffer)))
		}
		vm.PushBytes(L, buffer[:count])
		terminal_session_update(session)
		return 1, true
	case "GetHistory":
		vm.NewTable(L, len(session.history), 0)
		for command, index in session.history {
			vm.PushString(L, command)
			vm.RawSetIndex(L, -2, index + 1)
		}
		return 1, true
	case "ClearHistory":
		terminal_session_clear_history(session)
		return 0, true
	case "IsRunning":
		terminal_session_update(session)
		vm.PushBoolean(L, session.running)
		return 1, true
	case "GetExitCode":
		terminal_session_update(session)
		if session.running {vm.PushNil(L)} else {vm.PushNumber(L, f64(session.exit_code))}
		return 1, true
	case "CloseTerminal":
		terminal_session_destroy(session)
		delete_key(&service.sessions, id)
		return 0, true
	}
	return 0, false
}

Register_TerminalService_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&TerminalService_Class,
		terminal_service_construct,
		terminal_service_destroy,
		creatable = false,
		get = terminal_service_get,
		namecall = terminal_service_namecall,
		methods = TERMINAL_METHODS[:],
	)
}

Terminal_Service_Step :: proc(registry: ^Registry) {
	descriptor := Find_Service(registry, "TerminalService")
	if descriptor == nil || descriptor.object == nil {return}
	service := cast(^TerminalService)descriptor.object
	for _, session in service.sessions {terminal_session_update(session)}
}
