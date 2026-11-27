#+build js

package services

Telemetry_Set_Enabled :: proc(enabled: bool) {}
Telemetry_Report :: proc(subsystem, code: string, level: string = "error") {}
Telemetry_Shutdown :: proc() {}


Telemetry_Bootstrap_Consent :: proc() {}

Telemetry_Incident_Bootstrap :: proc() {}
Telemetry_Incident_Finish :: proc(approved: bool) {}
Telemetry_Incident_Mark_Prompt :: proc() -> bool {return false}

Telemetry_Editor_Luau_Failure :: proc(module: string = "", error_text: string = "") {}
Telemetry_Record_Native_Line :: proc(raw: string) {}
