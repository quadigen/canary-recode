#+build !js

package services

import "base:runtime"
import "core:bytes"
import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

import globals "../global"
import http "../util/odin-http"
import http_client "../util/odin-http/client"

TELEMETRY_URL :: "https://ktelemetry.quadigen.com/v1/logs"
TELEMETRY_BATCH_LIMIT :: 16
TELEMETRY_QUEUE_LIMIT :: 64
TELEMETRY_MAX_LOG_BYTES :: 65536

Telemetry_Event :: struct {
	level:        string,
	subsystem:    string,
	code:         string,
	version:      string,
	count:        int,
	message:      string,
	error_module: string,
	error_line:   int,
	error_text:   string,
}

Telemetry_Wire_Event :: struct {
	level:     string,
	subsystem: string,
	code:      string,
	version:   string,
	count:     int,
}

Telemetry_Wire_Log_Event :: struct {
	level:     string,
	subsystem: string,
	code:      string,
	version:   string,
	count:     int,
	message:   string,
}

Telemetry_Wire_Incident_Event :: struct {
	level:        string,
	subsystem:    string,
	code:         string,
	version:      string,
	count:        int,
	message:      string,
	error_module: string,
	error_line:   int,
	error_text:   string,
}

Telemetry_State :: struct {
	mu:                      sync.Mutex,
	enabled:                 bool,
	quit:                    bool,
	incident_capture:        bool,
	incident_prompted:       bool,
	incident_error_module:   string,
	incident_error_line:     int,
	incident_error_text:     string,
	suppress_session_upload: bool,
	session_report_success:  bool,
	pending:                 [dynamic]Telemetry_Event,
	incident_pending:        [dynamic]Telemetry_Event,
	session_lines:           [dynamic]string,
	session_bytes:           int,
}

telemetry_state: ^Telemetry_State
telemetry_thread: ^thread.Thread

telemetry_snapshot :: proc(lines: []string, limit: int) -> string {
	if len(lines) == 0 {return ""}
	start := len(lines)
	bytes: int
	for index := len(lines); index > 0; index -= 1 {
		line := lines[index - 1]
		if bytes + len(line) + 1 > limit {break}
		bytes += len(line) + 1
		start = index - 1
	}
	if start == len(lines) {return ""}
	return strings.join(lines[start:], "\n", runtime.heap_allocator())
}

telemetry_clear_session :: proc(state: ^Telemetry_State) {
	for line in state.session_lines {delete(line, runtime.heap_allocator())}
	clear(&state.session_lines)
	state.session_bytes = 0
}

telemetry_ensure_state :: proc() -> ^Telemetry_State {
	if telemetry_state != nil {return telemetry_state}
	state := new(Telemetry_State, runtime.heap_allocator())
	state.pending = make(
		[dynamic]Telemetry_Event,
		0,
		TELEMETRY_QUEUE_LIMIT,
		runtime.heap_allocator(),
	)
	state.incident_pending = make([dynamic]Telemetry_Event, 0, 4, runtime.heap_allocator())
	state.session_lines = make([dynamic]string, 0, 128, runtime.heap_allocator())
	telemetry_state = state
	telemetry_thread = thread.create_and_start_with_data(state, telemetry_worker_proc)
	return state
}

Telemetry_Incident_Bootstrap :: proc() {
	state := telemetry_ensure_state()
	sync.mutex_lock(&state.mu)
	state.incident_capture = true
	sync.mutex_unlock(&state.mu)
	Telemetry_LogCapture_Install()
}

telemetry_post :: proc(events: []Telemetry_Event) -> bool {
	if len(events) == 0 {return true}

	request: http_client.Request
	http_client.request_init(&request, .Post)
	defer http_client.request_destroy(&request)
	request.public_only = true
	http.headers_set_content_type_string(&request.headers, "application/json")
	if _, err := bytes.buffer_write_string(&request.body, "{\"events\":[");
	   err != nil {return false}
	for event, index in events {
		if index > 0 {
			if _, err := bytes.buffer_write_string(&request.body, ","); err != nil {return false}
		}
		data: []u8
		marshal_err: json.Marshal_Error
		if event.code == "EDITOR_LUAU_FAILURE" && event.error_text != "" {
			data, marshal_err = json.marshal(
				Telemetry_Wire_Incident_Event {
					level = event.level,
					subsystem = event.subsystem,
					code = event.code,
					version = event.version,
					count = event.count,
					message = event.message,
					error_module = event.error_module,
					error_line = event.error_line,
					error_text = event.error_text,
				},
			)
		} else if event.message != "" {
			data, marshal_err = json.marshal(
				Telemetry_Wire_Log_Event {
					level = event.level,
					subsystem = event.subsystem,
					code = event.code,
					version = event.version,
					count = event.count,
					message = event.message,
				},
			)
		} else {
			data, marshal_err = json.marshal(
				Telemetry_Wire_Event {
					level = event.level,
					subsystem = event.subsystem,
					code = event.code,
					version = event.version,
					count = event.count,
				},
			)
		}
		if marshal_err != nil {return false}
		_, write_err := bytes.buffer_write(&request.body, data)
		delete(data)
		if write_err != nil {return false}
	}
	if _, err := bytes.buffer_write_string(&request.body, "]}"); err != nil {return false}
	response, request_err := http_client.request(&request, TELEMETRY_URL)
	if request_err != nil {return false}
	success := http.status_is_success(response.status)
	http_client.response_destroy(&response)
	return success
}

telemetry_worker_proc :: proc(user_data: rawptr) {
	context.allocator = runtime.heap_allocator()
	state := cast(^Telemetry_State)user_data
	batch := make([dynamic]Telemetry_Event, 0, TELEMETRY_BATCH_LIMIT)
	defer delete(batch)
	for {
		sync.mutex_lock(&state.mu)
		quitting := state.quit
		urgent := len(state.incident_pending) > 0
		if urgent {
			for event in state.incident_pending {
				if len(batch) >= TELEMETRY_BATCH_LIMIT {break}
				append(&batch, event)
			}
			remove_range(&state.incident_pending, 0, len(batch))
		} else if quitting {
			for event in state.pending {
				if len(batch) >= TELEMETRY_BATCH_LIMIT {break}
				append(&batch, event)
			}
			remove_range(&state.pending, 0, len(batch))
		}
		sync.mutex_unlock(&state.mu)
		if len(batch) > 0 {
			success := telemetry_post(batch[:])
			for event in batch {
				if event.code == "ENGINE_SESSION_END" &&
				   success {state.session_report_success = true}
				if success &&
				   event.message != "" &&
				   (event.code == "ENGINE_SESSION_RECOVERED" ||
						   strings.has_prefix(
							   event.code,
							   "NATIVE_SIG",
						   )) {Telemetry_Journal_Confirm_Recovery()}
				if event.message != "" {delete(event.message, runtime.heap_allocator())}
				if event.error_module != "" {delete(event.error_module, runtime.heap_allocator())}
				if event.error_text != "" {delete(event.error_text, runtime.heap_allocator())}
			}
			clear(&batch)
		} else if quitting {
			break
		} else {
			time.sleep(100 * time.Millisecond)
		}
	}
}

Telemetry_Bootstrap_Consent :: proc() {
	data, ok := studio_read_settings()
	if !ok {return}
	defer delete(data)
	value, parse_err := json.parse_string(string(data))
	if parse_err != nil {return}
	defer json.destroy_value(value)
	object, is_object := value.(json.Object)
	if !is_object {return}
	if setting, exists := object["telemetryEnabled"]; exists {
		if enabled, is_bool := setting.(json.Boolean); is_bool && enabled {
			Telemetry_Set_Enabled(true)
		}
	}
}

Telemetry_Set_Enabled :: proc(enabled: bool) {
	if telemetry_state == nil && !enabled {return}
	state := telemetry_ensure_state()
	if enabled {
		Telemetry_Crash_Install()
		crash_code := Telemetry_Crash_Read_Pending()
		previous := Telemetry_Journal_Start()
		sync.mutex_lock(&state.mu)
		state.enabled = true
		if previous != "" {
			code := crash_code if crash_code != "" else "ENGINE_SESSION_RECOVERED"
			append(
				&state.incident_pending,
				Telemetry_Event {
					level = "error",
					subsystem = "engine",
					code = code,
					version = globals.RUNTIME_VERSION_DISPLAY,
					count = 1,
					message = previous,
				},
			)
		} else if crash_code != "" {
			append(
				&state.incident_pending,
				Telemetry_Event {
					level = "error",
					subsystem = "engine",
					code = crash_code,
					version = globals.RUNTIME_VERSION_DISPLAY,
					count = 1,
				},
			)
		}
		sync.mutex_unlock(&state.mu)
		Telemetry_LogCapture_Install()
		return
	}
	sync.mutex_lock(&state.mu)
	state.enabled = false
	for event in state.pending {
		if event.message != "" {delete(event.message, runtime.heap_allocator())}
	}
	clear(&state.pending)
	if !state.incident_capture {telemetry_clear_session(state)}
	stop_capture := !state.incident_capture
	sync.mutex_unlock(&state.mu)
	Telemetry_Journal_Stop(true, true)
	Telemetry_Crash_Uninstall()
	if stop_capture {Telemetry_LogCapture_Uninstall()}
}

Telemetry_Report :: proc(subsystem, code: string, level: string = "error") {
	state := telemetry_state
	if state == nil {return}
	switch code {
	case "MAP_LOAD_FAILED",
	     "REPLICATION_START_FAILED",
	     "VULKAN_DEVICE_LOST",
	     "GRAPHICS_INIT_FAILED",
	     "MATERIAL_COMPILATION_FAILED",
	     "UPDATE_CHECK_FAILED",
	     "ENGINE_STARTUP_FAILED",
	     "NATIVE_SIGSEGV",
	     "NATIVE_SIGBUS",
	     "NATIVE_SIGILL",
	     "NATIVE_SIGABRT",
	     "NATIVE_SIGFPE":
	case:
		return
	}
	switch subsystem {
	case "renderer", "physics", "network", "luau", "editor", "loader", "update", "engine":
	case:
		return
	}
	if level != "error" && level != "warning" && level != "info" {return}
	sync.mutex_lock(&state.mu)
	defer sync.mutex_unlock(&state.mu)
	if !state.enabled || state.quit {return}
	for &event in state.pending {
		if event.code == code &&
		   event.subsystem == subsystem &&
		   event.level == level &&
		   event.count < 50 {
			event.count += 1
			return
		}
	}
	if len(state.pending) >= TELEMETRY_QUEUE_LIMIT {return}
	append(
		&state.pending,
		Telemetry_Event {
			level = level,
			subsystem = subsystem,
			code = code,
			version = globals.RUNTIME_VERSION_DISPLAY,
			count = 1,
		},
	)
}

Telemetry_Record_Native_Line :: proc(raw: string) {
	state := telemetry_state
	if state == nil {return}
	cleaned := Telemetry_Sanitize_Native_Line(raw, runtime.heap_allocator())
	if cleaned == "" {return}
	sync.mutex_lock(&state.mu)
	defer sync.mutex_unlock(&state.mu)
	if state.quit || (!state.enabled && !state.incident_capture) {
		delete(cleaned, runtime.heap_allocator())
		return
	}
	for state.session_bytes + len(cleaned) + 1 > TELEMETRY_MAX_LOG_BYTES &&
	    len(state.session_lines) > 0 {
		first := state.session_lines[0]
		state.session_bytes -= len(first) + 1
		delete(first, runtime.heap_allocator())
		ordered_remove(&state.session_lines, 0)
	}
	append(&state.session_lines, cleaned)
	state.session_bytes += len(cleaned) + 1
	if state.enabled && !state.suppress_session_upload {
		last_half := ""
		if telemetry_journal_size + len(cleaned) + 1 > TELEMETRY_MAX_LOG_BYTES {
			last_half = telemetry_snapshot(state.session_lines[:], TELEMETRY_MAX_LOG_BYTES / 2)
		}
		Telemetry_Journal_Append(cleaned, last_half)
		if last_half != "" {delete(last_half, runtime.heap_allocator())}
	}
}

Telemetry_Editor_Set_Error :: proc(module, error_text: string) {
	state := telemetry_state
	if state == nil {return}
	allocator := runtime.heap_allocator()
	resolved_module, line := Telemetry_Parse_Luau_Source(module, error_text, allocator)
	cleaned := Telemetry_Sanitize_Luau_Error(error_text, allocator)
	sync.mutex_lock(&state.mu)
	defer sync.mutex_unlock(&state.mu)
	if !state.incident_capture || state.incident_prompted || state.quit {
		delete(resolved_module, allocator)
		delete(cleaned, allocator)
		return
	}
	if state.incident_error_module != "" {delete(state.incident_error_module, allocator)}
	if state.incident_error_text != "" {delete(state.incident_error_text, allocator)}
	state.incident_error_module = resolved_module
	state.incident_error_line = line
	state.incident_error_text = cleaned
}

Telemetry_Incident_Finish :: proc(approved: bool) {
	state := telemetry_state
	if state == nil {return}
	sync.mutex_lock(&state.mu)
	if approved && state.incident_capture && !state.quit {
		allocator := runtime.heap_allocator()
		module := state.incident_error_module
		detail := state.incident_error_text
		if module == "" {module = "unknown"}
		if detail == "" {detail = "Internal editor error reported without details"}
		header := fmt.aprintf(
			"[EditorError] module=%s line=%d\n[EditorError] %s",
			module,
			state.incident_error_line,
			detail,
			allocator,
		)
		limit := max(0, TELEMETRY_MAX_LOG_BYTES - len(header) - 1)
		snapshot := telemetry_snapshot(state.session_lines[:], limit)
		aggregate := strings.concatenate({header, "\n", snapshot}, allocator)
		delete(header, allocator)
		if snapshot != "" {delete(snapshot, allocator)}
		append(
			&state.incident_pending,
			Telemetry_Event {
				level = "error",
				subsystem = "editor",
				code = "EDITOR_LUAU_FAILURE",
				version = globals.RUNTIME_VERSION_DISPLAY,
				count = 1,
				message = aggregate,
				error_module = strings.clone(module, allocator),
				error_line = state.incident_error_line,
				error_text = strings.clone(detail, allocator),
			},
		)
		telemetry_clear_session(state)
	}
	if !approved {
		state.suppress_session_upload = true
		telemetry_clear_session(state)
	}
	if state.incident_error_module !=
	   "" {delete(state.incident_error_module, runtime.heap_allocator())}
	if state.incident_error_text !=
	   "" {delete(state.incident_error_text, runtime.heap_allocator())}
	state.incident_error_module = ""
	state.incident_error_text = ""
	state.incident_error_line = 0
	state.incident_capture = false
	stop_capture := !state.enabled
	if stop_capture {telemetry_clear_session(state)}
	sync.mutex_unlock(&state.mu)
	if !approved {Telemetry_Journal_Stop(true, true)}
	if stop_capture {Telemetry_LogCapture_Uninstall()}
}

Telemetry_Incident_Mark_Prompt :: proc() -> bool {
	state := telemetry_state
	if state == nil {return false}
	sync.mutex_lock(&state.mu)
	defer sync.mutex_unlock(&state.mu)
	if !state.incident_capture || state.incident_prompted || state.quit {return false}
	state.incident_prompted = true
	return true
}

Telemetry_Queue_Shutdown_Report :: proc(state: ^Telemetry_State) {
	if !state.enabled || state.suppress_session_upload {return}
	snapshot := telemetry_snapshot(state.session_lines[:], TELEMETRY_MAX_LOG_BYTES)
	if snapshot != "" {
		append(
			&state.pending,
			Telemetry_Event {
				level = "info",
				subsystem = "engine",
				code = "ENGINE_SESSION_END",
				version = globals.RUNTIME_VERSION_DISPLAY,
				count = 1,
				message = snapshot,
			},
		)
	}
}

Telemetry_Shutdown :: proc() {
	Telemetry_LogCapture_Uninstall()
	Telemetry_Crash_Uninstall()
	state := telemetry_state
	if state == nil {return}
	sync.mutex_lock(&state.mu)
	Telemetry_Queue_Shutdown_Report(state)
	state.quit = true
	sync.mutex_unlock(&state.mu)
	if telemetry_thread != nil {
		thread.join(telemetry_thread)
		thread.destroy(telemetry_thread)
		telemetry_thread = nil
	}
	Telemetry_Journal_Stop(
		state.session_report_success ||
		!state.enabled ||
		state.suppress_session_upload ||
		state.session_bytes == 0,
	)
	for event in state.pending {
		if event.message != "" {delete(event.message, runtime.heap_allocator())}
	}
	for event in state.incident_pending {
		if event.message != "" {delete(event.message, runtime.heap_allocator())}
		if event.error_module != "" {delete(event.error_module, runtime.heap_allocator())}
		if event.error_text != "" {delete(event.error_text, runtime.heap_allocator())}
	}
	if state.incident_error_module !=
	   "" {delete(state.incident_error_module, runtime.heap_allocator())}
	if state.incident_error_text !=
	   "" {delete(state.incident_error_text, runtime.heap_allocator())}
	telemetry_clear_session(state)
	delete(state.pending)
	delete(state.incident_pending)
	delete(state.session_lines)
	free(state, runtime.heap_allocator())
	telemetry_state = nil
}
