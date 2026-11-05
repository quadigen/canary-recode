#+build !js
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import target "engine/target"

Startup_Options :: struct {
	address:      string,
	port:         u16,
	map_path:     string,
	playtest:     bool,
	singleplayer: bool,
	update_check: bool,
	no_update:    bool,
	window:       bool,
	mode:         target.Mode,
	standalone:   bool,
	username:     string,
}

startup_options :: proc() -> (Startup_Options, bool) {
	return startup_options_for(os.args)
}

startup_options_for :: proc(args: []string) -> (Startup_Options, bool) {
	options := Startup_Options {
		address = CONFIG_ADDRESS,
		port    = 1234,
		mode    = target.ACTIVE,
	}
	address_given := false
	port_given := false
	role_given := false
	if CONFIG_PORT != 0 {
		if CONFIG_PORT < 1 ||
		   CONFIG_PORT >
			   65535 {fmt.eprintf("Config port %d must be between 1 and 65535\n", CONFIG_PORT); return options, false}
		options.port = u16(CONFIG_PORT)
	}
	if CONFIG_MODE != "" {
		switch CONFIG_MODE {
		case "editor":
			options.mode = target.Mode.Editor
		case "client", "player":
			options.mode = target.Mode.Client
		case "server":
			options.mode = target.Mode.Server
		case:
			fmt.eprintf("Config mode %q must be editor, client, or server\n", CONFIG_MODE)
			return options, false
		}
	}
	if self, self_ok := self_payload(); self_ok {
		if self.address != "" {
			options.address = self.address
		}
		if self.port != 0 {
			options.port = self.port
		}
		switch self.mode {
		case .Server, .Client:
			options.mode = self.mode
		case .Singleplayer:
			options.singleplayer = true
			options.no_update = true
		case .Editor, .Standalone:
		}
	}
	for index := 1; index < len(args); index += 1 {
		arg := args[index]
		switch arg {
		case "--address":
			if index + 1 >=
			   len(args) {fmt.eprintln("--address requires a value"); return options, false}
			index += 1
			options.address = args[index]
			address_given = true
		case "--port":
			if index + 1 >=
			   len(args) {fmt.eprintln("--port requires a value"); return options, false}
			index += 1
			value, ok := strconv.parse_int(args[index])
			if !ok ||
			   value < 1 ||
			   value >
				   65535 {fmt.eprintln("--port must be between 1 and 65535"); return options, false}
			options.port = u16(value)
			port_given = true
		case "--map":
			if index + 1 >=
			   len(args) {fmt.eprintln("--map requires a .kine file path"); return options, false}
			index += 1
			options.map_path = args[index]
		case "--playtest":
			if index + 1 >=
			   len(
				   args,
			   ) {fmt.eprintln("--playtest requires a .kine file path"); return options, false}
			index += 1
			options.map_path = args[index]
			options.playtest = true
		case "--playtest-host":
			options.playtest = true
		case "--singleplayer":
			options.singleplayer = true
		case "--server":
			options.mode = target.Mode.Server
			role_given = true
		case "--client":
			options.mode = target.Mode.Client
			role_given = true
		case "--editor":
			options.mode = target.Mode.Editor
			role_given = true
		case "--script":
			if index + 1 >=
			   len(args) {fmt.eprintln("--script requires a file path"); return options, false}
			index += 1
		case "--update":
			options.update_check = true
		case "--no-update":
			options.no_update = true
		case "--window":
			options.window = true
		case "--username":
			if index + 1 >= len(args) {
				fmt.eprintln("--username requires a value")
				return options, false
			}
			index += 1
			options.username = args[index]
		case:
			if strings.has_prefix(arg, "kinemium://") {
				query_start := strings.index(arg, "?")
				if query_start >= 0 {
					query := arg[query_start + 1:]
					parts := strings.split(query, "&")
					defer delete(parts)
					for p in parts {
						kv := strings.split(p, "=")
						if len(kv) == 2 {
							key := kv[0]; val := kv[1]
							if key == "username" {options.username = val}
							if key == "address" {options.address = val}
							if key == "port" {
								v, ok := strconv.parse_int(val)
								if ok && v >= 1 && v <= 65535 {options.port = u16(v)}
							}
							delete(kv)
						}
					}
				}
				options.mode = target.Mode.Client
				role_given = true
			} else if strings.has_suffix(arg, ".kine") || strings.has_suffix(arg, ".KINE") {
				if options.map_path !=
				   "" {fmt.eprintln("Only one .kine file can be loaded"); return options, false}
				options.map_path = arg
				options.playtest = true
			} else {
				fmt.eprintf("Unknown argument: %s\n", arg)
				return options, false
			}
		}
	}
	_, _, has_embedded := embedded_map()
	if options.singleplayer {
		if role_given {
			fmt.eprintln("--singleplayer is its own mode; drop --server/--client/--editor")
			return options, false
		}
		if address_given || port_given {
			fmt.eprintln("--singleplayer does not use the network; drop --address/--port")
			return options, false
		}
		if options.map_path == "" && !has_embedded {
			fmt.eprintln("--singleplayer requires --map with a .kine file path")
			return options, false
		}
		options.mode = target.Mode.Singleplayer
		options.address = ""
	}

	options.standalone =
		options.mode == target.Mode.Client && options.address == "" && has_embedded
	if options.standalone {
		options.address = ""
	}
	if options.singleplayer {
	} else if options.mode == target.Mode.Server && options.address == "" {
		options.address = "0.0.0.0"
	} else if options.address == "" && !options.standalone {
		options.address = "127.0.0.1"
	}
	if options.username == "" {
		if options.mode == target.Mode.Client || options.singleplayer {
			options.username = "Player"
		} else {
			options.username = "Server"
		}
	}
	return options, true
}
