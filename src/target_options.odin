#+build !js
package main

import "core:fmt"
import "core:os"
import "core:strconv"

Startup_Options :: struct {
	address: string,
	port:    u16,
}

startup_options :: proc(default_address: string) -> (Startup_Options, bool) {
	options := Startup_Options {
		address = default_address,
		port    = 1234,
	}
	for index := 1; index < len(os.args); index += 1 {
		arg := os.args[index]
		switch arg {
		case "--address":
			if index + 1 >=
			   len(os.args) {fmt.eprintln("--address requires a value"); return options, false}
			index += 1
			options.address = os.args[index]
		case "--port":
			if index + 1 >=
			   len(os.args) {fmt.eprintln("--port requires a value"); return options, false}
			index += 1
			value, ok := strconv.parse_int(os.args[index])
			if !ok ||
			   value < 1 ||
			   value >
				   65535 {fmt.eprintln("--port must be between 1 and 65535"); return options, false}
			options.port = u16(value)
		}
	}
	return options, true
}
