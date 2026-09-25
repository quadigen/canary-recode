#+build !js
package main

import vm "engine/vm"
import engine_runtime "engine/runtime"
import services "engine/services"

CONFIG_ADDRESS :: #config(KINE_ADDRESS, "")
CONFIG_PORT    :: #config(KINE_PORT, 0)
CONFIG_MODE    :: #config(KINE_MODE, "")
CONFIG_EMBED   :: #config(KINE_EMBED, "")

when CONFIG_EMBED != "" {
	EMBEDDED_MAP_BYTES: []u8 = #load(CONFIG_EMBED)
}

g_self_checked: bool
g_self_payload: services.Payload
g_self_ok: bool

self_payload :: proc() -> (services.Payload, bool) {
	if !g_self_checked {
		g_self_checked = true
		g_self_payload, g_self_ok = services.Payload_Read_Self()
	}
	return g_self_payload, g_self_ok
}

embedded_map :: proc() -> (data: []u8, name: string, ok: bool) {
	if self, self_ok := self_payload(); self_ok && len(self.map_bytes) > 0 {
		return self.map_bytes, self.name, true
	}
	when CONFIG_EMBED != "" {
		return EMBEDDED_MAP_BYTES, CONFIG_EMBED, true
	}
	return nil, "", false
}

load_game_map :: proc(
	environment: ^engine_runtime.Environment,
	script_vm: ^vm.VM,
	options: Startup_Options,
) -> bool {
	if options.map_path != "" {
		return engine_runtime.Load_Map(environment, script_vm, options.map_path)
	}
	if data, name, ok := embedded_map(); ok {
		return engine_runtime.Load_Map_From_Data(environment, script_vm, data, name)
	}
	return true
}