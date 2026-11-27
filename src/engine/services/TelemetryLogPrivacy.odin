#+build !js

package services

import "base:runtime"
import "core:strings"

telemetry_machine_keywords := [?]string {
	"cpu model",
	"cpu name",
	"cpu brand",
	"cpu:",
	"processor model",
	"processor name",
	"processor:",
	"logical cores",
	"physical cores",
	"gpu model",
	"gpu name",
	"gpu:",
	"gpu vendor",
	"graphics card",
	"graphics adapter",
	"graphics device:",
	"device name:",
	"devicename",
	"device_name",
	"nvidia geforce",
	"geforce rtx",
	"geforce gtx",
	"nvidia rtx",
	"nvidia gtx",
	"rtx 20",
	"rtx 30",
	"rtx 40",
	"rtx 50",
	"amd radeon",
	"radeon rx",
	"intel(r) core",
	"intel core",
	"amd ryzen",
	"vram:",
	"ram:",
	"system ram",
	"hardware:",
	"gpu=",
	"cpu=",
	"gpu device=",
	"cpu core count",
	"memory size:",
	"total memory:",
	"memory capacity",
	"driver version:",
	"driver version=",
	"driver_version",
	"pci device",
	"pci vendor",
	"subsystem id",
	"serial number",
	"hardware id",
	"machine id",
	"mac address",
}

telemetry_secret_keywords := [?]string {
	"password",
	"passwd",
	"authorization",
	"bearer ",
	"cookie",
	"access_token",
	"access token",
	"api_key",
	"api key",
	"private_key",
	"private key",
	"secret",
	"session token",
	"refresh_token",
	"session_id",
	"session id",
	"username",
	"connected as ",
	"accepted ",
	"player name",
	"user script",
	"script traceback",
	"scriptcontext",
	"[script]",
	"[scriptcontext]",
	"luau startup failed",
	"rbxassetid://",
	"rbxasset://",
	"mxc://",
}


telemetry_machine_information :: proc(lower: string) -> bool {
	for keyword in telemetry_machine_keywords {
		if strings.contains(lower, keyword) {return true}
	}
	return false
}

telemetry_secret_information :: proc(lower: string, internal_luau_error: bool = false) -> bool {
	for keyword in telemetry_secret_keywords {
		if internal_luau_error &&
		   (keyword == "script traceback" || keyword == "scriptcontext") {continue}
		if strings.contains(lower, keyword) {return true}
	}
	return false
}

telemetry_private_token :: proc(token: string) -> bool {
	if len(token) == 0 {return false}
	if token[0] == '/' || token[0] == '~' || token[0] == '\\' {return true}
	for ch, index in transmute([]u8)token {
		if ch == '@' || ch == '\\' {return true}
		if ch == '/' {
			if index > 0 {return true}
		}
		if ch == ':' && index > 0 && index + 1 < len(token) {
			if token[index + 1] == '/' || token[index + 1] == '\\' {return true}
		}
	}
	return false
}

Telemetry_Sanitize_Native_Line :: proc(
	raw: string,
	allocator: runtime.Allocator,
	internal_luau_error: bool = false,
) -> string {
	if len(raw) == 0 || len(raw) > 1024 {return ""}
	lower := strings.to_lower(raw, allocator)
	defer delete(lower, allocator)
	if telemetry_machine_information(lower) ||
	   telemetry_secret_information(lower, internal_luau_error) {return ""}

	result := make([dynamic]u8, 0, min(len(raw), 384), allocator)
	defer delete(result)
	for start := 0; start < len(raw); {
		ch := raw[start]
		if ch == ' ' || ch == '\t' {
			if len(result) < 384 {append(&result, ' ')}
			start += 1
			continue
		}
		end := start
		for end < len(raw) && raw[end] != ' ' && raw[end] != '\t' {end += 1}
		token := raw[start:end]
		if len(result) >= 384 {return ""}
		if telemetry_private_token(token) {
			append(&result, ..transmute([]u8)string("[redacted]"))
		} else {
			for byte in transmute([]u8)token {
				if byte < 32 || byte > 126 {continue}
				if len(result) >= 384 {return ""}
				append(&result, byte)
			}
		}
		start = end
	}
	trimmed := strings.trim_space(string(result[:]))
	if len(trimmed) < 3 {return ""}
	return strings.clone(trimmed, allocator)
}
