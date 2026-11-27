#+build !js

package services

import "base:runtime"
import "core:strings"

telemetry_module_name :: proc(value: string, allocator: runtime.Allocator) -> string {
	if value == "" {return strings.clone("unknown", allocator)}
	out := make([dynamic]u8, 0, min(len(value), 96), allocator)
	defer delete(out)
	for ch in transmute([]u8)value {
		if len(out) >= 96 {break}
		if (ch >= 'a' && ch <= 'z') ||
		   (ch >= 'A' && ch <= 'Z') ||
		   (ch >= '0' && ch <= '9') ||
		   ch == '_' ||
		   ch == '-' ||
		   ch == '.' {
			append(&out, ch)
		} else if ch == '/' || ch == '\\' {
			append(&out, '.')
		}
	}
	if len(out) == 0 {return strings.clone("unknown", allocator)}
	return strings.clone(string(out[:]), allocator)
}

Telemetry_Parse_Luau_Source :: proc(
	fallback, error_text: string,
	allocator: runtime.Allocator,
) -> (
	module: string,
	line: int,
) {
	module = telemetry_module_name(fallback, allocator)
	line = 0
	for i in 0 ..< len(error_text) {
		if error_text[i] != ':' {continue}
		j := i + 1
		value := 0
		for j < len(error_text) && error_text[j] >= '0' && error_text[j] <= '9' {
			value = value * 10 + int(error_text[j] - '0')
			if value > 10000000 {break}
			j += 1
		}
		if value <= 0 ||
		   value > 10000000 ||
		   j >= len(error_text) ||
		   error_text[j] != ':' {continue}

		start := 0
		if cut := strings.last_index_byte(error_text[:i], '\n'); cut >= 0 {start = cut + 1}
		prefix := error_text[start:i]
		internal := strings.last_index(prefix, "@internal/")
		source_len := len("@internal/")
		if internal < 0 {
			internal = strings.last_index(prefix, "@internal\\")
			source_len = len("@internal\\")
		}
		if internal >= 0 {
			raw := strings.trim_space(prefix[internal + source_len:])
			if raw != "" {
				if strings.has_suffix(raw, ".luau") {
					raw = raw[:len(raw) - len(".luau")]
				} else if strings.has_suffix(raw, ".lua") {
					raw = raw[:len(raw) - len(".lua")]
				}
				candidate := telemetry_module_name(raw, allocator)
				delete(module, allocator)
				module = candidate
			}
			return module, value
		}
		if line == 0 {line = value}
	}
	return module, line
}

Telemetry_Sanitize_Luau_Error :: proc(raw: string, allocator: runtime.Allocator) -> string {
	lines := strings.split(raw, "\n", allocator)
	defer delete(lines, allocator)
	safe_lines := make([dynamic]string, 0, min(len(lines), 32), allocator)
	defer {
		for line in safe_lines {delete(line, allocator)}
		delete(safe_lines)
	}
	size := 0
	for original in lines {
		if size >= 4096 {break}
		trimmed := strings.trim_space(original)
		if trimmed == "" {continue}
		if len(trimmed) > 384 {trimmed = trimmed[:384]}
		safe := Telemetry_Sanitize_Native_Line(trimmed, allocator, internal_luau_error = true)
		if safe == "" {continue}
		if size + len(safe) + 1 > 4096 {
			delete(safe, allocator)
			break
		}
		append(&safe_lines, safe)
		size += len(safe) + 1
	}
	if len(safe_lines) == 0 {return strings.clone("Error details were filtered", allocator)}
	return strings.join(safe_lines[:], "\n", allocator)
}
