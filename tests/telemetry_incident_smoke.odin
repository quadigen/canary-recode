package main

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:encoding/json"
import services "../src/engine/services"

main :: proc() {
	heap := runtime.heap_allocator()
	state := new(services.Telemetry_State, heap)
	state.session_lines = make([dynamic]string, 0, 128, heap)
	state.pending = make([dynamic]services.Telemetry_Event, 0, 64, heap)
	state.incident_pending = make([dynamic]services.Telemetry_Event, 0, 4, heap)
	state.incident_capture = true
	services.telemetry_state = state

	services.Telemetry_Record_Native_Line("[EditorService] editor cache loaded")
	services.Telemetry_Record_Native_Line("[Kine] GPU model: NVIDIA RTX 3050")
	services.Telemetry_Record_Native_Line("Luau startup failed in editor_ui: private data")
	assert(len(state.session_lines) == 1)
	assert(len(state.pending) == 0)
	assert(services.Telemetry_Incident_Mark_Prompt())
	assert(!services.Telemetry_Incident_Mark_Prompt())
	services.Telemetry_Incident_Finish(false)
	assert(len(state.incident_pending) == 0)
	assert(len(state.session_lines) == 0)
	assert(state.suppress_session_upload)

	state.suppress_session_upload = false
	state.incident_prompted = false
	state.incident_capture = true
	services.Telemetry_Editor_Set_Error(
		"editor_ui",
		"@internal/ui/layout.luau:143: attempt to index nil with 'Theme'\nstack traceback:\nScriptContext: internal task resumed\n@internal/ui/init.luau:12: in function 'render'",
	)
	assert(state.incident_error_module == "ui.layout")
	assert(state.incident_error_line == 143)
	assert(strings.contains(state.incident_error_text, "attempt to index nil with 'Theme'"))
	assert(strings.contains(state.incident_error_text, "ScriptContext: internal task resumed"))
	for index in 0 ..< 250 {
		line := fmt.aprintf("[EditorService] diagnostic line %d", index)
		services.Telemetry_Record_Native_Line(line)
		delete(line)
	}
	services.Telemetry_Record_Native_Line("[Renderer] native pipeline initialized")
	services.Telemetry_Record_Native_Line("[EditorService] failed opening /home/user/private.kine")
	services.Telemetry_Incident_Finish(true)
	assert(len(state.incident_pending) == 1)
	assert(state.incident_pending[0].code == "EDITOR_LUAU_FAILURE")
	assert(state.incident_pending[0].error_module == "ui.layout")
	assert(state.incident_pending[0].error_line == 143)
	assert(strings.contains(state.incident_pending[0].error_text, "attempt to index nil with 'Theme'"))
	assert(strings.contains(state.incident_pending[0].message, "[EditorError] module=ui.layout line=143"))
	wire := services.Telemetry_Wire_Incident_Event{
		level="error", subsystem="editor", code="EDITOR_LUAU_FAILURE",
		version="1.19.5-dev", count=1,
		message=state.incident_pending[0].message,
		error_module=state.incident_pending[0].error_module,
		error_line=state.incident_pending[0].error_line,
		error_text=state.incident_pending[0].error_text,
	}
	encoded, encode_error := json.marshal(wire)
	assert(encode_error == nil)
	assert(strings.contains(string(encoded), "\"error_line\":143"))
	assert(strings.contains(string(encoded), "\"error_module\":\"ui.layout\""))
	assert(strings.contains(string(encoded), "attempt to index nil with"))
	delete(encoded)
	assert(strings.contains(state.incident_pending[0].message, "attempt to index nil with 'Theme'"))
	assert(strings.contains(state.incident_pending[0].message, "[EditorService] diagnostic line 0"))
	assert(strings.contains(state.incident_pending[0].message, "[EditorService] diagnostic line 249"))
	assert(strings.contains(state.incident_pending[0].message, "[Renderer] native pipeline initialized"))
	assert(strings.contains(state.incident_pending[0].message, "[EditorService] failed opening [redacted]"))
	assert(!strings.contains(state.incident_pending[0].message, "/home/user/"))
	assert(len(state.session_lines) == 0)

	state.enabled = true
	for index in 0 ..< 300 {
		line := fmt.aprintf("[Renderer] frame build phase %d complete", index)
		services.Telemetry_Record_Native_Line(line)
		delete(line)
	}
	assert(len(state.pending) == 0)
	snapshot := services.telemetry_snapshot(state.session_lines[:], services.TELEMETRY_MAX_LOG_BYTES)
	assert(strings.contains(snapshot, "[Renderer] frame build phase 299 complete"))
	assert(strings.contains(snapshot, "\n"))
	delete(snapshot, heap)
	services.Telemetry_Queue_Shutdown_Report(state)
	assert(len(state.pending) == 1)
	assert(state.pending[0].code == "ENGINE_SESSION_END")
	assert(strings.contains(state.pending[0].message, "\n"))
	assert(!strings.contains(state.pending[0].message, "/home/"))
	delete(state.pending[0].message, heap)
	clear(&state.pending)

	for event in state.incident_pending {
		if event.message != "" {delete(event.message, heap)}
		if event.error_module != "" {delete(event.error_module, heap)}
		if event.error_text != "" {delete(event.error_text, heap)}
	}
	services.telemetry_clear_session(state)
	delete(state.incident_pending)
	delete(state.pending)
	delete(state.session_lines)
	services.telemetry_state = nil
	free(state, heap)
	fmt.println("TELEMETRY_INCIDENT_SMOKE_PASSED")
}
