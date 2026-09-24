#+build !js
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import target "engine/target"

Startup_Options :: struct {
	address: string,
	port:    u16,
	map_path: string,
	playtest: bool,
	update_check: bool,
	no_update: bool,
	window: bool,
	mode:    target.Mode,
}

startup_options :: proc() -> (Startup_Options, bool) {
	options := Startup_Options {
		port = 1234,
		mode = target.ACTIVE,
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
		case "--map":
			if index + 1 >= len(os.args) {fmt.eprintln("--map requires a .kine file path"); return options, false}
			index += 1
			options.map_path = os.args[index]
		case "--playtest":
			if index + 1 >= len(os.args) {fmt.eprintln("--playtest requires a .kine file path"); return options, false}
			index += 1
			options.map_path = os.args[index]
			options.playtest = true
		case "--server":
			options.mode = target.Mode.Server
		case "--client":
			options.mode = target.Mode.Client
		case "--editor":
			options.mode = target.Mode.Editor
case "--script":
			if index + 1 >= len(os.args) {fmt.eprintln("--script requires a file path"); return options, false}
			index += 1
		case "--update":
			options.update_check = true
		case "--no-update":
			options.no_update = true
		case "--window":
			options.window = true
		case:
			if strings.has_suffix(arg, ".kine") || strings.has_suffix(arg, ".KINE") {
				if options.map_path != "" {fmt.eprintln("Only one .kine file can be loaded"); return options, false}
				options.map_path = arg
				options.playtest = true
			} else {
				fmt.eprintf("Unknown argument: %s\n", arg)
				return options, false
			}
		}
	}
	if options.mode == target.Mode.Server && options.address == "" {
		options.address = "0.0.0.0"
	} else if options.address == "" {
		options.address = "127.0.0.1"
	}
	return options, true
}
