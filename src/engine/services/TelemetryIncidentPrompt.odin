#+build !js

package services

import target "../target"
import "core:c"
import sdl3 "vendor:sdl3"

Telemetry_Editor_Luau_Failure :: proc(module: string = "", error_text: string = "") {
	if module != "" || error_text != "" {Telemetry_Editor_Set_Error(module, error_text)}
	if !target.is_editor() || target.is_playtest() {return}
	if !Telemetry_Incident_Mark_Prompt() {return}

	buttons := [2]sdl3.MessageBoxButtonData {
		{flags = {.ESCAPEKEY_DEFAULT}, buttonID = 0, text = "No"},
		{flags = {.RETURNKEY_DEFAULT}, buttonID = 1, text = "Yes"},
	}
	dialog := sdl3.MessageBoxData {
		flags      = {.WARNING},
		window     = sdl3.GetKeyboardFocus(),
		title      = "Kinemium Editor Error",
		message    = "An internal Luau editor error occurred.\n\nSend a diagnostic report containing the retained sanitized native engine logs (up to 64 KiB) and engine version?\n\nLuau prints, user-script output, file paths, hardware specifications and likely secrets are excluded.\n\nChoose Yes to send this report now. No discards it and suppresses this session's log upload.",
		numbuttons = 2,
		buttons    = &buttons[0],
	}
	button_id: c.int = 0
	accepted := sdl3.ShowMessageBox(dialog, &button_id) && button_id == 1
	Telemetry_Incident_Finish(accepted)
}
